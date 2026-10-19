import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/app/motion.dart';
import 'package:health_station_lite/app/theme.dart';
import 'package:health_station_lite/data/app_settings.dart';
import 'package:health_station_lite/data/patient_lookup.dart';
import 'package:health_station_lite/data/record_store.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';
import 'package:health_station_lite/screens/home_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

HealthRecord rec(String id, DateTime at, PersonProfile p) => HealthRecord(
  id: id,
  createdAt: at,
  profile: p,
  measurements: const AllMeasurements(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    Motion.enabled = false;
    await initializeDateFormatting('id_ID');
  });

  final now = DateTime(2026, 10, 19, 9, 30);
  final records = [
    rec(
      'a1',
      DateTime(2025, 10, 1, 8),
      const PersonProfile(name: 'Siti Aminah', gender: Gender.female, age: 67),
    ),
    rec(
      'a2',
      DateTime(2026, 10, 18, 10, 5),
      const PersonProfile(
        name: 'Siti Aminah',
        gender: Gender.female,
        age: 67,
        heightCm: 152,
      ),
    ),
    rec(
      'b1',
      DateTime(2026, 10, 19, 8, 15),
      const PersonProfile(name: 'Budi Santoso', gender: Gender.male, age: 70),
    ),
    rec(
      'c1',
      DateTime(2026, 9, 2, 8),
      const PersonProfile(name: 'Aminah Sari', gender: Gender.female),
    ),
  ];

  group('findPatients', () {
    test('dikelompokkan per orang, kunjungan terakhir & jumlah', () {
      final m = findPatients('siti', records);
      expect(m, hasLength(1));
      expect(m.single.visits, 2);
      expect(m.single.lastVisit, DateTime(2026, 10, 18, 10, 5));
      expect(m.single.profile.heightCm, 152);
    });

    test('awal nama di depan, lalu awal kata', () {
      final m = findPatients('amin', records);
      expect(m.map((e) => e.profile.name), ['Aminah Sari', 'Siti Aminah']);
    });

    test('kurang dari 2 huruf → tidak mencari', () {
      expect(findPatients('s', records), isEmpty);
      expect(findPatients('zz', records), isEmpty);
    });

    test('umur ikut bertambah sejak kunjungan terakhir', () {
      final m = findPatients('siti', [records.first]).single;
      expect(m.carriedTo(now).age, 68);
    });

    test('label kunjungan terakhir', () {
      expect(
        lastVisitLabel(DateTime(2026, 10, 19, 8, 15), now),
        'Hari ini, 08.15',
      );
      expect(
        lastVisitLabel(DateTime(2026, 10, 18, 10, 5), now),
        'Kemarin, 10.05',
      );
      expect(lastVisitLabel(DateTime(2026, 10, 15), now), '4 hari lalu');
      expect(lastVisitLabel(DateTime(2026, 9, 2), now), '2 Sep 2026');
    });
  });

  testWidgets('beranda: ketik nama → saran riwayat → isi otomatis', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('hs_lookup');
    SharedPreferences.setMockInitialValues({
      'settings_onscreen_keyboard': false,
    });
    await tester.runAsync(() async {
      RecordStore.directoryProvider = () async => dir;
      RecordStore.instance.debugReset();
      await AppSettings.instance.load();
      await RecordStore.instance.load();
      for (final r in records) {
        await RecordStore.instance.add(r);
      }
    });
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomeScreen()),
    );
    await tester.pump();

    expect(find.byKey(const Key('patient_suggestions')), findsNothing);
    await tester.enterText(find.byKey(const Key('name_field')), 'sit');
    await tester.pump();
    expect(find.byKey(const Key('patient_suggestions')), findsOneWidget);
    expect(find.text('Siti Aminah'), findsOneWidget);
    expect(find.text('2× diperiksa'), findsOneWidget);

    await tester.tap(find.byKey(const Key('patient_suggestion_0')));
    await tester.pump();
    final field = tester.widget<TextField>(find.byKey(const Key('name_field')));
    expect(field.controller!.text, 'Siti Aminah');
    final height = tester.widget<TextField>(
      find.byKey(const Key('height_field')),
    );
    expect(height.controller!.text, '152');
    // Setelah dipilih, saran disembunyikan.
    expect(find.byKey(const Key('patient_suggestions')), findsNothing);
    // Beranda hanya untuk pendaftaran: tidak ada kartu Hari ini / Riwayat.
    expect(find.byKey(const Key('today_card')), findsNothing);
  });
}
