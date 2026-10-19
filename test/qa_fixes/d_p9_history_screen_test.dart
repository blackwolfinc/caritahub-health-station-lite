// QA persona 9 (perbaikan D) — layar riwayat: keadaan kosong, rusak,
// hitungan hari ini (per orang), tengah malam, tombol Ekspor.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/app/motion.dart';
import 'package:health_station_lite/app/theme.dart';
import 'package:health_station_lite/data/app_settings.dart';
import 'package:health_station_lite/data/member_store.dart';
import 'package:health_station_lite/data/record_store.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';
import 'package:health_station_lite/screens/history_screen.dart';
import 'package:health_station_lite/widgets/common.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

HealthRecord rec(String id, DateTime at, String name) => HealthRecord(
  id: id,
  createdAt: at,
  startedAt: at.subtract(const Duration(seconds: 125)),
  profile: PersonProfile(name: name),
  measurements: const AllMeasurements(
    tensimeter: TensimeterData(systolic: 130, diastolic: 85),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    Motion.enabled = false;
    await initializeDateFormatting('id_ID');
  });
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<void> settle(WidgetTester tester, [int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> seed(
    WidgetTester tester, {
    List<HealthRecord> records = const [],
    String? rawFile,
  }) async {
    SharedPreferences.setMockInitialValues({
      'settings_onscreen_keyboard': false,
    });
    final recDir = Directory.systemTemp.createTempSync('qa_p9h_rec');
    final memDir = Directory.systemTemp.createTempSync('qa_p9h_mem');
    messenger.setMockMethodCallHandler(const MethodChannel('caritahub/nfc'), (
      call,
    ) async {
      return switch (call.method) {
        'status' => {'available': true, 'enabled': true},
        _ => true,
      };
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('caritahub/nfc/tags'),
      (_) async => null,
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(
        const MethodChannel('caritahub/nfc'),
        null,
      );
      RecordStore.instance.debugReset();
      MemberStore.instance.debugReset();
    });
    await tester.runAsync(() async {
      if (rawFile != null) {
        File(
          '${recDir.path}/health_records_v1.json',
        ).writeAsStringSync(rawFile);
      }
      RecordStore.directoryProvider = () async => recDir;
      MemberStore.directoryProvider = () async => memDir;
      RecordStore.instance.debugReset();
      MemberStore.instance.debugReset();
      await AppSettings.instance.load();
      await RecordStore.instance.load();
      await MemberStore.instance.load();
      for (final r in records) {
        await RecordStore.instance.add(r);
      }
    });
    tester.view.physicalSize = const Size(1920, 1158);
    tester.view.devicePixelRatio = 1.75;
    addTearDown(tester.view.reset);
  }

  Future<void> pump(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: home));
    await settle(tester);
  }

  final now = DateTime.now();
  final today9 = DateTime(now.year, now.month, now.day, 0, 5);
  final yesterday = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(const Duration(minutes: 1)); // 23.59 kemarin
  final older = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(const Duration(days: 9));

  testWidgets('riwayat kosong → pesan kosong Bahasa Indonesia', (tester) async {
    await seed(tester);
    await pump(tester, const HistoryScreen());
    expect(find.text('Belum ada pemeriksaan tersimpan.'), findsOneWidget);
    expect(find.text('Riwayat (0)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cari nama tanpa hasil → "Tidak ada nama yang cocok."', (
    tester,
  ) async {
    await seed(tester, records: [rec('A', today9, 'Siti')]);
    await pump(tester, const HistoryScreen());
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.text('Tidak ada nama yang cocok.'), findsOneWidget);
    // Hapus pencarian → kembali tampil.
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(find.text('Siti'), findsOneWidget);
  });

  testWidgets('pengelompokan hari: Hari ini / Kemarin / tanggal', (
    tester,
  ) async {
    await seed(
      tester,
      records: [
        rec('A', today9, 'Siti'),
        rec('B', yesterday, 'Budi'),
        rec('C', older, 'Rina'),
      ],
    );
    await pump(tester, const HistoryScreen());
    expect(find.text('Hari ini'), findsNWidgets(2)); // kartu rekap + judul
    expect(find.text('Kemarin'), findsOneWidget);
    expect(find.text('Riwayat (3)'), findsOneWidget);
    expect(find.textContaining(RegExp(r'\d{4}$')), findsWidgets);
  });

  testWidgets('hitungan hari ini: 23.59 kemarin tidak dihitung (badge beranda: '
      'home_screen.dart, diuji batch beranda)', (tester) async {
    await seed(
      tester,
      records: [
        rec('A', today9, 'Siti'),
        rec('B', today9.add(const Duration(minutes: 3)), 'Budi'),
        rec('C', yesterday, 'Rina'),
      ],
    );
    await pump(tester, const HistoryScreen());
    expect(find.textContaining('2 lansia · 2 pemeriksaan'), findsOneWidget);
  });

  testWidgets('P9-5: "N lansia" hari ini menghitung orang, bukan pemeriksaan — '
      'ukur ulang orang yang sama tetap 1 lansia', (tester) async {
    await seed(
      tester,
      records: [
        rec('A', today9, 'Siti Aminah'),
        rec('B', today9.add(const Duration(minutes: 4)), 'Siti Aminah'),
        rec('C', today9.add(const Duration(minutes: 9)), 'Budi'),
      ],
    );
    await pump(tester, const HistoryScreen());
    expect(
      find.textContaining('2 lansia · 3 pemeriksaan'),
      findsOneWidget,
      reason: '2 orang diperiksa, 3 pemeriksaan',
    );
    // Rata-rata 125 detik → "2 mnt 5 dtk" (bukan "2m 05d per lansia").
    expect(find.textContaining('rata-rata 2 mnt 5 dtk'), findsOneWidget);
  });

  testWidgets(
    'P9-4: file riwayat rusak → layar Riwayat menampilkan peringatan',
    (tester) async {
      await seed(tester, rawFile: '[{"id":"A","createdAt":');
      expect(RecordStore.instance.skippedOnLoad, -1);
      await pump(tester, const HistoryScreen());
      expect(
        find.textContaining(RegExp('rusak|tidak terbaca')),
        findsWidgets,
        reason: 'petugas mengira data hilang tanpa penjelasan',
      );
    },
  );

  testWidgets('tile riwayat: nama sangat panjang tidak overflow', (
    tester,
  ) async {
    await seed(
      tester,
      records: [
        rec('A', today9, 'Siti Aminah Binti Abdurrahman Wahid Al-Banjari ' * 3),
      ],
    );
    await pump(tester, const HistoryScreen());
    expect(tester.takeException(), isNull);
  });
  testWidgets('P9-4/P9-2: banner Riwayat bisa ditandai "Sudah ditangani"', (
    tester,
  ) async {
    await seed(tester, rawFile: 'garbage');
    await pump(tester, const HistoryScreen());
    expect(find.byKey(const Key('corrupt_banner')), findsOneWidget);
    await tester.tap(find.byKey(const Key('corrupt_dismiss')));
    await settle(tester, 3);
    await tester.tap(find.widgetWithText(FilledButton, 'Sudah ditangani'));
    await settle(tester, 5);
    expect(find.byKey(const Key('corrupt_banner')), findsNothing);
    expect(RecordStore.instance.skippedOnLoad, 0);
  });

  testWidgets('P9-2: 1 simpan + buka ulang → banner Riwayat tetap ada', (
    tester,
  ) async {
    await seed(tester, rawFile: 'garbage', records: [rec('A', today9, 'Siti')]);
    await tester.runAsync(() async {
      RecordStore.instance.debugReset();
      await RecordStore.instance.load();
    });
    expect(RecordStore.instance.records, hasLength(1));
    await pump(tester, const HistoryScreen());
    expect(find.byKey(const Key('corrupt_banner')), findsOneWidget);
    expect(find.textContaining('belum ditangani'), findsOneWidget);
  });

  testWidgets('P9-6: lewat tengah malam → "Hari ini" dihitung ulang', (
    tester,
  ) async {
    final day = DateTime(now.year, now.month, now.day);
    final late = day.add(const Duration(hours: 23, minutes: 59, seconds: 40));
    var clock = late;
    DayTicker.clock = () => clock;
    addTearDown(() => DayTicker.clock = DateTime.now);
    await seed(
      tester,
      records: [rec('A', day.add(const Duration(hours: 9)), 'Siti')],
    );
    await pump(tester, const HistoryScreen());
    expect(find.textContaining('1 lansia'), findsOneWidget);
    expect(find.text('Hari ini'), findsNWidgets(2));
    clock = day.add(const Duration(days: 1, seconds: 5));
    await tester.pump(const Duration(seconds: 31));
    expect(find.text('Belum ada lansia diperiksa'), findsOneWidget);
    expect(find.text('Kemarin'), findsOneWidget);
  });

  testWidgets('P10-8: tombol Ekspor ≥48 dp', (tester) async {
    await seed(tester, records: [rec('A', today9, 'Siti')]);
    await pump(tester, const HistoryScreen());
    final size = tester.getSize(
      find.descendant(
        of: find.byKey(const Key('export_menu')),
        matching: find.byType(InkWell),
      ),
    );
    expect(size.height, greaterThanOrEqualTo(48));
    expect(size.width, greaterThanOrEqualTo(48));
  });

  test('format durasi Bahasa Indonesia', () {
    expect(formatDurationId(18), '18 detik');
    expect(formatDurationId(60), '1 mnt');
    expect(formatDurationId(80), '1 mnt 20 dtk');
    expect(formatDurationId(0), '0 detik');
  });
}
