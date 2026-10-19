import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/data/csv_export.dart';
import 'package:health_station_lite/data/record_store.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';
import 'package:health_station_lite/printing/receipt_content.dart';
import 'package:intl/date_symbol_data_local.dart';

HealthRecord sample({String name = 'Siti Aminah', DateTime? at}) => HealthRecord(
      id: 'TEST-1',
      createdAt: at ?? DateTime(2026, 10, 18, 9, 30),
      profile: PersonProfile(name: name, gender: Gender.female, age: 68),
      measurements: const AllMeasurements(
        tensimeter: TensimeterData(systolic: 145, diastolic: 88, pulse: 76),
        pulseOximeter: PulseOximeterData(spo2: 97, heartRate: 75),
        thermometer: ThermometerData(temperature: 36.6),
        weightScale: WeightScaleData(weight: 58.4, bmi: 23.4, bmr: 1250),
        gripStrength: GripStrengthData(gripLeft1: 18.2, gripLeft2: 19.5, gripRight1: 21.0),
        others: OthersMeasurementData(height: 158),
      ),
    );

void main() {
  setUpAll(() async => initializeDateFormatting('id_ID'));

  test('copyWith bisa mengosongkan nilai (null) dan tetap mempertahankan lainnya', () {
    const g = GripStrengthData(gripLeft1: 10, gripLeft2: 12);
    final cleared = g.copyWith(gripLeft2: null);
    expect(cleared.gripLeft1, 10);
    expect(cleared.gripLeft2, isNull);
    expect(g.gripLeft, 12);
    expect(cleared.gripLeft, 10);
  });

  test('HealthRecord JSON bolak-balik tanpa kehilangan data', () {
    final r = sample();
    final back = HealthRecord.fromJson(
        jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>)!;
    expect(back.profile.name, r.profile.name);
    expect(back.profile.gender, Gender.female);
    expect(back.measurements.tensimeter.systolic, 145);
    expect(back.measurements.weightScale.bmr, 1250);
    expect(back.measurements.gripStrength.gripLeft, 19.5);
    expect(back.measurements.others.height, 158);
  });

  test('missingLabels menyebut alat yang belum ada hasil', () {
    const m = AllMeasurements(thermometer: ThermometerData(temperature: 36.5));
    expect(m.hasAnyData, isTrue);
    expect(m.missingLabels, containsAll(['Tensimeter', 'Oksimeter', 'Timbangan']));
    expect(m.missingLabels, isNot(contains('Termometer')));
    expect(const AllMeasurements().hasAnyData, isFalse);
  });

  test('isi struk: hanya bagian terisi, tanda * untuk di luar rentang', () {
    final c = buildReceipt(sample(), locationName: 'Posyandu Melati');
    expect(c.locationName, 'Posyandu Melati');
    final titles = c.sections.map((s) => s.title).toList();
    expect(titles, [
      'Tekanan Darah',
      'Saturasi Oksigen',
      'Suhu Tubuh',
      'Berat & Komposisi Tubuh',
      'Kekuatan Genggam',
      'Lainnya',
      'Analisa Hasil (Kemenkes RI)',
    ]);
    final bp = c.sections.first.lines.first;
    expect(bp.value, '145/88 mmHg');
    expect(bp.flagged, isTrue); // sistolik > 139
    expect(c.hasFlagged, isTrue);
    final temp = c.sections[2].lines.first;
    expect(temp.value, '36,6 °C');
    expect(temp.flagged, isFalse);
    expect(c.printNumber, 1);
  });

  test('RecordStore menyimpan ke file dan memuat ulang', () async {
    final dir = await Directory.systemTemp.createTemp('hs_store');
    RecordStore.directoryProvider = () async => dir;
    final store = RecordStore.instance;
    await store.load();
    await store.add(sample(name: 'A', at: DateTime(2026, 10, 18, 8)));
    final b = sample(name: 'B', at: DateTime(2026, 10, 18, 9));
    await store.add(HealthRecord(
        id: 'TEST-2',
        createdAt: b.createdAt,
        profile: b.profile,
        measurements: b.measurements));
    final file = File('${dir.path}/health_records_v1.json');
    expect(await file.exists(), isTrue);
    final saved = jsonDecode(await file.readAsString()) as List;
    expect(saved.length, 2);
    await store.update(store.byId('TEST-2')!.copyWith(printCount: 1));
    expect(store.byId('TEST-2')!.printCount, 1);
    await store.delete('TEST-1');
    expect(store.records.map((r) => r.id), ['TEST-2']);
  });

  test('CSV memakai titik koma dan desimal koma', () {
    final csv = CsvExport.build([sample()]);
    final lines = csv.trim().split('\n');
    expect(lines.length, 2);
    expect(lines.first.startsWith('No;Tanggal;Jam;Nama'), isTrue);
    expect(lines[1], contains(';Siti Aminah;;Perempuan;68;145;88;76;97;75;36,6;58,4;23,4;'));
  });
}
