// QA round 3 — NIK & model defects (scratch, do not ship).
// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';
import 'package:health_station_lite/satusehat/satusehat_export.dart';
import 'package:health_station_lite/utils/nik.dart';

const cfg = SatusehatConfig(
    orgId: '10000004', locationId: 'ef011065-38c9-46f8-9c35-d1fe68966a3e', practitionerId: 'N10000001');

void main() {
  final today = DateTime(2026, 10, 18);

  test('BUG: validate accepts impossible dates (31 Feb, 29 Feb non-leap, 31 Apr)', () {
    for (final nik in ['3201013102580001', '3201012902570001', '3201013104580001']) {
      // decode already knows they are impossible...
      expect(Nik.decode(nik, now: today), isNull, reason: nik);
      // ...but validate()/isValid() accept them, so they pass the form and SATUSEHAT export.
      expect(Nik.validate(nik), isNotNull, reason: 'validate($nik) should reject impossible date');
    }
  });

  test('BUG: impossible-date NIK is exported to SATUSEHAT as "ready"', () {
    final r = HealthRecord(
      id: 'X', createdAt: DateTime(2026, 10, 18, 9),
      profile: const PersonProfile(name: 'A', nik: '3201013102580001'),
      measurements: const AllMeasurements(tensimeter: TensimeterData(systolic: 120, diastolic: 80)),
    );
    expect(SatusehatExport.problems(r, cfg), isNotEmpty);
  });

  test('BUG: decode returns a birth date in the future when YY == current YY', () {
    // Born 15 Dec 1926 (centenarian) -> yy=26; today 18 Oct 2026.
    final d = Nik.decode('3201011512260001', now: today)!;
    print('decoded birthDate=${d.birthDate} age=${Nik.ageOn(d.birthDate, today)}');
    expect(d.birthDate.isAfter(today), isFalse, reason: 'birth date must not be in the future');
    expect(Nik.ageOn(d.birthDate, today), greaterThanOrEqualTo(0));
  });

  test('BUG: clearing/changing NIK keeps stale birthDate (persisted)', () {
    const p = PersonProfile(name: 'A', nik: '3201015203580001');
    final withBirth = p.withNik('3201015203580001', DateTime(1958, 3, 12));
    final cleared = withBirth.withNik(null, Nik.decode('')?.birthDate);
    final back = PersonProfile.fromJson(jsonDecode(jsonEncode(cleared.toJson())));
    print('after clearing NIK: nik=${back.nik} birthDate=${back.birthDate}');
    expect(back.birthDate, isNull, reason: 'birthDate derived from removed NIK must be cleared');
  });

  test('OK: female +40 / century / mask / JSON round trip of nik+birthDate', () {
    final f = Nik.decode('3578015212560003', now: today)!; // 12-12-1956 female
    expect(f.gender, Gender.female);
    expect(f.birthDate, DateTime(1956, 12, 12));
    expect(Nik.decode('3578010101000003', now: today)!.birthDate, DateTime(2000, 1, 1));
    expect(Nik.decode('3578012902000003', now: today)!.birthDate, DateTime(2000, 2, 29));
    expect(Nik.mask('3578015212560003'), '3578********0003');
    expect(Nik.validate('3578013212560003'), isNotNull); // day 32
    expect(Nik.validate('3578017212560003'), isNotNull); // day 72 (=32 female)
    expect(Nik.validate('3578014012560003'), isNotNull); // day 40 (=0 female)
  });
}
