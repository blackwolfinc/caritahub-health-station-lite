// QA putaran 6 — grafik tren tidak mencampur dua lansia bernama sama.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/data/record_store.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';
import 'package:health_station_lite/screens/result_screen.dart';

void main() {
  const a = PersonProfile(name: 'Siti Aminah', nik: '3201015203580001');
  const b = PersonProfile(name: 'Siti  aminah ', nik: '3201014507490002');
  const noNik = PersonProfile(name: 'siti aminah');

  test('NIK berbeda = orang berbeda meski nama sama', () {
    expect(samePerson(a, b), isFalse);
  });
  test('NIK sama = orang sama meski nama ditulis lain', () {
    expect(
      samePerson(
        a,
        const PersonProfile(name: 'Hj. Siti', nik: '3201-0152-0358-0001'),
      ),
      isTrue,
    );
  });
  test(
    'tanpa NIK di salah satu sisi → cocokkan nama (huruf/spasi diabaikan)',
    () {
      expect(samePerson(a, noNik), isTrue);
      expect(samePerson(noNik, const PersonProfile(name: 'Sutrisno')), isFalse);
    },
  );

  test(
    'riwayat tetap urut terbaru dulu walau disimpan tidak berurutan',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final dir = await Directory.systemTemp.createTemp('qa_r6_order');
      RecordStore.directoryProvider = () async => dir;
      final store = RecordStore.instance..debugReset();
      await store.load();
      HealthRecord rec(String id, DateTime at) => HealthRecord(
        id: id,
        createdAt: at,
        profile: const PersonProfile(name: 'X'),
        measurements: const AllMeasurements(
          thermometer: ThermometerData(temperature: 36.5),
        ),
      );
      await store.add(rec('pagi', DateTime(2026, 10, 18, 8)));
      await store.add(rec('siang', DateTime(2026, 10, 18, 12)));
      // Jam perangkat sempat mundur (baterai habis / sinkron NTP).
      await store.add(rec('bulan-lalu', DateTime(2026, 9, 18, 9)));
      await store.add(rec('sore', DateTime(2026, 10, 18, 16)));
      expect(store.records.map((r) => r.id), [
        'sore',
        'siang',
        'pagi',
        'bulan-lalu',
      ]);
    },
  );
}
