// QA persona 3 — form beranda + keyboard layar + saran pasien + reset.
// Disalin dari tes QA; perilaku yang benar ditegaskan.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/app/motion.dart';
import 'package:health_station_lite/app/theme.dart';
import 'package:health_station_lite/ble/measurement_session.dart';
import 'package:health_station_lite/data/app_settings.dart';
import 'package:health_station_lite/data/device_registry_store.dart';
import 'package:health_station_lite/data/member_store.dart';
import 'package:health_station_lite/data/record_store.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';
import 'package:health_station_lite/screens/home_screen.dart';
import 'package:health_station_lite/screens/measurement_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

const nikFemale = '3201015203580001'; // P, 12-03-1958
const nikMale = '3201011203580001'; // L, 12-03-1958

HealthRecord rec(
  String id,
  String name,
  DateTime at, {
  int? age,
  String? nik,
  Gender? g,
  double? h,
}) => HealthRecord(
  id: id,
  createdAt: at,
  profile: PersonProfile(
    name: name,
    age: age,
    gender: g,
    heightCm: h,
    nik: nik,
    birthDate: nik == null ? null : DateTime(1958, 3, 12),
  ),
  measurements: const AllMeasurements(
    thermometer: ThermometerData(temperature: 36.6),
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

  Future<void> settleIo(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpHome(
    WidgetTester tester, {
    bool keyboard = true,
    List<HealthRecord> records = const [],
    List<Member> members = const [],
  }) async {
    SharedPreferences.setMockInitialValues({
      'settings_onscreen_keyboard': keyboard,
    });
    final rec = Directory.systemTemp.createTempSync('qa3_rec');
    final mem = Directory.systemTemp.createTempSync('qa3_mem');
    // NFC tidak tersedia → form langsung tampil.
    messenger.setMockMethodCallHandler(const MethodChannel('caritahub/nfc'), (
      call,
    ) async {
      return switch (call.method) {
        'status' => {'available': false, 'enabled': false},
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
    });
    await tester.runAsync(() async {
      RecordStore.directoryProvider = () async => rec;
      MemberStore.directoryProvider = () async => mem;
      RecordStore.instance.debugReset();
      MemberStore.instance.debugReset();
      MeasurementSession.debugResetCarryOver();
      await AppSettings.instance.load();
      await DeviceRegistryStore.instance.load();
      await RecordStore.instance.load();
      await MemberStore.instance.load();
      for (final r in records) {
        await RecordStore.instance.add(r);
      }
      for (final m in members) {
        await MemberStore.instance.add(m);
      }
    });
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomeScreen()),
    );
    await settleIo(tester);
  }

  String field(WidgetTester tester, String key) =>
      tester.widget<TextField>(find.byKey(Key(key))).controller!.text;
  bool focused(WidgetTester tester, String key) =>
      tester.widget<TextField>(find.byKey(Key(key))).focusNode!.hasFocus;

  Future<void> kb(WidgetTester tester, String chars) async {
    for (final c in chars.split('')) {
      await tester.tap(find.byKey(Key(c == ' ' ? 'kb_space' : 'kb_$c')));
      await tester.pump();
    }
  }

  Finder genderSeg(String label) => find.descendant(
    of: find.byType(SegmentedButton<Gender?>),
    matching: find.text(label),
  );

  Gender? selectedGender(WidgetTester tester) => tester
      .widget<SegmentedButton<Gender?>>(find.byType(SegmentedButton<Gender?>))
      .selected
      .first;

  Future<PersonProfile?> startAndCapture(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('start_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final f = find.byType(MeasurementScreen);
    if (f.evaluate().isEmpty) return null;
    return tester.widget<MeasurementScreen>(f).profile;
  }

  group('P3 auto-advance', () {
    testWidgets('P3-01 L/P dipilih → fokus ke Umur', (tester) async {
      await pumpHome(tester);
      await kb(tester, 'BUDI');
      await tester.tap(genderSeg('L'));
      await tester.pump();
      expect(selectedGender(tester), Gender.male);
      expect(focused(tester, 'age_field'), isTrue);
      expect(find.text('Umur'), findsWidgets);
    });

    testWidgets('P3-02 umur 2 digit ≥13 → fokus ke Tinggi; ketikan ke tinggi', (
      tester,
    ) async {
      await pumpHome(tester);
      await kb(tester, 'BUDI');
      await tester.tap(genderSeg('L'));
      await tester.pump();
      await kb(tester, '68');
      expect(field(tester, 'age_field'), '68');
      expect(focused(tester, 'height_field'), isTrue);
      await kb(tester, '160');
      await tester.tap(find.byKey(const Key('kb_,')));
      await tester.pump();
      await kb(tester, '5');
      expect(field(tester, 'height_field'), '160,5');
      expect(field(tester, 'age_field'), '68');
    });

    testWidgets('P3-03 umur 10..12 menunggu digit ke-3 (100+)', (tester) async {
      await pumpHome(tester);
      await kb(tester, 'A');
      await tester.tap(genderSeg('P'));
      await tester.pump();
      await kb(tester, '10');
      expect(focused(tester, 'age_field'), isTrue);
      await kb(tester, '2');
      expect(field(tester, 'age_field'), '102');
      expect(focused(tester, 'height_field'), isTrue);
    });

    testWidgets('P3-04 umur maks 3 digit lewat keyboard layar', (tester) async {
      await pumpHome(tester);
      await kb(tester, 'A');
      await tester.tap(find.byKey(const Key('age_field')));
      await tester.pump();
      await kb(tester, '1');
      await kb(tester, '0');
      await kb(tester, '0');
      // sudah pindah ke tinggi; kembali ke umur dan coba tambah digit
      await tester.tap(find.byKey(const Key('age_field')));
      await tester.pump();
      await kb(tester, '9');
      expect(field(tester, 'age_field'), '100');
    });

    testWidgets('P3-05 Lanjut: Nama → Umur → Tinggi (tanpa KTP) lalu tidak ada '
        'tombol Lanjut di kolom terakhir', (tester) async {
      await pumpHome(tester);
      await kb(tester, 'X');
      await tester.tap(find.byKey(const Key('kb_next')));
      await tester.pump();
      expect(focused(tester, 'age_field'), isTrue);
      await tester.tap(find.byKey(const Key('kb_next')));
      await tester.pump();
      expect(focused(tester, 'height_field'), isTrue);
      expect(find.byKey(const Key('kb_next')), findsNothing);
    });

    testWidgets('P3-06 kapitalisasi nama per kata', (tester) async {
      await pumpHome(tester);
      await kb(tester, 'SITI AMINAH');
      expect(field(tester, 'name_field'), 'Siti Aminah');
    });

    testWidgets('P3-07 backspace/hapus di kolom kosong tidak galat', (
      tester,
    ) async {
      await pumpHome(tester);
      await tester.tap(find.byKey(const Key('kb_backspace')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('age_field')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('kb_clear')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('kb_backspace')));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(field(tester, 'name_field'), '');
    });
  });

  group('P3 NIK', () {
    testWidgets(
      'P3-08 saklar NIK → kolom muncul & aktif; NIK P mengisi P+umur',
      (tester) async {
        await pumpHome(tester);
        await kb(tester, 'SITI');
        await tester.tap(find.byKey(const Key('ktp_switch')));
        await tester.pump();
        await tester.pump();
        expect(find.byKey(const Key('nik_field')), findsOneWidget);
        expect(focused(tester, 'nik_field'), isTrue);
        await kb(tester, nikFemale);
        expect(field(tester, 'nik_field'), nikFemale);
        expect(selectedGender(tester), Gender.female);
        expect(field(tester, 'age_field'), isNotEmpty);
        expect(find.text('L/P dan umur diisi dari NIK'), findsOneWidget);
        // saklar mati → NIK & isian otomatis hilang
        await tester.tap(find.byKey(const Key('ktp_switch')));
        await tester.pump();
        expect(find.byKey(const Key('nik_field')), findsNothing);
        expect(selectedGender(tester), isNull);
        expect(field(tester, 'age_field'), '');
        // ketikan berikut masuk ke Nama, bukan NIK yang tersembunyi
        await kb(tester, 'A');
        expect(field(tester, 'name_field'), 'Sitia');
      },
    );

    testWidgets('P3-09 NIK maks 16 digit; digit ke-17 diabaikan', (
      tester,
    ) async {
      await pumpHome(tester);
      await kb(tester, 'A');
      await tester.tap(find.byKey(const Key('ktp_switch')));
      await tester.pump();
      await tester.pump();
      await kb(tester, '${nikFemale}9');
      expect(field(tester, 'nik_field'), nikFemale);
    });

    testWidgets('P3-10 NIK 15 digit → mulai ditolak dengan pesan', (
      tester,
    ) async {
      await pumpHome(tester);
      await kb(tester, 'A');
      await tester.tap(find.byKey(const Key('ktp_switch')));
      await tester.pump();
      await tester.pump();
      await kb(tester, nikFemale.substring(0, 15));
      final p = await startAndCapture(tester);
      expect(p, isNull);
      expect(find.text('NIK harus 16 angka (sekarang 15)'), findsOneWidget);
    });

    testWidgets('P3-11 NIK dikoreksi → umur otomatis ikut diperbarui', (
      tester,
    ) async {
      await pumpHome(tester);
      await kb(tester, 'A');
      await tester.tap(find.byKey(const Key('ktp_switch')));
      await tester.pump();
      await tester.pump();
      await kb(tester, nikFemale); // lahir 1958
      final age1 = field(tester, 'age_field');
      await tester.tap(find.byKey(const Key('kb_backspace')));
      await tester.pump();
      // NIK tidak lengkap → umur otomatis dihapus
      expect(field(tester, 'age_field'), '');
      await kb(tester, '1');
      expect(field(tester, 'age_field'), age1);
    });

    testWidgets('P3-12 L dipilih manual lalu NIK perempuan → peringatan, '
        'pengukuran ditahan sampai L/P diperbaiki', (tester) async {
      await pumpHome(tester);
      await kb(tester, 'SITI');
      await tester.tap(genderSeg('L'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('ktp_switch')));
      await tester.pump();
      await tester.pump();
      await kb(tester, nikFemale);
      // Peringatan langsung tampil di bawah NIK.
      expect(
        find.text('L/P tidak sesuai NIK (NIK: perempuan)'),
        findsOneWidget,
      );
      expect(await startAndCapture(tester), isNull);
      // L/P diperbaiki → peringatan hilang, bisa mulai.
      await tester.tap(genderSeg('P'));
      // Teks galat memudar dulu (animasi InputDecorator).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('L/P tidak sesuai NIK (NIK: perempuan)'), findsNothing);
      final p = await startAndCapture(tester);
      expect(p?.gender, Gender.female);
    });

    testWidgets('P3-12b NIK laki-laki + P dipilih → peringatan', (
      tester,
    ) async {
      await pumpHome(tester);
      await kb(tester, 'BUDI');
      await tester.tap(genderSeg('P'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('ktp_switch')));
      await tester.pump();
      await tester.pump();
      await kb(tester, nikMale);
      expect(
        find.text('L/P tidak sesuai NIK (NIK: laki-laki)'),
        findsOneWidget,
      );
      expect(await startAndCapture(tester), isNull);
    });
  });

  group('P3 validasi mulai', () {
    testWidgets('P3-13 nama hanya spasi → tombol Mulai nonaktif', (
      tester,
    ) async {
      await pumpHome(tester, keyboard: false);
      await tester.enterText(find.byKey(const Key('name_field')), '    ');
      await tester.pump();
      final b = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('start_button')),
      );
      expect(b.enabled, isFalse);
    });

    testWidgets('P3-14 spasi ganda di nama dirapikan', (tester) async {
      await pumpHome(tester, keyboard: false);
      await tester.enterText(
        find.byKey(const Key('name_field')),
        '  Siti    Aminah  ',
      );
      await tester.pump();
      final p = await startAndCapture(tester);
      expect(p?.name, 'Siti Aminah');
    });

    testWidgets('P3-15 tinggi dalam meter (1,55) → diubah ke 155 cm', (
      tester,
    ) async {
      await pumpHome(tester, keyboard: false);
      await tester.enterText(find.byKey(const Key('name_field')), 'Budi');
      await tester.enterText(find.byKey(const Key('height_field')), '1,55');
      await tester.pump();
      final p = await startAndCapture(tester);
      expect(p?.heightCm, 155);
    });

    testWidgets('P3-15b tinggi 300 → pesan "Tinggi 50–250 cm", tidak mulai', (
      tester,
    ) async {
      await pumpHome(tester, keyboard: false);
      await tester.enterText(find.byKey(const Key('name_field')), 'Budi');
      await tester.enterText(find.byKey(const Key('height_field')), '300');
      await tester.pump();
      expect(await startAndCapture(tester), isNull);
      expect(find.text('Tinggi 50–250 cm'), findsOneWidget);
      // Diperbaiki → pesan hilang.
      await tester.enterText(find.byKey(const Key('height_field')), '160');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Tinggi 50–250 cm'), findsNothing);
      expect((await startAndCapture(tester))?.heightCm, 160);
    });

    testWidgets('P3-16 umur 150 / 0 → pesan "Umur 1–129 th", tidak mulai', (
      tester,
    ) async {
      await pumpHome(tester, keyboard: false);
      await tester.enterText(find.byKey(const Key('name_field')), 'Budi');
      await tester.enterText(find.byKey(const Key('age_field')), '150');
      await tester.pump();
      expect(await startAndCapture(tester), isNull);
      expect(find.text('Umur 1–129 th'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('age_field')), '0');
      await tester.pump();
      expect(await startAndCapture(tester), isNull);
      expect(find.text('Umur 1–129 th'), findsOneWidget);
    });

    testWidgets('P3-17 tinggi "160.5.5" (titik ganda) → tidak galat, pesan', (
      tester,
    ) async {
      await pumpHome(tester, keyboard: false);
      await tester.enterText(find.byKey(const Key('name_field')), 'Budi');
      await tester.enterText(find.byKey(const Key('height_field')), '160.5.5');
      await tester.pump();
      expect(field(tester, 'height_field'), '160.5.5');
      final p = await startAndCapture(tester);
      expect(tester.takeException(), isNull);
      expect(p, isNull);
      expect(find.text('Tinggi 50–250 cm'), findsOneWidget);
    });
  });

  group('P3 saran pasien', () {
    final now = DateTime.now();

    testWidgets('P3-18 1 huruf → tanpa saran; 2 huruf → saran; pilih → isi', (
      tester,
    ) async {
      await pumpHome(
        tester,
        records: [
          rec(
            'R1',
            'Siti Aminah',
            now.subtract(const Duration(days: 400)),
            age: 66,
            g: Gender.female,
            h: 152.5,
          ),
        ],
      );
      await kb(tester, 'S');
      expect(find.byKey(const Key('patient_suggestions')), findsNothing);
      await kb(tester, 'I');
      expect(find.byKey(const Key('patient_suggestions')), findsOneWidget);
      await tester.tap(find.byKey(const Key('patient_suggestion_0')));
      await tester.pump();
      expect(field(tester, 'name_field'), 'Siti Aminah');
      expect(field(tester, 'age_field'), '67'); // +1 tahun
      expect(field(tester, 'height_field'), '152,5');
      expect(selectedGender(tester), Gender.female);
      expect(find.byKey(const Key('patient_suggestions')), findsNothing);
      // Nama diubah lagi → saran kembali muncul
      await tester.tap(find.byKey(const Key('kb_backspace')));
      await tester.pump();
      expect(find.byKey(const Key('patient_suggestions')), findsOneWidget);
    });

    testWidgets('P3-19 maks 3 saran, terbaru dulu', (tester) async {
      await pumpHome(
        tester,
        records: [
          for (var i = 0; i < 5; i++)
            rec('R$i', 'Sri Wahyuni $i', now.subtract(Duration(days: i + 1))),
        ],
      );
      await kb(tester, 'SR');
      expect(find.byKey(const Key('patient_suggestion_2')), findsOneWidget);
      expect(find.byKey(const Key('patient_suggestion_3')), findsNothing);
      expect(find.text('Sri Wahyuni 0'), findsOneWidget);
    });

    testWidgets('P3-20 saran dengan NIK anggota → kartu terhubung', (
      tester,
    ) async {
      await pumpHome(
        tester,
        records: [
          rec(
            'R1',
            'Siti Aminah',
            now.subtract(const Duration(days: 3)),
            nik: nikFemale,
            g: Gender.female,
          ),
        ],
        members: [
          Member(
            uid: '0E5E171105C65D',
            profile: const PersonProfile(name: 'Siti Aminah', nik: nikFemale),
            createdAt: now,
            updatedAt: now,
          ),
        ],
      );
      await kb(tester, 'SITI');
      await tester.tap(find.byKey(const Key('patient_suggestion_0')));
      await tester.pump();
      expect(find.byKey(const Key('card_linked_chip')), findsOneWidget);
      expect(find.byKey(const Key('nik_field')), findsOneWidget);
      expect(field(tester, 'nik_field'), nikFemale);
    });
  });

  group('P3 reset setelah sesi dibatalkan', () {
    testWidgets('P3-21 diketik → batal ukur → data tetap untuk diperbaiki', (
      tester,
    ) async {
      await pumpHome(tester, keyboard: false);
      await tester.enterText(find.byKey(const Key('name_field')), 'Budi');
      await tester.enterText(find.byKey(const Key('age_field')), '70');
      await tester.pump();
      final p = await startAndCapture(tester);
      expect(p?.age, 70);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(MeasurementScreen), findsNothing);
      expect(field(tester, 'name_field'), 'Budi');
      expect(field(tester, 'age_field'), '70');
    });

    testWidgets('P3-22 diketik petugas + saran yang punya kartu → batal ukur '
        'tidak boleh menghapus form yang diketik', (tester) async {
      final now = DateTime.now();
      await pumpHome(
        tester,
        records: [
          rec(
            'R1',
            'Siti Aminah',
            now.subtract(const Duration(days: 3)),
            nik: nikFemale,
            g: Gender.female,
            h: 150,
          ),
        ],
        members: [
          Member(
            uid: '0E5E171105C65D',
            profile: const PersonProfile(name: 'Siti Aminah', nik: nikFemale),
            createdAt: now,
            updatedAt: now,
          ),
        ],
      );
      await kb(tester, 'SITI');
      await tester.tap(find.byKey(const Key('patient_suggestion_0')));
      await tester.pump();
      // petugas mengoreksi tinggi
      await tester.tap(find.byKey(const Key('height_field')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('kb_backspace')));
      await tester.pump();
      await kb(tester, '2');
      expect(field(tester, 'height_field'), '152');
      await startAndCapture(tester);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.byKey(const Key('name_field')).evaluate().isNotEmpty &&
            field(tester, 'name_field') == 'Siti Aminah',
        isTrue,
        reason:
            'form yang diketik/dipilih petugas terhapus setelah batal '
            'karena _cardUid terisi dari saran (home_screen.dart:383)',
      );
    });
  });
}
