// QA persona 4 — logika sesi pengukuran (unit). Test gagal = bug.
// Disalin dari qa_tests/p4_session_test.dart + kasus tambahan (B-xx).
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/ble/health_device_models.dart';
import 'package:health_station_lite/ble/measurement_session.dart';
import 'package:health_station_lite/data/device_registry_store.dart';
import 'package:health_station_lite/models/device_models.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<int> ox(int spo2, int hr) => [0, 0, 0, hr, spo2]; // KS M6100P
List<int> temp(double c) {
  final raw = (c * 100).round();
  return [0, raw & 0xFF, (raw >> 8) & 0xFF];
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
const _tM = BleDeviceModel.Yuwell_HT_YHW;
const _wM = BleDeviceModel.IF_B8B;

const _reg =
    '[{"type":"pulseOximeter","remoteId":"B","name":"KS M6100P"},'
    '{"type":"thermometer","remoteId":"C","name":"Yuwell HT-YHW"},'
    '{"type":"weightScale","remoteId":"D","name":"IF_B8B"}]';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({'device_registry_v1': _reg});
    MeasurementSession.debugResetCarryOver();
    DeviceRegistryStore.instance.debugReset();
    await DeviceRegistryStore.instance.load();
  });

  Future<MeasurementSession> started() async {
    final s = MeasurementSession(
      profile: const PersonProfile(
        name: 'QA',
        heightCm: 158,
        gender: Gender.female,
      ),
    );
    await s.start();
    return s;
  }

  test(
    'P4-01 belum ada alat tersambung: required kosong, idle=true, allDone=false',
    () async {
      final s = await started();
      expect(s.requiredDevices, isEmpty);
      expect(s.hasIdleRegistered, isTrue);
      expect(s.allRequiredDone, isFalse);
      expect(s.isActive(DeviceType.tensimeter), isFalse); // tidak terdaftar
      s.dispose();
    },
  );

  test(
    'P4-02 alat tidak terdaftar diisi manual → tidak wajib & tidak memicu simpan otomatis',
    () async {
      final s = await started();
      s.updateTensimeterManual();
      expect(s.isActive(DeviceType.tensimeter), isFalse);
      expect(s.doneCount, 1);
      expect(s.allRequiredDone, isFalse);
      s.dispose();
    },
  );

  test(
    'P4-03 termometer selesai lalu mati sendiri → tetap wajib & tetap selesai',
    () async {
      final s = await started();
      s.debugSetStatus(DeviceType.thermometer, DeviceStatus.connected);
      s.debugInjectPacket(temp(36.6), _tM);
      s.debugSetStatus(DeviceType.thermometer, DeviceStatus.waiting);
      expect(s.requiredDevices, {DeviceType.thermometer});
      expect(s.allRequiredDone, isTrue);
      s.dispose();
    },
  );

  test(
    'P4-04 semua alat wajib dilewati → allDone=false (minimal satu selesai)',
    () async {
      final s = await started();
      s.debugSetStatus(DeviceType.thermometer, DeviceStatus.connected);
      s.skip(DeviceType.thermometer);
      expect(s.requiredDevices, {DeviceType.thermometer});
      expect(s.allRequiredDone, isFalse);
      expect(s.hasUnsavedData, isFalse);
      s.dispose();
    },
  );

  test(
    'P4-05 oksimeter sempat "menghubungkan" (tersambung fisik, setup GATT gagal) '
    'lalu kembali "menunggu" → tetap wajib, supaya tidak tersimpan duluan',
    () async {
      final s = await started();
      s.debugSetStatus(DeviceType.thermometer, DeviceStatus.connected);
      s.debugInjectPacket(temp(36.6), _tM);
      expect(s.allRequiredDone, isTrue);
      s.debugSetStatus(DeviceType.pulseOximeter, DeviceStatus.connecting);
      expect(s.allRequiredDone, isFalse);
      // _abandonLink: GATT 133 saat discoverServices → menunggu lagi.
      s.debugSetStatus(DeviceType.pulseOximeter, DeviceStatus.waiting);
      expect(
        s.requiredDevices,
        contains(DeviceType.pulseOximeter),
        reason:
            'oksimeter yang baru saja tersambung fisik dilepas dari daftar wajib → '
            'hitung mundur simpan otomatis mulai lagi tanpa oksimeter',
      );
      s.dispose();
    },
  );

  test(
    'P4-06 measurementsForSave membuang nilai belum stabil (SpO2 sebagian, berat belum terkunci)',
    () async {
      final s = await started();
      s.debugInjectPacket(ox(97, 0), _oxM); // SpO2 tanpa nadi
      s.debugInjectPacket(scaleMain(60, locked: false), _wM);
      expect(s.hasUnsavedData, isTrue);
      final m = s.measurementsForSave();
      expect(m.pulseOximeter.isEmpty, isTrue);
      expect(m.weightScale.isEmpty, isTrue);
      // hasUnsavedData (konfirmasi keluar) tetap true, tapi tidak ada yang
      // bisa disimpan → "Selesai" menolak.
      expect(m.hasAnyData, isFalse);
      expect(s.hasSavableData, isFalse);
      s.dispose();
    },
  );

  test(
    'P4-07 alat dicabut dari daftar di tengah sesi → hasil yang sudah selesai tetap disimpan',
    () async {
      final s = await started();
      s.debugSetStatus(DeviceType.thermometer, DeviceStatus.connected);
      s.debugInjectPacket(temp(36.6), _tM);
      await DeviceRegistryStore.instance.unregister(DeviceType.thermometer);
      await Future<void>.delayed(Duration.zero);
      expect(
        s.measurementsForSave().thermometer.temperature,
        closeTo(36.6, 1e-9),
      );
      s.dispose();
    },
  );

  test(
    'P4-08 ukur ulang oksimeter → tetap wajib, allDone=false sampai stabil lagi',
    () async {
      final s = await started();
      s.debugSetStatus(DeviceType.pulseOximeter, DeviceStatus.connected);
      for (var i = 0; i < 5; i++) {
        s.debugInjectPacket(ox(97, 72), _oxM);
      }
      expect(s.allRequiredDone, isTrue);
      s.debugSetStatus(DeviceType.pulseOximeter, DeviceStatus.waiting);
      s.remeasure(DeviceType.pulseOximeter);
      expect(s.requiredDevices, contains(DeviceType.pulseOximeter));
      expect(s.allRequiredDone, isFalse);
      s.dispose();
    },
  );

  test('P4-09 paket setelah dispose diabaikan (tidak melempar)', () async {
    final s = await started();
    s.dispose();
    expect(() => s.debugInjectPacket(ox(97, 72), _oxM), returnsNormally);
    expect(() => s.debugInjectPacket(temp(36.6), _tM), returnsNormally);
  });

  test(
    'P4-10 gerbang oksimeter: jari lansia sebelumnya masih terpasang, sesi baru '
    'dibuat 3,5 dtk kemudian → nilai lama tidak boleh langsung tercatat',
    () async {
      final a = MeasurementSession(profile: const PersonProfile(name: 'A'));
      for (var i = 0; i < 5; i++) {
        a.debugInjectPacket(ox(96, 70), _oxM);
      }
      a.dispose(); // simpan → dialog → kartu berikut: > 3 dtk
      await Future<void>.delayed(const Duration(milliseconds: 3500));
      final b = MeasurementSession(profile: const PersonProfile(name: 'B'));
      b.debugInjectPacket(ox(96, 70), _oxM);
      expect(
        b.measurements.pulseOximeter.spo2,
        isNull,
        reason:
            'SpO2 A langsung tercatat untuk B (jendela carry-over hanya 3 dtk '
            'dan tidak diperbarui selama tidak ada sesi)',
      );
      b.dispose();
    },
  );

  test(
    'B-01 alat sempat "menghubungkan" lalu dilewati → tidak wajib lagi, simpan otomatis boleh',
    () async {
      final s = await started();
      s.debugSetStatus(DeviceType.thermometer, DeviceStatus.connected);
      s.debugInjectPacket(temp(36.6), _tM);
      s.debugSetStatus(DeviceType.pulseOximeter, DeviceStatus.connecting);
      s.debugSetStatus(DeviceType.pulseOximeter, DeviceStatus.waiting);
      expect(s.allRequiredDone, isFalse);
      s.skip(DeviceType.pulseOximeter);
      expect(s.allRequiredDone, isTrue);
      s.dispose();
    },
  );

  test('B-02 isian manual saja (Lainnya) → bisa disimpan', () async {
    final s = await started();
    expect(s.hasSavableData, isFalse);
    s.updateOthers(s.measurements.others.copyWith(height: 160.0));
    expect(s.hasSavableData, isTrue);
    s.dispose();
  });

  test(
    'B-03 gerbang oksimeter: jeda panjang tetap ditahan sampai jari dilepas',
    () async {
      final a = MeasurementSession(profile: const PersonProfile(name: 'A'));
      a.debugInjectPacket(ox(96, 70), _oxM);
      a.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 3500));
      final b = MeasurementSession(profile: const PersonProfile(name: 'B'));
      expect(b.oxArmed, isFalse);
      b.debugInjectPacket(ox(96, 70), _oxM);
      expect(b.measurements.pulseOximeter.spo2, isNull);
      b.debugInjectPacket(ox(0, 0), _oxM); // jari A dilepas
      expect(b.oxArmed, isTrue);
      b.debugInjectPacket(ox(98, 80), _oxM);
      expect(b.measurements.pulseOximeter.spo2, 98);
      b.dispose();
      // Sesi A berakhir dengan jari dilepas → sesi berikut langsung siap.
      final c = MeasurementSession(profile: const PersonProfile(name: 'C'));
      c.debugInjectPacket(ox(0, 0), _oxM);
      c.dispose();
      final d = MeasurementSession(profile: const PersonProfile(name: 'D'));
      expect(d.oxArmed, isTrue);
      d.dispose();
    },
  );

  test(
    'B-04 gerbang oksimeter: diam ≥2 dtk setelah tersambung di sesi baru → siap',
    () async {
      final a = MeasurementSession(profile: const PersonProfile(name: 'A'));
      a.debugInjectPacket(ox(96, 70), _oxM);
      a.dispose();
      final b = MeasurementSession(profile: const PersonProfile(name: 'B'));
      b.debugMarkAttached(
        DeviceType.pulseOximeter,
        DateTime.now().subtract(const Duration(seconds: 3)),
      );
      b.debugTickGates();
      expect(b.oxArmed, isTrue);
      b.dispose();
      final c = MeasurementSession(profile: const PersonProfile(name: 'C'));
      expect(c.oxArmed, isTrue, reason: 'diam = jari sudah dilepas');
      c.dispose();
    },
  );
}

extension on MeasurementSession {
  void updateTensimeterManual() => updateTensimeter(
    measurements.tensimeter.copyWith(systolic: 120, diastolic: 80),
  );
}
