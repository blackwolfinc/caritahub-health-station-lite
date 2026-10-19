import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/app/version.dart';
import 'package:health_station_lite/data/csv_export.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';
import 'package:health_station_lite/satusehat/satusehat_export.dart';
import 'package:health_station_lite/utils/nik.dart';

const cfg = SatusehatConfig(
  orgId: '10000004',
  locationId: 'ef011065-38c9-46f8-9c35-d1fe68966a3e',
  locationName: 'Posyandu Lansia Melati',
  practitionerId: 'N10000001',
  practitionerName: 'Ns. Dewi',
);

// NIK fiktif berpola benar: perempuan lahir 12-03-1958.
const nikP = '3201015203580001';
// Laki-laki lahir 07-11-1952.
const nikL = '3578010711520002';

HealthRecord rec({
  String? nik = nikP,
  double? height = 158,
  AllMeasurements? m,
  String id = '261018-0931-T8R',
}) {
  final at = DateTime(2026, 10, 18, 9, 31, 20);
  return HealthRecord(
    id: id,
    createdAt: at,
    startedAt: at.subtract(const Duration(seconds: 215)),
    profile: PersonProfile(
      name: 'Siti Aminah',
      gender: Gender.female,
      age: 68,
      heightCm: height,
      nik: nik,
      birthDate: nik == null ? null : Nik.decode(nik)?.birthDate,
    ),
    measurements: m ??
        const AllMeasurements(
          tensimeter: TensimeterData(systolic: 128, diastolic: 82, pulse: 74),
          pulseOximeter: PulseOximeterData(spo2: 97, heartRate: 75),
          thermometer: ThermometerData(temperature: 36.6),
          weightScale: WeightScaleData(weight: 58.4, bmi: 23.39, bodyFatPercent: 31.24),
          gripStrength: GripStrengthData(
              gripLeft1: 18.2, gripLeft2: 19.5, gripRight1: 21.0, gripRight2: 22.4),
        ),
  );
}

Map<String, dynamic> obs(Map<String, dynamic> bundle, String loinc) =>
    (bundle['entry'] as List)
        .map((e) => e['resource'] as Map<String, dynamic>)
        .firstWhere((r) =>
            r['resourceType'] == 'Observation' &&
            (r['code']['coding'] as List).any((c) => c['code'] == loinc));

