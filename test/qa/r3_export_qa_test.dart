// QA round 3 — export / receipt consistency (scratch).
// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/data/csv_export.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';
import 'package:health_station_lite/printing/receipt_content.dart';
import 'package:health_station_lite/satusehat/satusehat_export.dart';
import 'package:intl/date_symbol_data_local.dart';

const cfg = SatusehatConfig(
    orgId: '10000004', locationId: 'ef011065-38c9-46f8-9c35-d1fe68966a3e', practitionerId: 'N10000001');

HealthRecord rec(AllMeasurements m, {double? profileHeight}) => HealthRecord(
      id: '261018-0931-T8R',
      createdAt: DateTime(2026, 10, 18, 9, 31),
      profile: PersonProfile(name: 'Siti', nik: '3201015203580001', heightCm: profileHeight),
      measurements: m,
    );

Map<String, dynamic>? obs(Map<String, dynamic> b, String loinc) {
  for (final e in b['entry'] as List) {
    final r = e['resource'];
    if (r['resourceType'] == 'Observation' &&
        (r['code']['coding'] as List).any((c) => c['code'] == loinc)) {
      return r;
    }
  }
  return null;
}

void main() {
  setUpAll(() async => initializeDateFormatting('id_ID'));

  test('BUG: CSV, receipt and SATUSEHAT round the same value differently', () {
    for (final w in [36.65, 58.15, 23.45, 19.95]) {
      final r = rec(AllMeasurements(
          thermometer: ThermometerData(temperature: w),
          weightScale: WeightScaleData(weight: w)));
      final csvRow = CsvExport.build([r]).trim().split('\n')[1].split(';');
      final csvTemp = csvRow[12];
      final receipt = buildReceipt(r).sections.first.lines.first.value; // "x,y °C"
      final fhir = obs(SatusehatExport.bundle(r, cfg), '8310-5')!['valueQuantity']['value'];
      print('raw=$w  csv=$csvTemp  receipt=$receipt  fhir=$fhir');
      expect(receipt.startsWith(csvTemp), isTrue);
      expect('$fhir'.replaceAll('.', ','), csvTemp, reason: 'raw $w: csv/receipt $csvTemp vs SATUSEHAT $fhir');
    }
  });

  test('BUG: physiologically impossible manual values are exported to SATUSEHAT', () {
    // Manual entry accepts any [0-9.,]: typo "365" for 36,5 °C, "0" systolic, "970" SpO2.
    final r = rec(const AllMeasurements(
      tensimeter: TensimeterData(systolic: 0, diastolic: 800, pulse: 0),
      pulseOximeter: PulseOximeterData(spo2: 970),
      thermometer: ThermometerData(temperature: 365),
      weightScale: WeightScaleData(weight: 0),
    ));
    // Pemeriksaan dengan nilai mustahil ditahan (tidak masuk ekspor) sampai diperbaiki.
    final p = SatusehatExport.problems(r, cfg);
    expect(p, contains('Suhu 365.0 tidak wajar'));
    expect(p, contains('SpO2 970 tidak wajar'));
    expect(p, contains('Diastolik 800 tidak wajar'));
    expect(SatusehatExport.batch([r], cfg).bundles, isEmpty);
  });

  // Lemak tubuh dari tinggi pengganti: dicegah saat SIMPAN (lihat
  // test/qa/r2_session_qa_test.dart QA-COMPOSITION-HEIGHT), bukan saat ekspor.

  test('OK: NDJSON is one bundle per line, unicode names survive', () {
    final r = HealthRecord(
      id: 'A', createdAt: DateTime(2026, 10, 18, 9),
      profile: const PersonProfile(name: 'Ñoño "Ä"\nX', nik: '3201015203580001'),
      measurements: const AllMeasurements(tensimeter: TensimeterData(systolic: 120, diastolic: 80)),
    );
    final nd = SatusehatExport.batch([r, r], cfg).ndjson;
    expect(nd.split('\n').length, 2);
    expect(jsonDecode(nd.split('\n')[0])['entry'][0]['resource']['subject']['display'], 'Ñoño "Ä"\nX');
    final csv = CsvExport.build([r]);
    expect(csv, contains('"Ñoño ""Ä""\nX"'));
  });
}
