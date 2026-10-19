import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/ble/health_device_models.dart';
import 'package:health_station_lite/ble/measurement_session.dart';
import 'package:health_station_lite/data/app_settings.dart';
import 'package:health_station_lite/models/device_models.dart';
import 'package:health_station_lite/printing/printer_service.dart';

void main() {
  group('BleDeviceModel.fromDeviceName', () {
    test('cocok persis dan dengan akhiran ID unik', () {
      expect(BleDeviceModel.fromDeviceName('Yuwell BO-YX110'),
          BleDeviceModel.Yuwell_BO_YX110);
      expect(BleDeviceModel.fromDeviceName('Yuwell BO-YX110-1da3'),
          BleDeviceModel.Yuwell_BO_YX110);
      expect(BleDeviceModel.fromDeviceName('KS M6100P'), BleDeviceModel.KS_M6100P);
      expect(BleDeviceModel.fromDeviceName('IF_B8B'), BleDeviceModel.IF_B8B);
      expect(BleDeviceModel.fromDeviceName('Random Speaker'), isNull);
    });

    test('jenis alat sesuai caritacore', () {
      expect(BleDeviceModel.KS_M6100P.kind, BleDeviceKind.oxymeter);
      expect(BleDeviceModel.Yuwell_HT_YHW.kind, BleDeviceKind.temperature);
      expect(BleDeviceModel.Yuwell_BP_YE670D.kind, BleDeviceKind.bloodPressure);
      expect(BleDeviceModel.IF_B8B.kind, BleDeviceKind.weightScale);
      expect(BleDeviceModel.FHR_666_BLE.kind, BleDeviceKind.doppler);
      expect(BleDeviceModel.Yuwell_CM100.kind, BleDeviceKind.oxymeter);
      expect(BleDeviceModel.KS_M6100P.isRead, isTrue);
      expect(BleDeviceModel.Yuwell_BO_YX110.isSubscribe, isTrue);
    });
  });

  group('HealthParserUtils', () {
    test('oksimeter KS M6100P: byte 3 = nadi, byte 4 = SpO2', () {
      final r = HealthParserUtils.parseOxymeter(
          [0x00, 0x00, 0x00, 72, 98], BleDeviceModel.KS_M6100P);
      expect(r.heartRate, 72);
      expect(r.oxygen, 98);
    });

    test('oksimeter Yuwell BO-YX110: byte 4 = nadi, byte 5 = SpO2', () {
      final r = HealthParserUtils.parseOxymeter(
          [0, 0, 0, 0, 80, 97], BleDeviceModel.Yuwell_BO_YX110);
      expect(r.heartRate, 80);
      expect(r.oxygen, 97);
    });

    // Paket asli dari BO-YX110 di iMin Falcon2 (19 Okt 2026).
    test('oksimeter Yuwell BO-YX110: frame FE, nilai dari frame 0x55', () {
      const m = BleDeviceModel.Yuwell_BO_YX110;
      final one = HealthParserUtils.parseOxymeter(
          [254, 10, 85, 0, 76, 98, 23, 112, 11, 81], m);
      expect(one.heartRate, 76);
      expect(one.oxygen, 98);
      // Dua frame dalam satu notifikasi: 0x57 (tanpa nilai) lalu 0x55.
      final two = HealthParserUtils.parseOxymeter([
        254, 10, 87, 10, 0, 0, 0, 0, 0, 95, //
        254, 10, 85, 0, 77, 97, 23, 112, 2, 230,
      ], m);
      expect(two.heartRate, 77);
      expect(two.oxygen, 97);
      // Hanya frame 0x57 → tidak ada nilai (bukan "jari dilepas").
      final none = HealthParserUtils.parseOxymeter(
          [254, 10, 87, 10, 0, 0, 0, 0, 0, 95], m);
      expect(none.heartRate, isNull);
      expect(none.oxygen, isNull);
    });

    test('termometer Yuwell HT-YHW (little endian /100) dan batas wajar', () {
      // 3660 = 0x0E4C → 36,60 °C
      expect(HealthParserUtils.parseTemperature(
          [0x00, 0x4C, 0x0E], BleDeviceModel.Yuwell_HT_YHW), closeTo(36.6, 1e-9));
      // 2000 → 20 °C, di luar 34–42 → ditolak
      expect(HealthParserUtils.parseTemperature(
          [0x00, 0xD0, 0x07], BleDeviceModel.Yuwell_HT_YHW), isNull);
    });

    test('termometer "Bluetooth BP" (ASCII)', () {
      final v = [0, 0, 0, 0, 0, 0x33, 0x36, 0x2E, 0x35]; // "36.5"
      expect(HealthParserUtils.parseTemperature(v, BleDeviceModel.Bluetooth_BP),
          closeTo(36.5, 1e-9));
    });

    test('tensimeter 0x2A35 dengan nadi', () {
      final v = List<int>.filled(16, 0);
      v[0] = 0x04; // flag nadi ada
      v[1] = 128; // sistolik
      v[3] = 82; // diastolik
      v[14] = 76; // nadi
      final bp = HealthParserUtils.parseBloodPressure(v)!;
      expect(bp.systolic, 128);
      expect(bp.diastolic, 82);
      expect(bp.pulse, 76);
      expect(HealthParserUtils.parseBloodPressure([1, 2, 3]), isNull);
    });
  });

  group('nameMatchesDeviceType', () {
    test('mencocokkan nama iklan ke jenis alat', () {
      expect(MeasurementSession.nameMatchesDeviceType(
          DeviceType.pulseOximeter, 'KS M6100P'), isTrue);
      expect(MeasurementSession.nameMatchesDeviceType(
          DeviceType.tensimeter, 'KS M6100P'), isFalse);
      expect(MeasurementSession.nameMatchesDeviceType(
          DeviceType.tensimeter, 'Yuwell BP-YE670D'), isTrue);
      expect(MeasurementSession.nameMatchesDeviceType(
          DeviceType.weightScale, 'IF_B8B'), isTrue);
      expect(MeasurementSession.nameMatchesDeviceType(
          DeviceType.gripStrength, 'weixin-nini'), isTrue);
      expect(MeasurementSession.nameMatchesDeviceType(
          DeviceType.gripStrength, 'Squegg 01'), isTrue);
      expect(MeasurementSession.nameMatchesDeviceType(
          DeviceType.thermometer, 'FHR-666(BLE)'), isFalse);
    });
  });

  // Jawaban asli iMin Falcon2 (I24T02): paperType=80, daftar [80, 58].
  test('lebar kertas dari printer iMin', () {
    expect(paperFromIminType(80), PaperWidth.mm80);
    expect(paperFromIminType('58'), PaperWidth.mm58);
    expect(paperFromIminType(null), isNull);
    expect(paperFromIminType(1), isNull);
  });
}
