import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/app/motion.dart';
import 'package:health_station_lite/app/theme.dart';
import 'package:health_station_lite/data/app_settings.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/screens/home_screen.dart';
import 'package:health_station_lite/utils/nik.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _nik = '3201015203580001';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => Motion.enabled = false);

  Future<void> pumpHome(
    WidgetTester tester,
    Size size, {
    required bool? on,
  }) async {
    SharedPreferences.setMockInitialValues({'settings_onscreen_keyboard': ?on});
    await tester.runAsync(AppSettings.instance.load);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomeScreen()),
    );
    await tester.pump();
  }

  String text(WidgetTester tester, String key) =>
      tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pump();
  }

  testWidgets('mode mati: keyboard layar tidak tampil', (tester) async {
    await pumpHome(tester, const Size(1280, 800), on: false);
    expect(find.byKey(const Key('onscreen_keyboard')), findsNothing);
  });

  testWidgets('belum dipilih: nyala di tablet, mati di genggam', (
    tester,
  ) async {
    await pumpHome(tester, const Size(1280, 800), on: null);
    expect(find.byKey(const Key('onscreen_keyboard')), findsOneWidget);
    await pumpHome(tester, const Size(400, 800), on: null);
    expect(find.byKey(const Key('onscreen_keyboard')), findsNothing);
  });

  testWidgets('tablet lanskap: form kiri, keyboard kanan, isi lengkap', (
    tester,
  ) async {
    await pumpHome(tester, const Size(1280, 800), on: true);
    final kb = find.byKey(const Key('onscreen_keyboard'));
    expect(kb, findsOneWidget);
    expect(
      tester.getTopLeft(kb).dx,
      greaterThan(tester.getTopRight(find.byKey(const Key('name_field'))).dx),
    );

    // Nama: huruf kapital tiap awal kata, sisanya kecil.
    for (final k in [
      'S',
      'I',
      'T',
      'I',
      'space',
      'A',
      'M',
      'I',
      'N',
      'A',
      'H',
      'H',
    ]) {
      await tap(tester, 'kb_$k');
    }
    await tap(tester, 'kb_backspace');
    expect(text(tester, 'name_field'), 'Siti Aminah');

    // Tanpa KTP kolom NIK tersembunyi.
    expect(find.byKey(const Key('nik_field')), findsNothing);

    // Saklar KTP → kolom NIK muncul & aktif, keypad angka; NIK lengkap
    // mengisi L/P dan umur.
    await tap(tester, 'ktp_switch');
    expect(find.byKey(const Key('nik_field')), findsOneWidget);
    expect(find.byKey(const Key('kb_Q')), findsNothing);
    for (final d in _nik.split('')) {
      await tap(tester, 'kb_$d');
    }
    await tap(tester, 'kb_9'); // lebih dari 16 digit ditolak formatter
    expect(text(tester, 'nik_field'), _nik);
    final age = Nik.ageOn(Nik.decode(_nik)!.birthDate, DateTime.now());
    expect(text(tester, 'age_field'), '$age');

    // Tinggi pakai koma.
    await tap(tester, 'kb_next');
    await tap(tester, 'kb_next');
    for (final k in ['1', '5', '8', ',', '5']) {
      await tap(tester, 'kb_$k');
    }
    expect(text(tester, 'height_field'), '158,5');
    expect(find.byKey(const Key('kb_next')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tanpa KTP: Lanjut dari nama melompati NIK ke umur', (
    tester,
  ) async {
    await pumpHome(tester, const Size(1280, 800), on: true);
    await tap(tester, 'kb_next');
    expect(find.text('Umur'), findsWidgets);
    expect(find.byKey(const Key('kb_Q')), findsNothing);
    await tap(tester, 'kb_7');
    expect(text(tester, 'age_field'), '7');
    // Saklar dimatikan lagi → NIK beserta isian otomatisnya dihapus.
    await tap(tester, 'ktp_switch');
    await tap(tester, 'ktp_switch');
    expect(find.byKey(const Key('nik_field')), findsNothing);
  });

  testWidgets('L/P → umur → otomatis ke tinggi', (tester) async {
    await pumpHome(tester, const Size(1280, 800), on: true);
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<Gender?>),
        matching: find.text('P'),
      ),
    );
    await tester.pump();
    expect(find.text('Umur'), findsWidgets);
    expect(find.byKey(const Key('kb_Q')), findsNothing);
    // 1 lalu 0: bisa jadi 100+ → tetap di umur.
    await tap(tester, 'kb_1');
    await tap(tester, 'kb_0');
    expect(find.byKey(const Key('kb_,')), findsNothing);
    await tap(tester, 'kb_2');
    expect(text(tester, 'age_field'), '102');
    expect(find.byKey(const Key('kb_,')), findsOneWidget); // keypad tinggi
    // 68 → langsung ke tinggi.
    await tester.tap(find.byKey(const Key('age_field')));
    await tester.pump();
    await tap(tester, 'kb_clear');
    await tap(tester, 'kb_6');
    await tap(tester, 'kb_8');
    expect(text(tester, 'age_field'), '68');
    expect(find.byKey(const Key('kb_,')), findsOneWidget);
  });

  testWidgets('mode kiosk: masuk langsung, keluar minta konfirmasi', (
    tester,
  ) async {
    await pumpHome(tester, const Size(1280, 800), on: true);
    await tap(tester, 'kiosk_toggle');
    await tester.pump();
    expect(AppSettings.instance.kioskMode, isTrue);
    await tap(tester, 'kiosk_toggle');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Keluar dari mode kiosk?'), findsOneWidget);
    await tester.tap(find.text('Keluar kiosk'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(AppSettings.instance.kioskMode, isFalse);
  });

  testWidgets('tombol Riwayat di header', (tester) async {
    await pumpHome(tester, const Size(1280, 800), on: true);
    expect(find.byKey(const Key('history_button')), findsOneWidget);
  });

  testWidgets('tombol Mulai nonaktif sampai nama diisi', (tester) async {
    await pumpHome(tester, const Size(1280, 800), on: true);
    final submit = find.byKey(const Key('kb_submit'));
    expect(tester.widget<InkWell>(submit).onTap, isNull);
    await tap(tester, 'kb_A');
    expect(tester.widget<InkWell>(submit).onTap, isNotNull);
  });

  testWidgets('tombol header menyalakan & mematikan mode', (tester) async {
    await pumpHome(tester, const Size(1280, 800), on: false);
    await tap(tester, 'keyboard_mode_toggle');
    expect(find.byKey(const Key('onscreen_keyboard')), findsOneWidget);
    expect(AppSettings.instance.onScreenKeyboard, isTrue);
    await tap(tester, 'keyboard_mode_toggle');
    expect(find.byKey(const Key('onscreen_keyboard')), findsNothing);
  });

  for (final size in const [Size(800, 1280), Size(1024, 768), Size(400, 800)]) {
    testWidgets('tanpa overflow ${size.width.toInt()}x${size.height.toInt()}', (
      tester,
    ) async {
      await pumpHome(tester, size, on: true);
      await tap(tester, 'kb_next');
      expect(tester.takeException(), isNull);
    });
  }
}
