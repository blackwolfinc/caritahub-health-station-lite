import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/ble/health_device_models.dart';
import 'package:health_station_lite/ble/measurement_session.dart';
import 'package:health_station_lite/data/device_registry_store.dart';
import 'package:health_station_lite/models/device_models.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Paket mentah seperti yang dikirim alat ──────────────────────────────────
List<int> ox(int spo2, int hr) => [0, 0, 0, hr, spo2]; // KS M6100P
List<int> temp(double c) {
  final raw = (c * 100).round();
  return [0, raw & 0xFF, (raw >> 8) & 0xFF]; // Yuwell HT-YHW
}
List<int> bp(int sys, int dia, int pulse) {
  final v = List<int>.filled(16, 0);
  v[0] = 0x04;
  v[1] = sys;
  v[3] = dia;
  v[14] = pulse;
  return v; // 0x2A35
}
List<int> scaleMain(double kg, {required bool locked}) {
  final raw = (kg * 100).round();
  final v = List<int>.filled(12, 0);
  v[0] = 0x33;
  v[1] = 0xCC;
  v[6] = locked ? 0x81 : 0x80;
  v[10] = (raw >> 8) & 0xFF;
  v[11] = raw & 0xFF;
  return v; // IF_B8B fff1
}
List<int> scaleFinal() => [78, 7, 0x04, 0xB0, 0x03, 0x03, 0, 0]; // skor 78

const _oxM = BleDeviceModel.KS_M6100P;
const _tM = BleDeviceModel.Yuwell_HT_YHW;
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

