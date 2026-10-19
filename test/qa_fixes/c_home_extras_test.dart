// Perbaikan QA tambahan: dialog "Halo" (identitas, 4 dtk), keyboard layar di
// Falcon2 (lebar tombol, "Hapus" tinggi), tata letak Falcon2 tanpa luapan,
// konfirmasi buang perubahan anggota, "Anggota baru" menunggu kartu.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/app/motion.dart';
import 'package:health_station_lite/app/nfc_reader.dart';
import 'package:health_station_lite/app/theme.dart';
import 'package:health_station_lite/data/app_settings.dart';
import 'package:health_station_lite/data/member_store.dart';
import 'package:health_station_lite/data/record_store.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';
import 'package:health_station_lite/screens/home_screen.dart';
import 'package:health_station_lite/screens/members_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _known = '0E5E171105C65D';
const _fresh = '0101021229A23EE02';
const _nikSiti = '3201015203580001'; // P

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    Motion.enabled = false;
    await initializeDateFormatting('id_ID');
  });

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var t = 0;

  Future<void> settleIo(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  void mockNfc({String model = 'I24T02'}) {
    messenger.setMockMethodCallHandler(const MethodChannel('caritahub/nfc'), (
      call,
    ) async {
      return switch (call.method) {
        'status' => {'available': true, 'enabled': true, 'model': model},
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
  }

  Future<void> setUpStores(
    WidgetTester tester, {
    bool keyboard = false,
    List<HealthRecord> records = const [],
  }) async {
    NfcReader.isNewTap(
      'reset-${DateTime.now().microsecondsSinceEpoch}',
      DateTime.now(),
    );
    SharedPreferences.setMockInitialValues({
      'settings_onscreen_keyboard': keyboard,
    });
    final rec = Directory.systemTemp.createTempSync('qa_c_rec');
    final mem = Directory.systemTemp.createTempSync('qa_c_mem');
    await tester.runAsync(() async {
      RecordStore.directoryProvider = () async => rec;
      MemberStore.directoryProvider = () async => mem;
      RecordStore.instance.debugReset();
      MemberStore.instance.debugReset();
      await AppSettings.instance.load();
      await RecordStore.instance.load();
      await MemberStore.instance.load();
      for (final r in records) {
        await RecordStore.instance.add(r);
      }
      final now = DateTime.now();
      await MemberStore.instance.add(
        Member(
          uid: _known,
          profile: const PersonProfile(
            name: 'Siti Aminah',
            gender: Gender.female,
            age: 68,
            heightCm: 152,
            nik: _nikSiti,
          ),
          createdAt: now,
          updatedAt: now,
        ),
      );
    });
  }

  void falcon2(WidgetTester tester) {
    tester.view.physicalSize = const Size(1920, 1200);
    tester.view.devicePixelRatio = 1.75;
    addTearDown(tester.view.reset);
  }

  void tablet(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: home));
    await settleIo(tester);
  }

  Future<void> tap(WidgetTester tester, String uid) async {
    t += 10000;
    await messenger.handlePlatformMessage(
      'caritahub/nfc/tags',
      const StandardMethodCodec().encodeSuccessEnvelope({
        'uid': formatUid(uid),
        'techs': ['NfcA'],
        'time': t,
      }),
      (_) {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> kb(WidgetTester tester, String chars) async {
    for (final c in chars.split('')) {
      await tester.tap(find.byKey(Key(c == ' ' ? 'kb_space' : 'kb_$c')));
      await tester.pump();
    }
  }

  String field(WidgetTester tester, String key) =>
      tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

  group('dialog "Halo"', () {
    testWidgets('nama lengkap + L/P · umur · NIK tersamar, 4 detik', (
      tester,
    ) async {
      mockNfc(model: '');
      await setUpStores(tester);
      tablet(tester);
      await pumpApp(tester, const HomeScreen());
      await tap(tester, _known);
      expect(find.byKey(const Key('card_start_dialog')), findsOneWidget);
      expect(find.text('Halo, Siti Aminah'), findsOneWidget);
      expect(find.text('P · 68 th · NIK 3201********0001'), findsOneWidget);
      // NIK utuh tidak pernah tampil di dialog.
      expect(
        find.descendant(
          of: find.byKey(const Key('card_start_dialog')),
          matching: find.textContaining(_nikSiti),
        ),
        findsNothing,
      );
      expect(find.text('Pengukuran dimulai dalam 4…'), findsOneWidget);
      expect(find.byKey(const Key('card_start_cancel')), findsOneWidget);
      expect(find.byKey(const Key('card_start_now')), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Pengukuran dimulai dalam 1…'), findsOneWidget);
      await tester.tap(find.byKey(const Key('card_start_cancel')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('card_start_dialog')), findsNothing);
    });

    testWidgets('batal setelah tempel kartu → form dikosongkan (alur kartu)', (
      tester,
    ) async {
      mockNfc(model: '');
      await setUpStores(tester);
      tablet(tester);
      await pumpApp(tester, const HomeScreen());
      await tap(tester, _known);
      await tester.tap(find.byKey(const Key('card_start_now')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(field(tester, 'name_field'), '');
    });
  });

  group('NFC beberapa pendengar', () {
    testWidgets('beranda → Anggota → "Anggota baru": kartu ditempel di dialog '
        '→ form anggota dengan UID itu', (tester) async {
      mockNfc();
      await setUpStores(tester);
      tablet(tester);
      await pumpApp(tester, const HomeScreen());
      await tester.tap(find.byKey(const Key('members_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('new_member_button')));
      await settleIo(tester);
      expect(find.byKey(const Key('new_card_dialog')), findsOneWidget);
      // Kartu milik anggota → ditolak di dialog, dialog tetap terbuka.
      await tap(tester, _known);
      expect(find.byKey(const Key('new_card_dialog')), findsOneWidget);
      expect(
        find.text(
          'Kartu ini sudah terdaftar untuk Siti Aminah · pakai kartu lain',
        ),
        findsOneWidget,
      );
      // Beranda di bawah tidak ikut memproses.
      expect(find.byKey(const Key('card_start_dialog')), findsNothing);
      await tap(tester, _fresh);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('new_card_dialog')), findsNothing);
      expect(find.byType(MemberFormScreen), findsOneWidget);
      expect(find.text(formatUid(_fresh)), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('member_name_field')),
        'Rina',
      );
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('member_save_button')));
      await tester.tap(find.byKey(const Key('member_save_button')));
      await settleIo(tester);
      await tester.pumpAndSettle();
      expect(MemberStore.instance.byUid(_fresh)?.profile.name, 'Rina');
      expect(find.byType(MembersScreen), findsOneWidget);
    });

    testWidgets('"Anggota baru" → Batal → tidak ada form', (tester) async {
      mockNfc();
      await setUpStores(tester);
      tablet(tester);
      await pumpApp(tester, const MembersScreen());
      await tester.tap(find.byKey(const Key('new_member_button')));
      await settleIo(tester);
      await tester.tap(find.byKey(const Key('new_card_cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('new_card_dialog')), findsNothing);
      expect(find.byType(MemberFormScreen), findsNothing);
    });
  });

  group('form anggota: buang perubahan', () {
    Future<void> openEdit(WidgetTester tester) async {
      await setUpStores(tester);
      tablet(tester);
      await pumpApp(tester, const MembersScreen());
      await tester.tap(find.byKey(const Key('member_tile_$_known')));
      await tester.pumpAndSettle();
      expect(find.text('Ubah data anggota'), findsOneWidget);
    }

    testWidgets('tanpa perubahan → kembali langsung', (tester) async {
      await openEdit(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Buang perubahan?'), findsNothing);
      expect(find.byType(MemberFormScreen), findsNothing);
    });

    testWidgets('ada perubahan → konfirmasi; "Lanjut mengisi" tetap; '
        '"Buang" keluar tanpa menyimpan', (tester) async {
      await openEdit(tester);
      await tester.enterText(
        find.byKey(const Key('member_height_field')),
        '160',
      );
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Buang perubahan?'), findsOneWidget);
      await tester.tap(find.text('Lanjut mengisi'));
      await tester.pumpAndSettle();
      expect(find.byType(MemberFormScreen), findsOneWidget);
      expect(field(tester, 'member_height_field'), '160');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Buang'));
      await tester.pumpAndSettle();
      expect(find.byType(MemberFormScreen), findsNothing);
      expect(MemberStore.instance.byUid(_known)?.profile.heightCm, 152);
    });

    testWidgets('simpan → keluar tanpa konfirmasi', (tester) async {
      await openEdit(tester);
      await tester.enterText(
        find.byKey(const Key('member_name_field')),
        'Siti Aminah Binti',
      );
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('member_save_button')));
      await tester.tap(find.byKey(const Key('member_save_button')));
      await settleIo(tester);
      await tester.pumpAndSettle();
      expect(find.text('Buang perubahan?'), findsNothing);
      expect(find.byType(MemberFormScreen), findsNothing);
      expect(
        MemberStore.instance.byUid(_known)?.profile.name,
        'Siti Aminah Binti',
      );
    });
  });

  group('keyboard layar Falcon2', () {
    const letters = 'QWERTYUIOPASDFGHJKLZXCVBNM';

    void expectWideKeys(WidgetTester tester) {
      for (final c in letters.split('')) {
        final w = tester.getSize(find.byKey(Key('kb_$c'))).width;
        expect(w, greaterThanOrEqualTo(44), reason: 'tombol $c $w dp');
      }
    }

    testWidgets('beranda kartu: tiap tombol huruf ≥ 44 dp', (tester) async {
      mockNfc();
      await setUpStores(tester, keyboard: true);
      falcon2(tester);
      await pumpApp(tester, const HomeScreen());
      expectWideKeys(tester);
    });

    testWidgets('form anggota: tiap tombol huruf ≥ 44 dp', (tester) async {
      await setUpStores(tester, keyboard: true);
      falcon2(tester);
      await pumpApp(tester, const MemberFormScreen(uid: _fresh));
      expectWideKeys(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keypad tinggi punya "Hapus": 165 terhapus sekali ketuk', (
      tester,
    ) async {
      mockNfc();
      await setUpStores(tester, keyboard: true);
      falcon2(tester);
      await pumpApp(tester, const HomeScreen());
      await tester.tap(find.byKey(const Key('height_field')));
      await tester.pump();
      expect(find.byKey(const Key('kb_,')), findsOneWidget);
      await kb(tester, '165');
      expect(field(tester, 'height_field'), '165');
      await tester.tap(find.byKey(const Key('kb_clear')));
      await tester.pump();
      expect(field(tester, 'height_field'), '');
      expect(tester.takeException(), isNull);
    });
  });

  group('beranda Falcon2 tanpa luapan', () {
    testWidgets('NIK nyala, nama diketik, kartu tertaut, saran tampil', (
      tester,
    ) async {
      final now = DateTime.now();
      mockNfc();
      await setUpStores(
        tester,
        keyboard: true,
        records: [
          for (var i = 0; i < 3; i++)
            HealthRecord(
              id: 'R$i',
              createdAt: now.subtract(Duration(days: i + 1)),
              profile: PersonProfile(
                name: 'Rina Wati $i',
                gender: Gender.female,
                age: 70 + i,
                heightCm: 150,
              ),
              measurements: const AllMeasurements(
                thermometer: ThermometerData(temperature: 36.6),
              ),
            ),
        ],
      );
      falcon2(tester);
      await pumpApp(tester, const HomeScreen());
      await kb(tester, 'RINA');
      expect(find.byKey(const Key('patient_suggestions')), findsOneWidget);
      // Keypad huruf: ketiga saran terlihat utuh di atas keyboard.
      Rect kbNow() =>
          tester.getRect(find.byKey(const Key('onscreen_keyboard')));
      final last = tester.getRect(
        find.byKey(const Key('patient_suggestion_2')),
      );
      expect(last.bottom, lessThanOrEqualTo(kbNow().top));
      await tester.tap(find.byKey(const Key('ktp_switch')));
      await tester.pump();
      await tester.pump();
      await kb(tester, '3201015203580002');
      expect(field(tester, 'nik_field'), '3201015203580002');
      await tester.tap(find.byKey(const Key('link_card_button')));
      await tester.pump();
      await tap(tester, _fresh);
      await settleIo(tester);
      expect(find.byKey(const Key('card_linked_chip')), findsOneWidget);
      expect(find.byKey(const Key('patient_suggestions')), findsOneWidget);
      expect(tester.takeException(), isNull);

      const screen = Size(1920 / 1.75, 1200 / 1.75);
      final nik = tester.getRect(find.byKey(const Key('nik_field')));
      final start = tester.getRect(find.byKey(const Key('start_button')));
      final zone = tester.getRect(find.byKey(const Key('nfc_card_target')));
      final kbRect = tester.getRect(find.byKey(const Key('onscreen_keyboard')));
      // Keypad angka (NIK) lebih tinggi: saran tetap mulai di atas keyboard
      // dan bisa digulir (tanpa luapan).
      final sugg = tester.getRect(
        find.byKey(const Key('patient_suggestion_0')),
      );
      expect(nik.top, greaterThanOrEqualTo(zone.bottom));
      expect(nik.bottom, lessThanOrEqualTo(start.top));
      expect(start.bottom, lessThanOrEqualTo(screen.height));
      expect(kbRect.bottom, lessThanOrEqualTo(screen.height));
      expect(kbRect.right, lessThanOrEqualTo(screen.width));
      expect(sugg.top, lessThan(kbRect.top));
      // Kolom isian di dalam area kartu.
      final chip = tester.getRect(find.byKey(const Key('card_linked_chip')));
      final age = tester.getRect(find.byKey(const Key('age_field')));
      expect(
        zone.contains(chip.topLeft) && zone.contains(age.bottomRight),
        isTrue,
      );
      // Kembali ke nama (keypad huruf) → saran utuh lagi.
      await tester.tap(find.byKey(const Key('name_field')));
      await tester.pump();
      expect(
        tester.getRect(find.byKey(const Key('patient_suggestion_2'))).bottom,
        lessThanOrEqualTo(kbNow().top),
      );

      // Galat L/P vs NIK + tinggi di luar rentang tetap muat.
      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedButton<Gender?>),
          matching: find.text('L'),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('height_field')));
      await tester.pump();
      await kb(tester, '300');
      await tester.tap(find.byKey(const Key('start_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text('L/P tidak sesuai NIK (NIK: perempuan)'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('body_error')), findsOneWidget);
      expect(tester.takeException(), isNull);
      final nik2 = tester.getRect(find.byKey(const Key('nik_field')));
      expect(nik2.bottom, lessThanOrEqualTo(start.top));
    });
  });
}