void main() {
  group('NIK', () {
    test('validasi & dekode L/P + tanggal lahir', () {
      expect(Nik.validate(''), isNull);
      expect(Nik.validate('123'), contains('16 angka'));
      expect(Nik.validate('0901015203580001'), contains('provinsi'));
      expect(Nik.validate('3201019913580001'), contains('Tanggal'));
      expect(Nik.validate('3201015213580001'), contains('Bulan'));
      expect(Nik.validate('3201015203580000'), contains('urut'));
      final p = Nik.decode(nikP, now: DateTime(2026, 10, 18))!;
      expect(p.gender, Gender.female);
      expect(p.birthDate, DateTime(1958, 3, 12));
      expect(Nik.ageOn(p.birthDate, DateTime(2026, 10, 18)), 68);
      final l = Nik.decode(nikL, now: DateTime(2026, 10, 18))!;
      expect(l.gender, Gender.male);
      expect(l.birthDate, DateTime(1952, 11, 7));
      expect(Nik.decode('3201013102580001'), isNull); // 31 Februari
      expect(Nik.mask(nikP), '3201********0001');
      expect(Nik.normalize('3201 0152-0358 0001'), nikP);
    });

    test('NIK & tanggal lahir tersimpan dan terbaca kembali', () {
      final r = rec();
      final back = HealthRecord.fromJson(jsonDecode(jsonEncode(r.toJson())))!;
      expect(back.profile.nik, nikP);
      expect(back.profile.birthDate, DateTime(1958, 3, 12));
      // Data lama tanpa NIK tetap terbaca.
      final old = HealthRecord.fromJson({
        'id': 'x',
        'createdAt': '2026-10-01T08:00:00.000',
        'profile': {'name': 'Lama'},
      })!;
      expect(old.profile.nik, isNull);
    });
  });

  group('SATUSEHAT Bundle', () {
    test('kelengkapan: konfigurasi, NIK, hasil', () {
      expect(SatusehatExport.problems(rec(), cfg), isEmpty);
      expect(SatusehatExport.problems(rec(nik: null), cfg), ['NIK kosong']);
      expect(SatusehatExport.problems(rec(nik: '123'), cfg), ['NIK tidak valid']);
      expect(
          SatusehatExport.problems(rec(m: const AllMeasurements()), cfg),
          ['Tidak ada hasil ukur']);
      const empty = SatusehatConfig(orgId: '', locationId: '', practitionerId: '');
      expect(SatusehatExport.problems(rec(), empty).length, 3);
    });

    test('struktur transaction: Encounter + Condition + Observation', () {
      final b = SatusehatExport.bundle(rec(), cfg);
      expect(b['resourceType'], 'Bundle');
      expect(b['type'], 'transaction');
      final entries = (b['entry'] as List).cast<Map<String, dynamic>>();
      final types = entries.map((e) => e['resource']['resourceType']).toList();
      expect(types.first, 'Encounter');
      expect(types[1], 'Condition');
      expect(types.where((t) => t == 'Observation').length, 11);

      // fullUrl unik & berbentuk urn:uuid v4
      final urls = entries.map((e) => e['fullUrl'] as String).toList();
      expect(urls.toSet().length, urls.length);
      for (final u in urls) {
        expect(u, matches(RegExp(
            r'^urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      }
      for (final e in entries) {
        expect(e['request'], {'method': 'POST', 'url': e['resource']['resourceType']});
      }

      final enc = entries.first['resource'] as Map<String, dynamic>;
      expect(enc['status'], 'finished');
      expect(enc['class']['code'], 'AMB');
      expect(enc['identifier'][0]['system'], 'http://sys-ids.kemkes.go.id/encounter/10000004');
      expect(enc['serviceProvider']['reference'], 'Organization/10000004');
      expect(enc['location'][0]['location']['reference'],
          'Location/ef011065-38c9-46f8-9c35-d1fe68966a3e');
      expect(enc['participant'][0]['individual']['reference'], 'Practitioner/N10000001');
      expect((enc['statusHistory'] as List).map((h) => h['status']),
          ['arrived', 'in-progress', 'finished']);
      // Waktu UTC berformat SATUSEHAT (WIB 09:27:45 → 02:27:45+00:00).
      final start = DateTime(2026, 10, 18, 9, 27, 45);
      expect(enc['period']['start'], SatusehatExport.time(start));
      expect(enc['period']['start'], matches(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\+00:00$')));
      expect(enc['subject']['identifier'], {'system': Nik.system, 'value': nikP});

      // Semua referensi encounter menunjuk ke fullUrl Encounter di bundle.
      for (final e in entries.skip(1)) {
        expect(e['resource']['encounter']['reference'], entries.first['fullUrl']);
      }
      expect(enc['diagnosis'][0]['condition']['reference'], entries[1]['fullUrl']);
    });

    test('kode LOINC & satuan UCUM sesuai dokumentasi SATUSEHAT', () {
      final b = SatusehatExport.bundle(rec(), cfg);
      void check(String loinc, String cat, num value, String unit, String code) {
        final o = obs(b, loinc);
        expect(o['status'], 'final');
        expect(o['category'][0]['coding'][0]['code'], cat, reason: loinc);
        expect(o['valueQuantity'],
            {'value': value, 'unit': unit, 'system': 'http://unitsofmeasure.org', 'code': code},
            reason: loinc);
        expect(o['performer'][0]['reference'], 'Practitioner/N10000001');
        expect(o['effectiveDateTime'], isNotNull);
        expect(o['issued'], isNotNull);
      }

      check('8480-6', 'vital-signs', 128, 'mm[Hg]', 'mm[Hg]');
      check('8462-4', 'vital-signs', 82, 'mm[Hg]', 'mm[Hg]');
      // Satu nilai nadi seperti analisa & catatan cetak: oksimeter dulu.
      check('8867-4', 'vital-signs', 75, 'beats/min', '/min');
      check('59408-5', 'vital-signs', 97, '%', '%');
      check('8310-5', 'vital-signs', 36.6, 'C', 'Cel');
      check('29463-7', 'vital-signs', 58.4, 'kg', 'kg');
      check('8302-2', 'vital-signs', 158, 'cm', 'cm');
      check('39156-5', 'exam', 23.4, 'kg/m2', 'kg/m2');
      check('41982-0', 'exam', 31.2, '%', '%');
      check('83173-5', 'exam', 19.5, 'kgf', 'kgf');
      check('83174-3', 'exam', 22.4, 'kgf', 'kgf');
      // SpO2 juga membawa kode dasar FHIR vital signs.
      expect((obs(b, '59408-5')['code']['coding'] as List).map((c) => c['code']),
          containsAll(['59408-5', '2708-6']));
    });

    test('tanpa tinggi: BMI & lemak tidak dikirim (dihitung dari 160 cm pengganti)', () {
      final b = SatusehatExport.bundle(rec(height: null), cfg);
      final codes = (b['entry'] as List)
          .map((e) => e['resource'])
          .where((r) => r['resourceType'] == 'Observation')
          .map((r) => r['code']['coding'][0]['code'])
          .toList();
      expect(codes, isNot(contains('39156-5')));
      expect(codes, isNot(contains('41982-0')));
      expect(codes, isNot(contains('8302-2')));
      expect(codes, contains('29463-7'));
    });

    test('nadi dari oksimeter bila tensimeter kosong; nilai NaN diabaikan', () {
      final b = SatusehatExport.bundle(
          rec(
              m: const AllMeasurements(
            pulseOximeter: PulseOximeterData(spo2: 96, heartRate: 81),
            thermometer: ThermometerData(temperature: double.nan),
          )),
          cfg);
      expect(obs(b, '8867-4')['valueQuantity']['value'], 81);
      expect(jsonEncode(b), isNot(contains('NaN')));
      expect(
          (b['entry'] as List).where((e) => e['resource']['resourceType'] == 'Observation').length,
          3); // SpO2, nadi, tinggi (profil)
    });

    test('ekspor ulang menghasilkan UUID yang sama; batch melewati yang belum siap', () {
      final a = jsonEncode(SatusehatExport.bundle(rec(), cfg));
      final b = jsonEncode(SatusehatExport.bundle(rec(), cfg));
      expect(a, b);
      final batch = SatusehatExport.batch([
        rec(id: 'A'),
        rec(id: 'B', nik: null),
        rec(id: 'C'),
      ], cfg);
      expect(batch.bundles.length, 2);
      expect(batch.skipped.keys, ['B']);
      final lines = batch.ndjson.split('\n');
      expect(lines.length, 2);
      for (final l in lines) {
        expect(jsonDecode(l)['resourceType'], 'Bundle');
      }
      // Contoh untuk validasi FHIR di luar Flutter (QA putaran 5).
      final dir = Directory('build/satusehat_samples')..createSync(recursive: true);
      File('${dir.path}/sample.ndjson').writeAsStringSync('${batch.ndjson}\n');
      File('${dir.path}/sample_bundle.json')
          .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(
              SatusehatExport.bundle(rec(), cfg)));
    });
  });

  test('CSV: NIK disamarkan (UU PDP), tidak jadi notasi ilmiah', () {
    final csv = CsvExport.build([rec()]);
    expect(csv.split('\n').first, contains(';NIK;'));
    expect(csv, contains('3201********0001'));
    expect(csv, isNot(contains('3201015203580001')));
  });

  test('versi aplikasi sama dengan pubspec', () {
    final pub = File('pubspec.yaml').readAsStringSync();
    final v = RegExp(r'^version:\s*([0-9.]+)\+', multiLine: true).firstMatch(pub)!.group(1);
    expect(appVersion, v);
  });
}