void squeeze(MeasurementSession s, double peak) {
  s.debugInjectGrip(5);
  s.debugInjectGrip(peak);
  s.debugInjectGrip(0.5); // lepas → 1 percobaan
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    MeasurementSession.debugResetCarryOver();
    await DeviceRegistryStore.instance.load();
    await registerAll();
  });

  test('1 lansia: semua alat mengirim bersamaan, tiap alat mengunci sendiri', () {
    final s = MeasurementSession(
        profile: const PersonProfile(name: 'Siti', heightCm: 158));
    // Belum ada alat tersambung → belum ada yang wajib dicek.
    expect(s.requiredDevices, isEmpty);

    // Paket dari lima alat saling bersilangan — tidak ada yang menunggu.
    s.debugInjectPacket(scaleMain(58.2, locked: false), _wM);
    s.debugInjectPacket(ox(97, 75), _oxM);
    s.debugInjectPacket(temp(36.6), _tM);
    s.debugInjectPacket(ox(97, 76), _oxM);
    s.debugInjectPacket(scaleMain(58.4, locked: true), _wM);
    s.debugInjectPacket(ox(98, 76), _oxM);
    squeeze(s, 18.4);
    s.debugInjectPacket(ox(97, 75), _oxM);
    s.debugInjectPacket(bp(128, 82, 74), _bpM);
    s.debugInjectPacket(ox(97, 75), _oxM);
    s.debugInjectPacket(scaleFinal(), _wM);

    expect(s.stepOf(DeviceType.thermometer), MeasureStep.done);
    expect(s.stepOf(DeviceType.tensimeter), MeasureStep.done);
    expect(s.stepOf(DeviceType.pulseOximeter), MeasureStep.done);
    expect(s.stepOf(DeviceType.weightScale), MeasureStep.done);
    expect(s.stepOf(DeviceType.gripStrength), MeasureStep.measuring);

    final m = s.measurements;
    expect(m.thermometer.temperature, closeTo(36.6, 1e-9));
    expect(m.tensimeter.systolic, 128);
    expect(m.pulseOximeter.spo2, 97);
    expect(m.weightScale.weight, 58.4);
    expect(m.weightScale.bmi, closeTo(58.4 / (1.58 * 1.58), 1e-6));
    expect(m.weightScale.bodyScore, 78);
    expect(s.allRequiredDone, isFalse); // genggam belum

    // Setelah terkunci, bacaan susulan tidak menimpa hasil.
    s.debugInjectPacket(ox(91, 110), _oxM);
    s.debugInjectPacket(temp(38.0), _tM);
    s.debugInjectPacket(bp(160, 100, 90), _bpM);
    expect(s.measurements.pulseOximeter.spo2, 97);
    expect(s.measurements.thermometer.temperature, closeTo(36.6, 1e-9));
    expect(s.measurements.tensimeter.systolic, 128);

    // Genggam: 3 kiri lalu otomatis pindah kanan, 6 remasan → selesai.
    for (final kg in [19.0, 18.7, 21.2, 22.0, 21.5]) {
      squeeze(s, kg);
    }
    expect(s.gripAttempts, 6);
    expect(s.measurements.gripStrength.gripLeft, 19.0);
    expect(s.measurements.gripStrength.gripRight, 22.0);
    expect(s.stepOf(DeviceType.gripStrength), MeasureStep.done);
    expect(s.allRequiredDone, isTrue);
    s.dispose();
  });

  test('oksimeter: nilai belum stabil tidak dikunci', () {
    final s = MeasurementSession(profile: const PersonProfile(name: 'A'));
    for (final v in [93, 96, 98, 95, 97]) {
      s.debugInjectPacket(ox(v, 80), _oxM);
    }
    expect(s.stepOf(DeviceType.pulseOximeter), MeasureStep.measuring);
    expect(s.oxStableProgress, lessThan(MeasurementSession.oxStableCount));
    // 0 / 127 = jari dilepas → bukan hasil.
    s.debugInjectPacket(ox(127, 255), _oxM);
    expect(s.measurements.pulseOximeter.spo2, 97);
    s.dispose();
  });

  test('gerbang: jari & kaki lansia sebelumnya tidak masuk ke lansia baru', () {
    final a = MeasurementSession(profile: const PersonProfile(name: 'A'));
    a.debugInjectPacket(ox(96, 70), _oxM);
    a.debugInjectPacket(scaleMain(61.0, locked: false), _wM);
    a.dispose();

    // Lansia B dimulai < 3 detik kemudian: alat masih dipakai A.
    final b = MeasurementSession(profile: const PersonProfile(name: 'B'));
    expect(b.oxArmed, isFalse);
    expect(b.scaleArmed, isFalse);
    b.debugInjectPacket(ox(96, 70), _oxM);
    b.debugInjectPacket(scaleMain(61.0, locked: true), _wM);
    expect(b.measurements.pulseOximeter.spo2, isNull);
    expect(b.measurements.weightScale.weight, isNull);

    // A melepas jari (frame tidak valid) dan turun (berat < 5 kg).
    b.debugInjectPacket(ox(0, 0), _oxM);
    b.debugInjectPacket(scaleMain(0.4, locked: false), _wM);
    expect(b.oxArmed, isTrue);
    expect(b.scaleArmed, isTrue);
    b.debugInjectPacket(ox(98, 88), _oxM);
    b.debugInjectPacket(scaleMain(47.5, locked: false), _wM);
    expect(b.measurements.pulseOximeter.spo2, 98);
    expect(b.measurements.weightScale.weight, 47.5);
    b.dispose();
  });

  test('lewati, ukur ulang, terima sekarang, isi manual', () {
    final s = MeasurementSession(profile: const PersonProfile(name: 'Hendrik'));
    // Kursi roda: timbangan dilewati, genggam cukup 1 per tangan.
    s.skip(DeviceType.weightScale);
    s.debugInjectPacket(temp(36.4), _tM);
    s.debugInjectPacket(bp(150, 95, 80), _bpM);
    for (var i = 0; i < 5; i++) {
      s.debugInjectPacket(ox(95, 72), _oxM);
    }
    squeeze(s, 12.0);
    s.setGripSide(GripSide.right);
    squeeze(s, 13.5);
    expect(s.stepOf(DeviceType.gripStrength), MeasureStep.measuring);
    s.acceptNow(DeviceType.gripStrength);
    expect(s.allRequiredDone, isTrue);

    // Tensi tinggi (cemas) → ukur ulang menghapus dan membuka kunci.
    s.remeasure(DeviceType.tensimeter);
    expect(s.allRequiredDone, isFalse);
    expect(s.measurements.tensimeter.systolic, isNull);
    s.debugInjectPacket(bp(136, 86, 76), _bpM);
    expect(s.measurements.tensimeter.systolic, 136);
    expect(s.allRequiredDone, isTrue);

    // Batal lewati → timbangan wajib lagi; isi manual menyelesaikannya.
    s.unskip(DeviceType.weightScale);
    expect(s.allRequiredDone, isFalse);
    s.updateWeightScale(s.measurements.weightScale.copyWith(weight: 55.0));
    expect(s.stepOf(DeviceType.weightScale), MeasureStep.done);
    expect(s.allRequiredDone, isTrue);
    s.dispose();
  });

  test('hanya alat tersambung/menyambung yang dicek', () async {
    final s = MeasurementSession(profile: const PersonProfile(name: 'Rina'));
    await s.start(); // status alat terdaftar baru berlaku setelah sesi mulai
    s.debugSetStatus(DeviceType.thermometer, DeviceStatus.connected);
    s.debugInjectPacket(temp(36.5), _tM);
    expect(s.requiredDevices, {DeviceType.thermometer});
    expect(s.hasIdleRegistered, isTrue);
    expect(s.allRequiredDone, isTrue);
    // Oksimeter baru dinyalakan (jari dipasang) → sedang menyambung → wajib.
    s.debugSetStatus(DeviceType.pulseOximeter, DeviceStatus.connecting);
    expect(s.requiredDevices, contains(DeviceType.pulseOximeter));
    expect(s.allRequiredDone, isFalse);
    // Putus sebentar setelah tersambung → tetap wajib.
    s.debugSetStatus(DeviceType.pulseOximeter, DeviceStatus.connected);
    s.debugSetStatus(DeviceType.pulseOximeter, DeviceStatus.waiting);
    expect(s.allRequiredDone, isFalse);
    s.dispose();
  });

  test('tanpa alat terdaftar tidak pernah simpan otomatis', () async {
    SharedPreferences.setMockInitialValues({});
    for (final t in DeviceType.values) {
      await DeviceRegistryStore.instance.unregister(t);
    }
    final s = MeasurementSession(profile: const PersonProfile(name: 'Manual'));
    s.updateThermometer(s.measurements.thermometer.copyWith(temperature: 36.5));
    expect(s.requiredDevices, isEmpty);
    expect(s.allRequiredDone, isFalse);
    expect(s.hasUnsavedData, isTrue);
    s.dispose();
  });
}
