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
import 'package:health_station_lite/screens/home_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _known = '0E5E171105C65D';
const _fresh = '0101021229A23EE02';

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

  Future<void> pumpHome(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
    double dpr = 1,
    String model = '',
    bool keyboard = false,
  }) async {
    SharedPreferences.setMockInitialValues({
      'settings_onscreen_keyboard': keyboard,
    });
    final rec = Directory.systemTemp.createTempSync('hs_card_rec');
    final mem = Directory.systemTemp.createTempSync('hs_card_mem');
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
    await tester.runAsync(() async {
      RecordStore.directoryProvider = () async => rec;
      MemberStore.directoryProvider = () async => mem;
      RecordStore.instance.debugReset();
      MemberStore.instance.debugReset();
      await AppSettings.instance.load();
      await RecordStore.instance.load();
      await MemberStore.instance.load();
      final now = DateTime.now();
      await MemberStore.instance.add(
        Member(
          uid: _known,
          profile: const PersonProfile(
            name: 'Siti Aminah',
            gender: Gender.female,
            age: 68,
            heightCm: 152,
          ),
          createdAt: now,
          updatedAt: now,
        ),
      );
    });
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomeScreen()),
    );
    await settleIo(tester);
  }

  /// Tempelkan kartu: event seperti dari Android (waktu berbeda tiap kali
  /// supaya tidak dianggap tempelan ulang).
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

  String field(WidgetTester tester, String key) =>
      tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

  testWidgets('beranda tablet: kotak kartu dan kolom nama satu tampilan', (
    tester,
  ) async {
    await pumpHome(tester);
    expect(find.byKey(const Key('nfc_card_target')), findsOneWidget);
    expect(find.text('Tempelkan kartu di sini'), findsOneWidget);
    expect(find.byKey(const Key('name_field')), findsOneWidget);
    expect(find.byKey(const Key('start_button')), findsOneWidget);
    // Kotak kartu kecil di atas form tidak dipakai lagi (dobel).
    expect(find.byKey(const Key('nfc_tap_box')), findsNothing);
    // Mengetik nama tidak menyembunyikan kotak kartu.
    await tester.enterText(find.byKey(const Key('name_field')), 'Rina');
    await tester.pump();
    expect(find.byKey(const Key('nfc_card_target')), findsOneWidget);
    // Tautkan kartu → kotak besar menampilkan permintaan.
    await tester.tap(find.byKey(const Key('link_card_button')));
    await tester.pump();
    expect(find.text('Tempelkan kartu untuk Rina'), findsOneWidget);
  });

  testWidgets('Falcon2: kotak kartu di atas antena, tanpa luapan', (
    tester,
  ) async {
    await pumpHome(
      tester,
      size: const Size(1920, 1200),
      dpr: 1.75,
      model: 'I24T02',
      keyboard: true,
    );
    final box = tester.getRect(find.byKey(const Key('nfc_card_target')));
    // Area biru seukuran kartu asli (378 × 238 dp) + margin, tengah
    // vertikal; sisa lebar untuk keyboard.
    expect(box.width, closeTo(378 + 24, 1));
    expect(box.height, greaterThan(238));
    expect(box.center.dy, closeTo(1200 / 1.75 / 2, 2));
    final keys = tester.getRect(find.byKey(const Key('onscreen_keyboard')));
    expect(keys.width, greaterThan(560));
    final name = tester.getRect(find.byKey(const Key('name_field')));
    final start = tester.getRect(find.byKey(const Key('start_button')));
    // Nama dan L/P/umur/tinggi di atas latar area kartu.
    final age = tester.getRect(find.byKey(const Key('age_field')));
    expect(box.overlaps(name) && box.overlaps(age), isTrue);
    expect(start.top, greaterThan(box.bottom));
    expect(start.bottom, lessThanOrEqualTo(1200 / 1.75));
    // Kotak kartu & nama dalam satu kartu, sejajar dengan keyboard kanan.
    final panel = tester.getRect(find.byKey(const Key('card_name_panel')));
    final kb = tester.getRect(find.byKey(const Key('onscreen_keyboard')));
    expect(
      panel.contains(box.topLeft) && panel.contains(start.bottomRight),
      isTrue,
    );
    expect(kb.bottom, closeTo(panel.bottom, 1));
  });

  testWidgets('kartu terdaftar → data terisi, hitung mundur mulai', (
    tester,
  ) async {
    await pumpHome(tester);
    await tap(tester, _known);
    expect(find.byKey(const Key('card_start_dialog')), findsOneWidget);
    expect(find.text('Halo, Siti Aminah'), findsOneWidget);
    expect(field(tester, 'name_field'), 'Siti Aminah');
    expect(field(tester, 'height_field'), '152');
    await tester.tap(find.byKey(const Key('card_start_cancel')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('card_linked_chip')), findsOneWidget);
    // Nama diganti → kartu Siti tidak lagi dianggap milik orang ini.
    await tester.enterText(find.byKey(const Key('name_field')), 'Orang lain');
    await tester.pump();
    expect(find.byKey(const Key('card_linked_chip')), findsNothing);
    expect(find.byKey(const Key('link_card_button')), findsOneWidget);
  });

  testWidgets('kartu baru + nama sudah diketik → simpan sebagai anggota', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.enterText(find.byKey(const Key('name_field')), 'Budi');
    await tester.pump();
    await tap(tester, _fresh);
    expect(find.byKey(const Key('unknown_card_dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('card_use_for_form')));
    await settleIo(tester);
    expect(MemberStore.instance.byUid(_fresh)?.profile.name, 'Budi');
    expect(find.byKey(const Key('card_linked_chip')), findsOneWidget);
  });

  testWidgets('tautkan kartu yang sudah dipakai orang lain → ditolak', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.enterText(find.byKey(const Key('name_field')), 'Rina');
    await tester.pump();
    await tester.tap(find.byKey(const Key('link_card_button')));
    await tester.pump();
    expect(find.text('Tempelkan kartu untuk Rina'), findsOneWidget);
    await tap(tester, _known);
    await settleIo(tester);
    expect(
      find.text('Kartu ini sudah terdaftar untuk Siti Aminah'),
      findsOneWidget,
    );
    // Akun Siti tetap utuh; Rina tidak mendapat kartu itu.
    expect(MemberStore.instance.byUid(_known)?.profile.name, 'Siti Aminah');
    expect(MemberStore.instance.members, hasLength(1));
  });

  testWidgets('kartu baru → daftar → tersimpan; dibuka ulang tetap dikenali', (
    tester,
  ) async {
    await pumpHome(tester);
    await tap(tester, _fresh);
    expect(find.byKey(const Key('unknown_card_dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('card_register')));
    await settleIo(tester);
    await tester.tap(find.byKey(const Key('register_new_button')));
    await settleIo(tester);
    await tester.enterText(
      find.byKey(const Key('member_name_field')),
      'Budi Santoso',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('member_save_button')));
    await settleIo(tester);
    expect(MemberStore.instance.byUid(_fresh)?.profile.name, 'Budi Santoso');
    // Hitung mundur "Halo" untuk anggota baru → batalkan.
    expect(find.byKey(const Key('card_start_dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('card_start_cancel')));
    await settleIo(tester);
    // Aplikasi dibuka ulang: data dibaca lagi dari file.
    await tester.runAsync(() async {
      MemberStore.instance.debugReset();
      await MemberStore.instance.load();
    });
    expect(MemberStore.instance.byUid(_fresh)?.profile.name, 'Budi Santoso');
    // Tempel lagi lain waktu (di luar jendela 4 detik kartu sama).
    NfcReader.isNewTap('lain', DateTime(2000));
    await tap(tester, _fresh);
    expect(find.text('Halo, Budi Santoso'), findsOneWidget);
    await tester.tap(find.byKey(const Key('card_start_cancel')));
    await settleIo(tester);
  });

  testWidgets('kartu ber-UID acak (kartu bank) ditolak, tidak didaftarkan', (
    tester,
  ) async {
    await pumpHome(tester);
    await tap(tester, '08A1B2C3');
    expect(find.byKey(const Key('random_uid_dialog')), findsOneWidget);
    expect(find.byKey(const Key('unknown_card_dialog')), findsNothing);
    await tester.tap(find.byKey(const Key('random_uid_ok')));
    await settleIo(tester);
    expect(MemberStore.instance.byUid('08A1B2C3'), isNull);
  });

  testWidgets('e-KTP (NFC-B, PUPI acak) ditolak sebagai kartu anggota', (
    tester,
  ) async {
    await pumpHome(tester);
    t += 10000;
    await messenger.handlePlatformMessage(
      'caritahub/nfc/tags',
      const StandardMethodCodec().encodeSuccessEnvelope({
        'uid': '4D 81 2D 55',
        'techs': ['IsoDep', 'NfcB'],
        'time': t,
      }),
      (_) {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('random_uid_dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('random_uid_ok')));
    await settleIo(tester);
    expect(MemberStore.instance.byUid('4D812D55'), isNull);
  });
}
