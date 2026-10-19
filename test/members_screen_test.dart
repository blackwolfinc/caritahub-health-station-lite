import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/app/motion.dart';
import 'package:health_station_lite/app/theme.dart';
import 'package:health_station_lite/data/app_settings.dart';
import 'package:health_station_lite/data/member_store.dart';
import 'package:health_station_lite/data/record_store.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';
import 'package:health_station_lite/screens/members_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _uid = '0E5E171105C65D';

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

  /// Hasil `Navigator.pop` dari MembersScreen.
  Member? popped;
  var didPop = false;

  Future<void> pumpScreen(
    WidgetTester tester, {
    String? pendingUid,
    List<HealthRecord> records = const [],
    List<Member> members = const [],
    bool? onScreenKeyboard = false,
    Size size = const Size(1280, 800),
  }) async {
    popped = null;
    didPop = false;
    SharedPreferences.setMockInitialValues({
      'settings_onscreen_keyboard': ?onScreenKeyboard,
    });
    final recDir = Directory.systemTemp.createTempSync('hs_rec');
    final memDir = Directory.systemTemp.createTempSync('hs_mem');
    addTearDown(() {
      RecordStore.instance.debugReset();
      MemberStore.instance.debugReset();
      recDir.deleteSync(recursive: true);
      memDir.deleteSync(recursive: true);
    });
    await tester.runAsync(() async {
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
      for (final m in members) {
        await MemberStore.instance.upsert(m);
      }
    });
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const Key('open'),
                onPressed: () async {
                  final m = await Navigator.of(context).push<Member>(
                    MaterialPageRoute(
                      builder: (_) => MembersScreen(pendingUid: pendingUid),
                    ),
                  );
                  popped = m;
                  didPop = true;
                },
                child: const Text('buka'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
  }

  /// Biarkan penulisan file (IO sungguhan) selesai lalu bangun ulang layar.
  Future<void> settleIo(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pumpAndSettle();
    }
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  testWidgets('tanpa kartu: tidak ada banner; "Anggota baru" tanpa NFC → '
      'pesan jelas', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Pendaftaran Anggota'), findsOneWidget);
    expect(find.byKey(const Key('pending_banner')), findsNothing);
    // Tes tanpa kanal NFC = perangkat tanpa NFC (dialog tunggu kartu ada di
    // test/qa_fixes/c_home_extras_test.dart).
    await tap(tester, 'new_member_button');
    await settleIo(tester);
    expect(
      find.text(
        'Perangkat ini tidak punya NFC — kartu anggota tidak bisa dibaca',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('new_card_dialog')), findsNothing);
    expect(find.byType(MemberFormScreen), findsNothing);
  });

  testWidgets('kartu baru → daftar → simpan → kembali dengan anggota', (
    tester,
  ) async {
    await pumpScreen(tester, pendingUid: '0e 5e 17 11 05 c6 5d');
    expect(find.byKey(const Key('pending_banner')), findsOneWidget);
    expect(
      find.text('Kartu belum terdaftar · UID 0E 5E 17 11 05 C6 5D'),
      findsOneWidget,
    );

    await tap(tester, 'register_new_button');
    expect(find.byType(MemberFormScreen), findsOneWidget);
    expect(find.text('0E 5E 17 11 05 C6 5D'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('member_name_field')),
      '  Siti   Aminah ',
    );
    // NIK lengkap → L/P & tanggal lahir otomatis, kolom umur diganti info.
    await tester.enterText(
      find.byKey(const Key('member_nik_field')),
      '3201015203580001',
    );
    await tester.pump();
    expect(find.byKey(const Key('member_birth_info')), findsOneWidget);
    expect(find.byKey(const Key('member_age_field')), findsNothing);
    await tester.enterText(find.byKey(const Key('member_height_field')), '152');
    await tester.pump();
    await tap(tester, 'member_save_button');
    await settleIo(tester);

    final m = MemberStore.instance.byUid(_uid);
    expect(m, isNotNull);
    expect(m!.profile.name, 'Siti Aminah');
    expect(m.profile.gender, Gender.female);
    expect(m.profile.birthDate, DateTime(1958, 3, 12));
    expect(m.profile.heightCm, 152);
    expect(didPop, isTrue);
    expect(popped?.uid, _uid);
    expect(find.byType(MembersScreen), findsNothing);
  });

  testWidgets('tautkan ke riwayat → anggota baru dengan kartu ini', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      pendingUid: _uid,
      records: [
        rec(
          'r1',
          DateTime(2026, 9, 1, 8),
          const PersonProfile(
            name: 'Budi Santoso',
            gender: Gender.male,
            age: 70,
            heightCm: 165,
          ),
        ),
      ],
    );
    await tap(tester, 'link_existing_button');
    await tester.enterText(find.byKey(const Key('link_search')), 'budi');
    await tester.pumpAndSettle();
    expect(find.text('Budi Santoso'), findsOneWidget);
    await tap(tester, 'link_history_0');
    await settleIo(tester);

    final m = MemberStore.instance.byUid(_uid)!;
    expect(m.profile.name, 'Budi Santoso');
    expect(m.profile.gender, Gender.male);
    expect(m.profile.heightCm, 165);
    expect(m.profile.age, greaterThanOrEqualTo(70));
    expect(popped?.uid, _uid);
  });

  testWidgets('tautkan ke anggota lain → kartu dipindah (relink)', (
    tester,
  ) async {
    final created = DateTime(2025, 5, 1);
    await pumpScreen(
      tester,
      pendingUid: _uid,
      members: [
        Member(
          uid: 'AABBCCDD',
          profile: const PersonProfile(name: 'Citra Lestari'),
          createdAt: created,
          updatedAt: created,
        ),
      ],
    );
    await tap(tester, 'link_existing_button');
    await tap(tester, 'link_member_0');
    // Konfirmasi kartu lama tidak berlaku lagi.
    expect(find.text('Ganti kartu Citra Lestari?'), findsOneWidget);
    await tester.tap(find.text('Tautkan'));
    await tester.pumpAndSettle();
    await settleIo(tester);

    expect(MemberStore.instance.byUid('AABBCCDD'), isNull);
    final m = MemberStore.instance.byUid(_uid)!;
    expect(m.profile.name, 'Citra Lestari');
    expect(m.createdAt, created);
    expect(popped?.uid, _uid);
  });

  testWidgets('kartu milik anggota lain: tidak ditimpa, pesan jelas', (
    tester,
  ) async {
    final at = DateTime(2025, 5, 1);
    await pumpScreen(
      tester,
      pendingUid: _uid,
      members: [
        Member(
          uid: _uid,
          profile: const PersonProfile(name: 'Citra Lestari'),
          createdAt: at,
          updatedAt: at,
        ),
      ],
    );
    await tap(tester, 'register_new_button');
    await tester.enterText(find.byKey(const Key('member_name_field')), 'Budi');
    await tester.pump();
    await tap(tester, 'member_save_button');
    await settleIo(tester);

    expect(
      find.text('Kartu ini sudah terdaftar untuk Citra Lestari'),
      findsOneWidget,
    );
    // Form tetap terbuka, data pemilik kartu tidak berubah.
    expect(find.byType(MemberFormScreen), findsOneWidget);
    expect(MemberStore.instance.members.single.profile.name, 'Citra Lestari');
    expect(didPop, isFalse);
  });

  testWidgets('NIK sudah terdaftar → tawarkan pindah ke kartu baru', (
    tester,
  ) async {
    final at = DateTime(2025, 5, 1);
    await pumpScreen(
      tester,
      pendingUid: _uid,
      members: [
        Member(
          uid: 'AABB',
          profile: PersonProfile(
            name: 'Siti Aminah',
            gender: Gender.female,
            nik: '3201015203580001',
            birthDate: DateTime(1958, 3, 12),
          ),
          createdAt: at,
          updatedAt: at,
        ),
      ],
    );
    await tap(tester, 'register_new_button');
    await tester.enterText(find.byKey(const Key('member_name_field')), 'Siti');
    await tester.enterText(
      find.byKey(const Key('member_nik_field')),
      '3201015203580001',
    );
    await tester.pump();

    // Batal → tidak ada yang berubah, form tetap terbuka.
    await tap(tester, 'member_save_button');
    expect(find.text('NIK sudah terdaftar'), findsOneWidget);
    expect(
      find.textContaining(
        'NIK ini sudah terdaftar untuk Siti Aminah (kartu AA BB)',
      ),
      findsWidgets,
    );
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(find.byType(MemberFormScreen), findsOneWidget);
    expect(MemberStore.instance.byUid('AABB'), isNotNull);

    // Pindahkan → anggota lama memakai kartu baru, tidak ada anggota kedua.
    await tap(tester, 'member_save_button');
    await tester.tap(find.text('Pindahkan ke kartu ini'));
    await tester.pumpAndSettle();
    await settleIo(tester);
    expect(MemberStore.instance.byUid('AABB'), isNull);
    final m = MemberStore.instance.members.single;
    expect(m.uid, _uid);
    expect(m.profile.name, 'Siti Aminah');
    expect(m.createdAt, at);
    expect(popped?.uid, _uid);
  });

  testWidgets('daftar: NIK disamarkan; cari; ubah & hapus anggota', (
    tester,
  ) async {
    final at = DateTime(2026, 1, 1);
    await pumpScreen(
      tester,
      members: [
        Member(
          uid: '01020304',
          profile: PersonProfile(
            name: 'Siti Aminah',
            gender: Gender.female,
            nik: '3201015203580001',
            birthDate: DateTime(1958, 3, 12),
          ),
          createdAt: at,
          updatedAt: at,
        ),
        Member(
          uid: '0A0B0C0D',
          profile: const PersonProfile(name: 'Budi', age: 70),
          createdAt: at,
          updatedAt: at,
        ),
      ],
    );
    expect(find.textContaining('3201015203580001'), findsNothing);
    expect(find.textContaining('3201********0001'), findsOneWidget);
    expect(find.text('01 02 03 04'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('member_search')), '3201');
    await tester.pumpAndSettle();
    expect(find.text('Siti Aminah'), findsOneWidget);
    expect(find.text('Budi'), findsNothing);
    await tester.enterText(find.byKey(const Key('member_search')), 'bud');
    await tester.pumpAndSettle();
    expect(find.text('Budi'), findsOneWidget);
    expect(find.text('Siti Aminah'), findsNothing);

    await tap(tester, 'member_tile_0A0B0C0D');
    expect(find.text('Ubah data anggota'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('member_name_field')),
      'Budi S',
    );
    await tap(tester, 'member_save_button');
    await settleIo(tester);
    expect(MemberStore.instance.byUid('0A0B0C0D')!.profile.name, 'Budi S');
    // Mengubah anggota tanpa kartu tertunda tidak menutup daftar.
    expect(find.byType(MembersScreen), findsOneWidget);
    expect(didPop, isFalse);

    await tester.enterText(find.byKey(const Key('member_search')), '');
    await tester.pumpAndSettle();
    await tap(tester, 'member_tile_01020304');
    await tap(tester, 'member_delete_button');
    await tester.tap(find.widgetWithText(FilledButton, 'Hapus'));
    await tester.pumpAndSettle();
    await settleIo(tester);
    expect(MemberStore.instance.byUid('01020304'), isNull);
    expect(find.text('Siti Aminah'), findsNothing);
  });

  testWidgets('keyboard layar di tablet: ketik nama lalu Simpan', (
    tester,
  ) async {
    await pumpScreen(tester, pendingUid: _uid, onScreenKeyboard: true);
    await tap(tester, 'register_new_button');
    final kb = find.byKey(const Key('onscreen_keyboard'));
    expect(kb, findsOneWidget);
    // Form kiri, keyboard kanan.
    expect(
      tester.getTopLeft(kb).dx,
      greaterThan(
        tester.getTopRight(find.byKey(const Key('member_name_field'))).dx,
      ),
    );
    for (final k in ['A', 'N', 'I']) {
      await tester.tap(find.byKey(Key('kb_$k')));
      await tester.pump();
    }
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('member_name_field')))
          .controller!
          .text,
      'Ani',
    );
    expect(find.text('Simpan'), findsOneWidget);
    await tester.tap(find.byKey(const Key('kb_submit')));
    await tester.pumpAndSettle();
    await settleIo(tester);
    expect(MemberStore.instance.byUid(_uid)!.profile.name, 'Ani');
    expect(popped?.uid, _uid);
  });
}
