// QA putaran 5 — contoh Bundle beragam untuk divalidasi validator resmi HL7
// (java -jar validator_cli.jar) dan fhir.resources di luar Flutter.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';
import 'package:health_station_lite/satusehat/satusehat_export.dart';

const cfg = SatusehatConfig(
  orgId: '10000004',
  locationId: 'ef011065-38c9-46f8-9c35-d1fe68966a3e',
  locationName: 'Posyandu Lansia Melati',
  practitionerId: 'N10000001',
  practitionerName: 'Ns. Dewi',
);

HealthRecord r(String id, PersonProfile p, AllMeasurements m) {
  final at = DateTime(2026, 10, 18, 9, 31, 20);
  return HealthRecord(
    id: id,
    createdAt: at,
    startedAt: at.subtract(const Duration(seconds: 215)),
    profile: p,
    measurements: m,
  );
}

void main() {
  test('tulis contoh Bundle untuk validasi', () {
    final samples = {
      'lengkap_p': r(
        'S-FULL',
        const PersonProfile(
            name: 'Siti Aminah', gender: Gender.female, age: 68, heightCm: 158, nik: '3201015203580001'),
        const AllMeasurements(
          tensimeter: TensimeterData(systolic: 128, diastolic: 82, pulse: 74),
          pulseOximeter: PulseOximeterData(spo2: 97, heartRate: 75),
          thermometer: ThermometerData(temperature: 36.6),
          weightScale: WeightScaleData(weight: 58.4, bmi: 23.39, bodyFatPercent: 31.2),
          gripStrength: GripStrengthData(gripLeft1: 19.5, gripRight1: 22.4),
        ),
      ),
      'tensi_saja_l': r(
        'S-BP',
        const PersonProfile(name: 'Bambang Hartono', gender: Gender.male, nik: '3578010711520002'),
        const AllMeasurements(tensimeter: TensimeterData(systolic: 152, diastolic: 94, pulse: 81)),
      ),
      'tanpa_tinggi': r(
        'S-NOH',
        const PersonProfile(name: 'Wahyuni', nik: '3201015203580001'),
        const AllMeasurements(
          weightScale: WeightScaleData(weight: 52.1, bmi: 20.4, bodyFatPercent: 29.0),
          thermometer: ThermometerData(temperature: 37.8),
        ),
      ),
      'oksimeter_genggam': r(
        'S-OX',
        const PersonProfile(name: "Opa Hendrik O'Neil", gender: Gender.male, nik: '3578010711520002'),
        const AllMeasurements(
          pulseOximeter: PulseOximeterData(spo2: 93, heartRate: 104),
          gripStrength: GripStrengthData(gripLeft1: 12.0, gripRight1: 13.5),
        ),
      ),
    };
    final dir = Directory('build/satusehat_samples')..createSync(recursive: true);
    for (final e in samples.entries) {
      expect(SatusehatExport.problems(e.value, cfg), isEmpty, reason: e.key);
      File('${dir.path}/${e.key}.json').writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(SatusehatExport.bundle(e.value, cfg)));
    }
    File('${dir.path}/semua.ndjson')
        .writeAsStringSync('${SatusehatExport.batch(samples.values.toList(), cfg).ndjson}\n');
  });
}
