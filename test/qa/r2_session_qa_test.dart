// QA round 2 — scratch tests that PROVE defects in MeasurementSession.
// Every test asserts the CORRECT behaviour, so a failing test == a defect.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:health_station_lite/ble/health_device_models.dart';
import 'package:health_station_lite/ble/measurement_session.dart';
import 'package:health_station_lite/data/device_registry_store.dart';
import 'package:health_station_lite/models/device_models.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';
import 'package:health_station_lite/printing/receipt_content.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<int> ox(int spo2, int hr) => [0, 0, 0, hr, spo2]; // KS M6100P
List<int> bp(int sys, int dia, int pulse) {
  final v = List<int>.filled(16, 0);
  v[0] = 0x04;
  v[1] = sys & 0xFF;
  v[2] = (sys >> 8) & 0xFF;
  v[3] = dia & 0xFF;
  v[4] = (dia >> 8) & 0xFF;
  v[14] = pulse;
  return v;
}

List<int> scaleMain(double kg, {required bool locked}) {
  final raw = (kg * 100).round();
  final v = List<int>.filled(12, 0);
  v[0] = 0x33;
  v[1] = 0xCC;
  v[6] = locked ? 0x81 : 0x80;
  v[10] = (raw >> 8) & 0xFF;
  v[11] = raw & 0xFF;
  return v;
}

const _oxM = BleDeviceModel.KS_M6100P;
const _bpM = BleDeviceModel.Yuwell_BP_YE670D;
const _wM = BleDeviceModel.IF_B8B;

