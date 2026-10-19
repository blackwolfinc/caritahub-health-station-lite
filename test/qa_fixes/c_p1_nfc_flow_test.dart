// QA persona 1 — alur kartu NFC (beranda), disesuaikan ke beranda satu
// tampilan (kolom nama selalu tampil di tablet ber-NFC).
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
import 'package:health_station_lite/screens/home_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _known = '0E5E171105C65D';
const _known2 = '04A1B2C3D4E5F6';
const _fresh = '0101021229A23EE02';
const _fresh2 = '0499887766';
const _nikSiti = '3201015203580001';

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

  final navKey = GlobalKey<NavigatorState>();

  Future<void> pumpHome(WidgetTester tester, {bool sitiHasNik = false}) async {
    // Lupakan kartu terakhir dari tes sebelumnya (jendela 4 detik).
    NfcReader.isNewTap(
      'reset-${DateTime.now().microsecondsSinceEpoch}',
      DateTime.now(),
    );
    SharedPreferences.setMockInitialValues({
      'settings_onscreen_keyboard': false,
    });
    final rec = Directory.systemTemp.createTempSync('qa_p1_rec');
    final mem = Directory.systemTemp.createTempSync('qa_p1_mem');
    messenger.setMockMethodCallHandler(const MethodChannel('caritahub/nfc'), (
      call,
    ) async {
      return switch (call.method) {
        'status' => {'available': true, 'enabled': true, 'model': 'I24T02'},
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
          profile: PersonProfile(
            name: 'Siti Aminah',
            gender: Gender.female,
            age: 68,
            heightCm: 152,
            nik: sitiHasNik ? _nikSiti : null,
          ),
          createdAt: now,
          updatedAt: now,
        ),
      );
      await MemberStore.instance.add(
        Member(
          uid: _known2,
          profile: const PersonProfile(name: 'Budi Santoso', age: 70),
          createdAt: now,
          updatedAt: now,
        ),
      );
    });
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        theme: buildAppTheme(),
        home: const HomeScreen(),
      ),
    );
    await settleIo(tester);
  }

  Future<void> send(Object? data) => messenger.handlePlatformMessage(
    'caritahub/nfc/tags',
    const StandardMethodCodec().encodeSuccessEnvelope(data),
    (_) {},
  );

  Future<void> tap(WidgetTester tester, String uid, {bool pump = true}) async {
    t += 10000;
    await send({
      'uid': formatUid(uid),
      'techs': ['NfcA'],
      'time': t,
    });
    if (pump) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  String field(WidgetTester tester, String key) =>
      tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

  group('NfcReader.isNewTap (jendela kartu sama)', () {
    test('kartu sama < 4 dtk diabaikan; jendela bergeser', () {
      final t0 = DateTime(2026, 10, 19, 9);
      expect(NfcReader.isNewTap('AA', t0), isTrue);
      expect(
        NfcReader.isNewTap('AA', t0.add(const Duration(seconds: 3))),
        isFalse,
      );
      // Masih ditahan di pembaca: jendela diperpanjang dari bacaan terakhir.
      expect(
        NfcReader.isNewTap('AA', t0.add(const Duration(seconds: 6))),
        isFalse,
      );
      expect(
        NfcReader.isNewTap(
          'AA',
          t0.add(const Duration(seconds: 10, milliseconds: 1)),
        ),
        isTrue,
      );
    });

    test('kartu berbeda langsung diterima; A-B-A juga diterima', () {
      final t0 = DateTime(2026, 10, 19, 10);
      expect(NfcReader.isNewTap('AA', t0), isTrue);
      expect(
        NfcReader.isNewTap('BB', t0.add(const Duration(milliseconds: 10))),
        isTrue,
      );
      expect(
        NfcReader.isNewTap('AA', t0.add(const Duration(milliseconds: 20))),
        isTrue,
      );
    });

    test('tepat 4 dtk = tempelan baru (batas)', () {
      final t0 = DateTime(2026, 10, 19, 11);
      expect(NfcReader.isNewTap('CC', t0), isTrue);
      expect(
        NfcReader.isNewTap('CC', t0.add(const Duration(seconds: 4))),
        isTrue,
      );
    });
  });

  testWidgets('dua kartu berbeda dalam satu frame → hanya satu dialog', (
    tester,
  ) async {
    await pumpHome(tester);
    await tap(tester, _known, pump: false);
    await tap(tester, _known2, pump: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('card_start_dialog')), findsOneWidget);
    expect(find.text('Halo, Siti Aminah'), findsOneWidget);
    expect(find.text('Halo, Budi Santoso'), findsNothing);
    await tester.tap(find.byKey(const Key('card_start_cancel')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(field(tester, 'name_field'), 'Siti Aminah');
  });

  testWidgets('kartu lain ditempel saat hitung mundur → diabaikan', (
    tester,
  ) async {
    await pumpHome(tester);
    await tap(tester, _known);
    expect(find.byKey(const Key('card_start_dialog')), findsOneWidget);
    await tap(tester, _known2);
    await tap(tester, _fresh);
    expect(find.byKey(const Key('card_start_dialog')), findsOneWidget);
    expect(find.byKey(const Key('unknown_card_dialog')), findsNothing);
    expect(find.text('Halo, Budi Santoso'), findsNothing);
    await tester.tap(find.byKey(const Key('card_start_cancel')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    for (final e in find.byType(AlertDialog).evaluate()) {
      // ignore: avoid_print
      print(
        'DIALOG MASIH ADA: ${(e.widget as AlertDialog).key} '
        '${((e.widget as AlertDialog).title as Text?)?.data}',
      );
    }
    expect(field(tester, 'name_field'), 'Siti Aminah');
    expect(find.byKey(const Key('card_start_dialog')), findsNothing);
  });

  testWidgets('kartu ditempel saat dialog kartu baru terbuka → diabaikan; '
      'setelah Batal kartu berikutnya diproses', (tester) async {
    await pumpHome(tester);
    await tap(tester, _fresh);
    expect(find.byKey(const Key('unknown_card_dialog')), findsOneWidget);
    await tap(tester, _known);
    expect(find.byKey(const Key('card_start_dialog')), findsNothing);
    await tester.tap(find.text('Batal'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    for (final e in find.byType(AlertDialog).evaluate()) {
      // ignore: avoid_print
      print(
        'DIALOG MASIH ADA: ${(e.widget as AlertDialog).key} '
        '${((e.widget as AlertDialog).title as Text?)?.data}',
      );
    }
    expect(find.byKey(const Key('unknown_card_dialog')), findsNothing);
    // Status "sibuk" sudah dilepas.
    await tap(tester, _known2);
    expect(find.text('Halo, Budi Santoso'), findsOneWidget);
    expect(MemberStore.instance.byUid(_fresh), isNull);
    await tester.tap(find.byKey(const Key('card_start_cancel')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets(
    'kontrol: kartu LAIN setelah kembali dari layar lain → diproses',
    (tester) async {
      await pumpHome(tester);
      navKey.currentState!.push(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('layar lain')),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, _known);
      navKey.currentState!.pop();
      await tester.pumpAndSettle();
      await tap(tester, _known2);
      expect(find.text('Halo, Budi Santoso'), findsOneWidget);
      await tester.tap(find.byKey(const Key('card_start_cancel')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    },
  );

  testWidgets('kartu ditempel di layar lain → tidak ada aksi di beranda', (
    tester,
  ) async {
    await pumpHome(tester);
    navKey.currentState!.push(
      MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('layar lain')),
      ),
    );
    await tester.pumpAndSettle();
    await tap(tester, _known);
    await tap(tester, _fresh);
    expect(find.byKey(const Key('card_start_dialog')), findsNothing);
    expect(find.byKey(const Key('unknown_card_dialog')), findsNothing);
    navKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('card_start_dialog')), findsNothing);
    expect(find.byKey(const Key('unknown_card_dialog')), findsNothing);
  });

  testWidgets('kartu yang diabaikan di layar lain tetap bisa ditempel lagi '
      'segera setelah kembali ke beranda', (tester) async {
    await pumpHome(tester);
    navKey.currentState!.push(
      MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('layar lain')),
      ),
    );
    await tester.pumpAndSettle();
    await tap(tester, _known); // diabaikan (beranda tidak di depan)
    navKey.currentState!.pop();
    await tester.pumpAndSettle();
    // Lansia menempel ulang (< 4 dtk) karena tadi tidak terjadi apa-apa.
    await tap(tester, _known);
    final shown = find
        .byKey(const Key('card_start_dialog'))
        .evaluate()
        .isNotEmpty;
    if (shown) {
      await tester.tap(find.byKey(const Key('card_start_cancel')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(
      shown,
      isTrue,
      reason:
          'tempelan pertama tidak diproses, jadi tempelan kedua bukan '
          '"bacaan ulang" — seharusnya tidak ditelan jendela 4 detik',
    );
  });

  testWidgets('event NFC rusak (tanpa uid / uid bukan teks / bukan map) '
      'tidak membuat crash; kartu berikutnya tetap terbaca', (tester) async {
    await pumpHome(tester);
    await send({
      'techs': ['NfcA'],
    });
    await send({'uid': 12345});
    await send('bukan map');
    await send({'uid': '-- :: --'});
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('unknown_card_dialog')), findsNothing);
    await tap(tester, _known2);
    expect(find.text('Halo, Budi Santoso'), findsOneWidget);
    await tester.tap(find.byKey(const Key('card_start_cancel')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('satu kartu = satu akun: kartu baru dipakai Budi, lalu tidak '
      'bisa ditautkan ke Ani', (tester) async {
    await pumpHome(tester);
    await tester.enterText(find.byKey(const Key('name_field')), 'Budi Baru');
    await tester.pump();
    await tap(tester, _fresh);
    await tester.tap(find.byKey(const Key('card_use_for_form')));
    await settleIo(tester);
    expect(MemberStore.instance.byUid(_fresh)?.profile.name, 'Budi Baru');
    await tester.enterText(find.byKey(const Key('name_field')), 'Ani');
    await tester.pump();
    await tester.tap(find.byKey(const Key('link_card_button')));
    await tester.pump();
    NfcReader.isNewTap('reset2', DateTime.now());
    await tap(tester, _fresh);
    await settleIo(tester);
    expect(
      find.text('Kartu ini sudah terdaftar untuk Budi Baru'),
      findsOneWidget,
    );
    expect(MemberStore.instance.byUid(_fresh)?.profile.name, 'Budi Baru');
    expect(MemberStore.instance.members, hasLength(3));
  });

  testWidgets('tautkan kartu dengan NIK tidak lengkap → ditolak, anggota '
      'tidak tersimpan dengan NIK salah', (tester) async {
    await pumpHome(tester);
    await tester.enterText(find.byKey(const Key('name_field')), 'Rina');
    await tester.tap(find.byKey(const Key('ktp_switch')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('nik_field')), '320101');
    await tester.pump();
    await tester.tap(find.byKey(const Key('link_card_button')));
    await tester.pump();
    // Tidak masuk mode tunggu; pesan NIK tampil.
    expect(find.text('Tempelkan kartu untuk Rina'), findsNothing);
    expect(find.text('NIK harus 16 angka (sekarang 6)'), findsOneWidget);
    // Kartu baru → "Kartu untuk Rina" juga ditolak.
    await tap(tester, _fresh);
    expect(find.byKey(const Key('unknown_card_dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('card_use_for_form')));
    await settleIo(tester);
    expect(MemberStore.instance.byUid(_fresh), isNull);
    expect(find.textContaining('perbaiki dulu'), findsOneWidget);
  });

  testWidgets('tautkan kartu milik orang yang sama (NIK sama, kartu sama) → '
      'dianggap sudah tertaut, bukan pesan "milik orang lain"', (tester) async {
    await pumpHome(tester, sitiHasNik: true);
    await tester.enterText(find.byKey(const Key('name_field')), 'Siti A');
    await tester.tap(find.byKey(const Key('ktp_switch')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('nik_field')), _nikSiti);
    await tester.pump();
    await tester.tap(find.byKey(const Key('link_card_button')));
    await tester.pump();
    await tap(tester, _known);
    await settleIo(tester);
    expect(
      find.textContaining('sudah terdaftar untuk Siti Aminah'),
      findsNothing,
      reason: 'kartu & NIK milik orang yang sama — bukan konflik',
    );
    expect(find.byKey(const Key('card_linked_chip')), findsOneWidget);
  });

  testWidgets('NIK milik anggota lain di kartu lama → tawarkan pindah; '
      'akun tetap satu', (tester) async {
    await pumpHome(tester, sitiHasNik: true);
    await tester.enterText(find.byKey(const Key('name_field')), 'Siti Aminah');
    await tester.tap(find.byKey(const Key('ktp_switch')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('nik_field')), _nikSiti);
    await tester.pump();
    await tester.tap(find.byKey(const Key('link_card_button')));
    await tester.pump();
    await tap(tester, _fresh2);
    await tester.pumpAndSettle();
    expect(find.text('NIK sudah terdaftar'), findsOneWidget);
    await tester.tap(find.text('Pindahkan'));
    await settleIo(tester);
    expect(MemberStore.instance.byUid(_known), isNull);
    expect(MemberStore.instance.byUid(_fresh2)?.profile.nik, _nikSiti);
    expect(MemberStore.instance.members, hasLength(2));
  });

  testWidgets('nama dikosongkan saat menunggu kartu → mode tunggu bisa '
      'dibatalkan / tidak menggantung', (tester) async {
    await pumpHome(tester);
    await tester.enterText(find.byKey(const Key('name_field')), 'Rina');
    await tester.pump();
    await tester.tap(find.byKey(const Key('link_card_button')));
    await tester.pump();
    expect(find.text('Tempelkan kartu untuk Rina'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('name_field')), '');
    await tester.pump();
    final stuck = find.text('Tempelkan kartu untuk ').evaluate().isNotEmpty;
    final canCancel = find.text('Batal tautkan kartu').evaluate().isNotEmpty;
    expect(
      !stuck || canCancel,
      isTrue,
      reason:
          'prompt "Tempelkan kartu untuk " (nama kosong) tetap tampil '
          'tanpa tombol batal',
    );
  });

  testWidgets('hitung mundur selesai sendiri → pengukuran dimulai '
      '(tanpa sentuhan)', (tester) async {
    await pumpHome(tester);
    await tap(tester, _known2);
    expect(find.byKey(const Key('card_start_dialog')), findsOneWidget);
    expect(find.text('Pengukuran dimulai dalam 4…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Pengukuran dimulai dalam 3…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    // Masih terbuka setelah 3 dtk: lansia sempat bereaksi.
    expect(find.byKey(const Key('card_start_dialog')), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('card_start_dialog')), findsNothing);
    expect(find.byType(HomeScreen, skipOffstage: false), findsOneWidget);
    // Layar pengukuran di atas beranda.
    expect(navKey.currentState!.canPop(), isTrue);
  });

  testWidgets('anggota dengan NIK tidak lengkap (data lama) → tempel kartu '
      '→ pesan jelas + form terisi, tanpa hitung mundur; diperbaiki → mulai', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.runAsync(() async {
      final now = DateTime.now();
      await MemberStore.instance.add(
        Member(
          uid: _fresh,
          profile: const PersonProfile(name: 'Rina', nik: '320101'),
          createdAt: now,
          updatedAt: now,
        ),
      );
    });
    await tap(tester, _fresh);
    expect(find.byKey(const Key('card_start_dialog')), findsNothing);
    expect(find.byKey(const Key('card_invalid_dialog')), findsOneWidget);
    expect(find.textContaining('NIK harus 16 angka'), findsWidgets);
    await tester.tap(find.byKey(const Key('card_invalid_form')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('card_invalid_dialog')), findsNothing);
    expect(field(tester, 'name_field'), 'Rina');
    expect(field(tester, 'nik_field'), '320101');
    expect(find.text('NIK harus 16 angka (sekarang 6)'), findsOneWidget);
    expect(find.byKey(const Key('card_linked_chip')), findsOneWidget);
    // Petugas memperbaiki NIK lalu mulai.
    await tester.enterText(find.byKey(const Key('nik_field')), _nikSiti);
    await tester.pump();
    await tester.tap(find.byKey(const Key('start_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(navKey.currentState!.canPop(), isTrue);
  });

  testWidgets('anggota dengan NIK salah → "Ubah data anggota" membuka form '
      'anggota', (tester) async {
    await pumpHome(tester);
    await tester.runAsync(() async {
      final now = DateTime.now();
      await MemberStore.instance.add(
        Member(
          uid: _fresh,
          profile: const PersonProfile(name: 'Rina', nik: '320101'),
          createdAt: now,
          updatedAt: now,
        ),
      );
    });
    await tap(tester, _fresh);
    await tester.tap(find.byKey(const Key('card_invalid_edit')));
    await tester.pumpAndSettle();
    expect(find.text('Ubah data anggota'), findsWidgets);
    expect(find.byKey(const Key('member_nik_field')), findsOneWidget);
  });
}
