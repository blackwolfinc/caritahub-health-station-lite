import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/ble/measurement_session.dart';
import 'package:health_station_lite/data/record_store.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('BMI hanya dari tinggi asli (bukan 160 cm pengganti), tinggi 0 diabaikan', () {
    final s = MeasurementSession(profile: const PersonProfile(name: 'A'));
    s.updateWeightScale(const WeightScaleData(weight: 64));
    // Tanpa tinggi: BMI tidak ditampilkan/dicetak (bisa menyesatkan).
    expect(s.measurements.weightScale.bmi, isNull);
    expect(s.heightMissing, isTrue);

    s.updateOthers(const OthersMeasurementData(height: 0)); // salah ketik
    expect(s.measurements.weightScale.bmi, isNull);
    // tetap bisa disimpan sebagai JSON
    expect(() => jsonEncode(s.measurements.toJson()), returnsNormally);

    s.updateOthers(const OthersMeasurementData(height: 170));
    expect(s.measurements.weightScale.bmi, closeTo(64 / (1.7 * 1.7), 1e-9));
    expect(s.heightMissing, isFalse);
    s.dispose();
  });

  test('tinggi dari profil saja tidak dianggap data belum tersimpan', () {
    final s = MeasurementSession(
        profile: const PersonProfile(name: 'B', heightCm: 155));
    expect(s.measurements.others.height, 155);
    expect(s.hasUnsavedData, isFalse);
    s.updateThermometer(const ThermometerData(temperature: 36.5));
    expect(s.hasUnsavedData, isTrue);
    s.dispose();
  });

  test('RecordStore mengembalikan daftar bila penyimpanan gagal', () async {
    final dir = await Directory.systemTemp.createTemp('hs_fail');
    RecordStore.directoryProvider = () async => dir;
    final store = RecordStore.instance;
    await store.load();
    final before = store.records.length;
    // Buat path file menjadi folder supaya rename gagal.
    await Directory('${dir.path}/health_records_v1.json').create();
    final r = HealthRecord(
      id: 'X',
      createdAt: DateTime(2026, 10, 18),
      profile: const PersonProfile(name: 'C'),
      measurements: const AllMeasurements(
          thermometer: ThermometerData(temperature: 36.4)),
    );
    await expectLater(store.add(r), throwsA(anything));
    expect(store.records.length, before);
    expect(store.byId('X'), isNull);
  });
}