Future<void> registerAll() async {
  final reg = DeviceRegistryStore.instance;
  await reg.register(const RegisteredDevice(
      type: DeviceType.tensimeter, remoteId: 'A', name: 'Yuwell BP-YE670D'));
  await reg.register(const RegisteredDevice(
      type: DeviceType.pulseOximeter, remoteId: 'B', name: 'KS M6100P'));
  await reg.register(const RegisteredDevice(
      type: DeviceType.thermometer, remoteId: 'C', name: 'Yuwell HT-YHW'));
  await reg.register(const RegisteredDevice(
      type: DeviceType.weightScale, remoteId: 'D', name: 'IF_B8B'));
  await reg.register(const RegisteredDevice(
      type: DeviceType.gripStrength, remoteId: 'E', name: 'weixin-nini'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => initializeDateFormatting('id_ID'));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    MeasurementSession.debugResetCarryOver();
    await DeviceRegistryStore.instance.load();
    await registerAll();
  });

  // ── F-gate: silence measured from session start, not from first packet ──
  test('QA-GATE-OX: carry-over gate must not open before the new session has '
      'even received a packet (re-link latency > 2 s)', () async {
    final a = MeasurementSession(profile: const PersonProfile(name: 'A'));
    a.debugInjectPacket(ox(96, 70), _oxM); // A's finger in the oximeter
    a.dispose();

    final b = MeasurementSession(profile: const PersonProfile(name: 'B'));
    expect(b.oxArmed, isFalse);
    // New session re-attaches BLE: permissions, discoverServices, then the
    // first 1 s poll tick. No packet reaches B for > 2 s.
    await Future<void>.delayed(const Duration(milliseconds: 2100));
    b.debugTickGates();
    // A's finger is STILL clipped: polling resumes with A's values.
    for (var i = 0; i < 5; i++) {
      b.debugInjectPacket(ox(96, 70), _oxM);
    }
    // Correct: no release was ever observed, so A's values must not be
    // recorded/locked for B.
    expect(b.measurements.pulseOximeter.spo2, isNull,
        reason: 'previous person SpO2 leaked into next session');
    expect(b.stepOf(DeviceType.pulseOximeter), isNot(MeasureStep.done));
    b.dispose();
  });

  test('QA-GATE-SCALE: same for the scale (A still standing)', () async {
    final a = MeasurementSession(profile: const PersonProfile(name: 'A'));
    a.debugInjectPacket(scaleMain(72.0, locked: true), _wM);
    a.dispose();
    final b = MeasurementSession(profile: const PersonProfile(name: 'B'));
    expect(b.scaleArmed, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 2100));
    b.debugTickGates();
    b.debugInjectPacket(scaleMain(72.0, locked: false), _wM); // A still on it
    expect(b.measurements.weightScale.weight, isNull,
        reason: 'previous person weight leaked into next session');
    b.dispose();
  });

  // ── Grip: no hysteresis around the 2.0 kg threshold ─────────────────────
  test('QA-GRIP-NOISE: one squeeze with jitter around 2.0 kg = ONE attempt',
      () {
    final s = MeasurementSession(profile: const PersonProfile(name: 'G'));
    // Single real squeeze; force decays with sensor jitter near 2 kg.
    for (final f in [3.0, 12.0, 24.5, 15.0, 6.0, 2.1, 1.9, 2.2, 1.8, 2.0, 0.4]) {
      s.debugInjectGrip(f);
    }
    expect(s.gripAttempts, 1,
        reason: 'jitter produced spurious attempts: '
            '${s.measurements.gripStrength.toJson()}');
    expect(s.activeGripSide, GripSide.left);
    s.dispose();
  });

  // ── Grip: a squeeze is silently dropped when the selected side is full ──
  test('QA-GRIP-DROP: squeeze on a full side must be recorded, not dropped',
      () {
    final s = MeasurementSession(profile: const PersonProfile(name: 'G'));
    s.setGripSide(GripSide.right); // nurse starts with the right hand
    for (final kg in [20.0, 21.0, 22.0]) {
      s.debugInjectGrip(5);
      s.debugInjectGrip(kg);
      s.debugInjectGrip(0.5);
    }
    expect(s.gripAttempts, 3);
    // 4th squeeze (left hand). Side is still "right" (no auto switch R->L).
    s.debugInjectGrip(5);
    s.debugInjectGrip(17.5);
    s.debugInjectGrip(0.5);
    expect(s.gripAttempts, 4,
        reason: '17.5 kg squeeze was discarded: '
            '${s.measurements.gripStrength.toJson()}');
    s.dispose();
  });

  // ── Scale: 6 s acceptance timer survives the weight becoming unstable ──
  test('QA-SCALE-TIMER: lock timer must not finalise a weight that became '
      'unstable again', () async {
    final s = MeasurementSession(profile: const PersonProfile(name: 'W'));
    s.debugInjectPacket(scaleMain(60.0, locked: false), _wM);
    s.debugInjectPacket(scaleMain(60.2, locked: true), _wM); // starts 6 s timer
    await Future<void>.delayed(const Duration(seconds: 1));
    // Person shifts / second person leans on scale: unstable frames again.
    s.debugInjectPacket(scaleMain(75.4, locked: false), _wM);
    expect(s.isWeightLocked, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 5300));
    expect(s.stepOf(DeviceType.weightScale), isNot(MeasureStep.done),
        reason: 'unstable ${s.measurements.weightScale.weight} kg was locked');
    s.dispose();
  });

  // ── BMI from the 160 cm placeholder is printed as a real value ─────────
  test('QA-BMI-DEFAULT: receipt must not print BMI computed from the 160 cm '
      'placeholder height', () {
    final s = MeasurementSession(profile: const PersonProfile(name: 'NoHeight'));
    s.updateWeightScale(const WeightScaleData(weight: 70));
    expect(s.heightMissing, isTrue);
    final record = HealthRecord(
      id: 'R1',
      createdAt: DateTime(2026, 10, 18),
      profile: s.profile,
      measurements: s.measurements,
    );
    final lines = buildReceipt(record)
        .sections
        .expand((sec) => sec.lines)
        .map((l) => '${l.label}=${l.value}')
        .toList();
    expect(lines.where((l) => l.startsWith('IMT')), isEmpty,
        reason: 'receipt prints $lines although height is unknown '
            '(SATUSEHAT export already drops it)');
    s.dispose();
  });

  test('QA-COMPOSITION-HEIGHT: komposisi dari tinggi pengganti tidak disimpan', () {
    // Profil tanpa tinggi & L/P: timbangan menghitung lemak dengan 160 cm/laki-laki.
    final s = MeasurementSession(profile: const PersonProfile(name: 'X'));
    s.debugMarkCompositionProfileSent();
    s.updateWeightScale(const WeightScaleData(weight: 58.4, bodyFatPercent: 28.0));
    // Tinggi diketik belakangan → komposisi tadi tetap berasal dari 160 cm.
    s.updateOthers(const OthersMeasurementData(height: 150));
    final saved = s.measurementsForSave();
    expect(saved.weightScale.weight, 58.4);
    expect(saved.weightScale.bodyFatPercent, isNull);
    expect(saved.weightScale.bmi, closeTo(58.4 / (1.5 * 1.5), 1e-6));
    s.dispose();

    // Tinggi & L/P sudah ada saat profil dikirim ke timbangan → komposisi sah.
    final ok = MeasurementSession(
        profile: const PersonProfile(name: 'Y', gender: Gender.female, heightCm: 155));
    ok.debugMarkCompositionProfileSent();
    ok.updateWeightScale(const WeightScaleData(weight: 50, bodyFatPercent: 30.5));
    expect(ok.measurementsForSave().weightScale.bodyFatPercent, 30.5);
    ok.dispose();
  });

  // ── BP: no plausibility check before locking ───────────────────────────
  test('QA-BP-RANGE: implausible BP (SFLOAT NaN 0x07FF) must not lock', () {
    final s = MeasurementSession(profile: const PersonProfile(name: 'T'));
    s.debugInjectPacket(bp(0x07FF, 0x07FF, 0), _bpM);
    expect(s.stepOf(DeviceType.tensimeter), isNot(MeasureStep.done),
        reason: 'locked ${s.measurements.tensimeter.toJson()}');
    s.dispose();
  });

  // ── acceptNow on grip mid-first-squeeze is a silent no-op ──────────────
  test('QA-ACCEPT-NOOP: "Terima" shown while grip measuring with 0 attempts',
      () {
    final s = MeasurementSession(profile: const PersonProfile(name: 'G'));
    s.debugInjectGrip(8); // squeeze in progress → step measuring
    expect(s.stepOf(DeviceType.gripStrength), MeasureStep.measuring);
    // Belum ada remasan tercatat → tidak ada data → tombol "Terima" disembunyikan.
    expect(s.hasData(DeviceType.gripStrength), isFalse);
    s.dispose();
  });

  // ── Body-composition floats are stored without any range check ─────────
  test('QA-BODYCOMP-RANGE: absurd body-composition floats must not be stored',
      () {
    List<int> chunk(double f) {
      final bd = ByteData(4)..setFloat32(0, f, Endian.big);
      final b = bd.buffer.asUint8List();
      return [b[2], b[3], b[0], b[1]]; // Senssun word order
    }

    final s = MeasurementSession(profile: const PersonProfile(name: 'W', heightCm: 160));
    s.debugInjectPacket(scaleMain(62.0, locked: true), _wM);
    final pkt = <int>[0, 0, 42, 0];
    for (final f in [0.0, 2400.0, 0.0, -5000.0, 99999.0, 0.0, 0.0, 9e6, 1e7]) {
      pkt.addAll(chunk(f));
    }
    s.debugInjectPacket(pkt, _wM);
    final w = s.measurements.weightScale;
    expect(w.bodyFatPercent == null || (w.bodyFatPercent! >= 0 && w.bodyFatPercent! <= 75),
        isTrue,
        reason: 'stored fat=${w.bodyFatPercent}% muscle=${w.musclePercent}% '
            'water=${w.bodyWaterPercent}% bone=${w.boneMineralPercent}%');
    s.dispose();
  });
}
