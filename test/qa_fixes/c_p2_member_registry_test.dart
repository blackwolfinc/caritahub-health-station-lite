// QA persona 2 — registri anggota (MemberStore, MembersScreen,
// MemberFormScreen). Disalin dari tes QA; perilaku yang benar ditegaskan.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/app/motion.dart';
import 'package:health_station_lite/app/theme.dart';
import 'package:health_station_lite/data/app_settings.dart';
import 'package:health_station_lite/data/member_store.dart';
import 'package:health_station_lite/data/record_store.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/screens/members_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _a = '0E5E171105C65D';
const _b = '04A1B2C3D4E5F6';
const _c = '0499887766';
const _nikA = '3201015203580001';
const _nikB = '3201011203580002';

Member mem(String uid, String name, {String? nik, DateTime? at}) {
  final t = at ?? DateTime(2026, 10, 1, 9);
  return Member(
    uid: uid,
    profile: PersonProfile(name: name, nik: nik),
    createdAt: t,
    updatedAt: t,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = MemberStore.instance;

  group('normalizeUid / formatUid', () {
    test('hanya karakter non-hex → kosong', () {
      expect(normalizeUid('—'), '');
      expect(normalizeUid('-- :: --'), '');
      expect(normalizeUid('   \n\t'), '');
      expect(normalizeUid('ZZ-YY'), '');
    });
    test('tab/baris baru/titik dua/strip dibuang, huruf besar', () {
      expect(normalizeUid('\t0e\n5e:17-11 05.c6_5d '), _a);
    });
    test('panjang ganjil dipertahankan; formatUid tidak crash', () {
      expect(normalizeUid('abc'), 'ABC');
      expect(formatUid('abc'), 'AB C');
      expect(formatUid('A'), 'A');
    });
    test('UID beda pemisah = kartu sama (byUid)', () async {
      final dir = await Directory.systemTemp.createTemp('qa_p2_u');
      MemberStore.directoryProvider = () async => dir;
      store.debugReset();
      await store.load();
      await store.add(mem(_a, 'Siti'));
      expect(store.byUid('0e:5e:17:11:05:c6:5d')?.profile.name, 'Siti');
      expect(store.byUid(''), isNull);
      expect(store.byUid('—'), isNull);
      store.debugReset();
      await dir.delete(recursive: true);
    });
  });

  group('MemberStore', () {
    late Directory dir;
    File file() => File('${dir.path}/members_v1.json');
    List<FileSystemEntity> backups() => dir
        .listSync()
        .where((e) => e.path.contains('members_v1.json.corrupt-'))
        .toList();

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('qa_p2');
      MemberStore.directoryProvider = () async => dir;
      store.debugReset();
    });
    tearDown(() async {
      store.debugReset();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test(
      'add: UID sama beda format → CardInUseException, pemilik utuh',
      () async {
        await store.load();
        await store.add(mem(_a, 'Siti'));
        await expectLater(
          store.add(mem('0e 5e 17 11 05 c6 5d', 'Rina')),
          throwsA(isA<CardInUseException>()),
        );
        expect(store.members.single.profile.name, 'Siti');
      },
    );

    test('add bersamaan untuk kartu sama → tepat satu berhasil', () async {
      await store.load();
      final results = await Future.wait([
        store.add(mem(_a, 'Siti')).then((_) => 'ok', onError: (_) => 'err'),
        store.add(mem(_a, 'Rina')).then((_) => 'ok', onError: (_) => 'err'),
      ]);
      expect(results.where((r) => r == 'ok'), hasLength(1));
      expect(store.members, hasLength(1));
      store.debugReset();
      await store.load();
      expect(store.members, hasLength(1));
    });

    test(
      'upsert anggota lain (createdAt beda) ke kartu terpakai → ditolak',
      () async {
        await store.load();
        await store.add(mem(_a, 'Siti'));
        await expectLater(
          store.upsert(mem(_a, 'Penyusup', at: DateTime(2026, 1, 1))),
          throwsA(isA<CardInUseException>()),
        );
        expect(store.byUid(_a)?.profile.name, 'Siti');
      },
    );

    test('relink: kartu lama mati, tanggal daftar tetap, tersimpan', () async {
      await store.load();
      await store.add(mem(_a, 'Siti', nik: _nikA));
      final moved = await store.relink(_a, 'c0 ff ee');
      expect(moved.uid, 'C0FFEE');
      expect(moved.createdAt, DateTime(2026, 10, 1, 9));
      expect(store.byUid(_a), isNull);
      expect(store.byNik(_nikA)?.uid, 'C0FFEE');
      store.debugReset();
      await store.load();
      expect(store.byUid(_a), isNull);
      expect(store.byUid('C0FFEE')?.profile.name, 'Siti');
    });

    test('relink: ke kartu orang lain / ke UID kosong / dari kartu tak dikenal '
        '→ galat, data tidak berubah', () async {
      await store.load();
      await store.add(mem(_a, 'Siti'));
      await store.add(mem(_b, 'Budi'));
      await expectLater(
        store.relink(_a, _b),
        throwsA(isA<CardInUseException>()),
      );
      await expectLater(store.relink(_a, '--'), throwsArgumentError);
      await expectLater(store.relink(_c, 'AA'), throwsStateError);
      await expectLater(store.relink(_a, _a), completion(isA<Member>()));
      expect(store.byUid(_a)?.profile.name, 'Siti');
      expect(store.byUid(_b)?.profile.name, 'Budi');
      expect(store.members, hasLength(2));
    });

    test('delete lalu daftar ulang kartu yang sama → bisa; hapus UID tak '
        'dikenal → tidak apa-apa', () async {
      await store.load();
      await store.add(mem(_a, 'Siti'));
      await store.delete('0e5e171105c65d');
      expect(store.byUid(_a), isNull);
      await store.delete(_c);
      await store.add(mem(_a, 'Rina'));
      store.debugReset();
      await store.load();
      expect(store.byUid(_a)?.profile.name, 'Rina');
    });

    test('JSON terpotong → daftar kosong, salinan file asli utuh, simpan '
        'berikutnya tidak menghapus salinan', () async {
      const broken =
          '[{"uid":"0E5E171105C65D","profile":{"name":"Siti"},'
          '"createdAt":"2026-10-01T09:00:00.000"},{"uid":"04A1';
      await file().writeAsString(broken);
      await store.load();
      expect(store.isLoaded, isTrue);
      expect(store.skippedOnLoad, -1);
      expect(store.members, isEmpty);
      expect(backups(), hasLength(1));
      expect(File(backups().single.path).readAsStringSync(), broken);
      await store.add(mem(_b, 'Budi'));
      expect(backups(), hasLength(1));
      expect(File(backups().single.path).readAsStringSync(), broken);
      expect(jsonDecode(file().readAsStringSync()), hasLength(1));
    });

    test(
      'file kosong (0 byte) / objek bukan daftar → dianggap rusak',
      () async {
        await file().writeAsString('');
        await store.load();
        expect(store.skippedOnLoad, -1);
        store.debugReset();
        await file().writeAsString('{"uid":"AA"}');
        await store.load();
        expect(store.skippedOnLoad, -1);
        expect(store.members, isEmpty);
      },
    );

    test(
      'sebagian data rusak → yang baik tetap dimuat, jumlah rusak benar',
      () async {
        final good = mem(_a, 'Siti').toJson();
        await file().writeAsString(
          jsonEncode([
            good,
            {
              'uid': 12345,
              'profile': {'name': 'X'},
              'createdAt': '2026-10-01',
            },
            'teks',
            null,
            {
              'uid': '',
              'profile': {'name': 'Y'},
              'createdAt': '2026-10-01',
            },
            {'uid': 'AB', 'createdAt': '2026-10-01'},
            {
              'uid': 'AC',
              'profile': {'name': '   '},
              'createdAt': '2026-10-01',
            },
            {
              'uid': 'AD',
              'profile': {'name': 'Z'},
              'createdAt': 'kemarin',
            },
            {
              'uid': 'AE',
              'profile': {'name': 'W', 'age': 'tujuh'},
              'createdAt': '2026-10-01',
            },
          ]),
        );
        await store.load();
        expect(store.members.single.profile.name, 'Siti');
        expect(store.skippedOnLoad, 8);
        expect(backups(), hasLength(1));
      },
    );

    test(
      'gagal menulis (folder hilang) → galat, memori dikembalikan',
      () async {
        await store.load();
        await store.add(mem(_a, 'Siti'));
        await dir.delete(recursive: true);
        await expectLater(store.add(mem(_b, 'Budi')), throwsA(anything));
        expect(store.byUid(_b), isNull);
        expect(store.members, hasLength(1));
        await dir.create();
        // Antrian tidak macet setelah galat.
        await store.add(mem(_c, 'Cici'));
        expect(store.members, hasLength(2));
      },
    );

    test(
      'add sebelum load selesai tidak menimpa file anggota yang ada',
      () async {
        await file().writeAsString(jsonEncode([mem(_a, 'Siti').toJson()]));
        // load() tidak ditunggu (mis. MembersScreen.initState memanggil
        // unawaited(load())) lalu langsung add.
        final loading = store.load();
        await store.add(mem(_b, 'Budi'));
        await loading;
        store.debugReset();
        await store.load();
        expect(
          store.members.map((m) => m.profile.name),
          containsAll(['Siti', 'Budi']),
        );
      },
    );
  });

  group('Layar anggota', () {
    setUpAll(() async {
      Motion.enabled = false;
      await initializeDateFormatting('id_ID');
    });

    Member? popped;

    Future<Directory> pump(
      WidgetTester tester, {
      String? pendingUid,
      List<Member> members = const [],
      String? rawFile,
    }) async {
      popped = null;
      SharedPreferences.setMockInitialValues({
        'settings_onscreen_keyboard': false,
      });
      final recDir = Directory.systemTemp.createTempSync('qa_p2_rec');
      final memDir = Directory.systemTemp.createTempSync('qa_p2_mem');
      addTearDown(() {
        RecordStore.instance.debugReset();
        store.debugReset();
      });
      await tester.runAsync(() async {
        RecordStore.directoryProvider = () async => recDir;
        MemberStore.directoryProvider = () async => memDir;
        RecordStore.instance.debugReset();
        store.debugReset();
        if (rawFile != null) {
          File('${memDir.path}/members_v1.json').writeAsStringSync(rawFile);
        }
        await AppSettings.instance.load();
        await RecordStore.instance.load();
        await store.load();
        for (final m in members) {
          await store.upsert(m);
        }
      });
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                key: const Key('open'),
                onPressed: () async {
                  popped = await Navigator.of(context).push<Member>(
                    MaterialPageRoute(
                      builder: (_) => MembersScreen(pendingUid: pendingUid),
                    ),
                  );
                },
                child: const Text('buka'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      return memDir;
    }

    Future<void> settleIo(WidgetTester tester) async {
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pumpAndSettle();
      }
    }

    Future<void> tapKey(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    testWidgets('file anggota rusak → petugas diberi tahu (bukan daftar '
        'kosong diam-diam)', (tester) async {
      await pump(tester, rawFile: '[{"uid":"0E5E1711');
      expect(store.skippedOnLoad, -1);
      expect(store.hasCorruptData, isTrue);
      expect(find.byKey(const Key('member_corrupt_banner')), findsOneWidget);
      expect(find.textContaining('tidak terbaca'), findsOneWidget);
    });

    testWidgets('sebagian anggota rusak → banner menyebut jumlahnya', (
      tester,
    ) async {
      await pump(
        tester,
        rawFile: jsonEncode([
          mem(_a, 'Siti').toJson(),
          {
            'uid': '',
            'profile': {'name': 'Y'},
          },
        ]),
      );
      expect(store.skippedOnLoad, 1);
      expect(find.textContaining('1 data anggota kartu rusak'), findsOneWidget);
    });

    testWidgets('file anggota baik → tanpa banner', (tester) async {
      await pump(tester, members: [mem(_a, 'Siti')]);
      expect(store.hasCorruptData, isFalse);
      expect(find.byKey(const Key('member_corrupt_banner')), findsNothing);
    });

    testWidgets('anggota baru: NIK milik anggota lain → tawarkan pindah; '
        'jumlah akun tetap', (tester) async {
      await pump(
        tester,
        pendingUid: _c,
        members: [mem(_a, 'Siti Aminah', nik: _nikA)],
      );
      await tapKey(tester, 'register_new_button');
      await tester.enterText(
        find.byKey(const Key('member_name_field')),
        'Siti A',
      );
      await tester.enterText(find.byKey(const Key('member_nik_field')), _nikA);
      await tester.pump();
      await tapKey(tester, 'member_save_button');
      expect(find.text('NIK sudah terdaftar'), findsOneWidget);
      await tester.tap(find.text('Pindahkan ke kartu ini'));
      await settleIo(tester);
      expect(store.members, hasLength(1));
      expect(store.byUid(_c)?.profile.name, 'Siti Aminah');
      expect(popped?.uid, _c);
    });

    testWidgets('ubah anggota: NIK diganti ke NIK anggota lain → ditolak', (
      tester,
    ) async {
      await pump(
        tester,
        members: [
          mem(_a, 'Siti Aminah', nik: _nikA),
          mem(_b, 'Budi', nik: _nikB),
        ],
      );
      await tapKey(tester, 'member_tile_$_b');
      await tester.enterText(find.byKey(const Key('member_nik_field')), _nikA);
      await tester.pump();
      await tapKey(tester, 'member_save_button');
      await settleIo(tester);
      expect(store.byUid(_b)?.profile.nik, _nikB);
      expect(find.textContaining('Siti Aminah'), findsWidgets);
      expect(find.text('Ubah data anggota'), findsOneWidget);
    });

    testWidgets('NIK 16 angka tidak valid → tidak tersimpan', (tester) async {
      await pump(tester, pendingUid: _c);
      await tapKey(tester, 'register_new_button');
      await tester.enterText(find.byKey(const Key('member_name_field')), 'Ani');
      await tester.enterText(
        find.byKey(const Key('member_nik_field')),
        '9901013213580000',
      );
      await tester.pump();
      await tapKey(tester, 'member_save_button');
      await settleIo(tester);
      expect(store.byUid(_c), isNull);
      expect(find.text('Anggota baru'), findsWidgets);
    });

    testWidgets('simpan diketuk dua kali cepat → satu anggota, tanpa pesan '
        '"sudah terdaftar"', (tester) async {
      await pump(tester, pendingUid: _c);
      await tapKey(tester, 'register_new_button');
      await tester.enterText(find.byKey(const Key('member_name_field')), 'Ani');
      await tester.pump();
      final btn = find.byKey(const Key('member_save_button'));
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.tap(btn, warnIfMissed: false);
      await settleIo(tester);
      expect(store.members, hasLength(1));
      expect(find.textContaining('sudah terdaftar'), findsNothing);
      expect(popped?.profile.name, 'Ani');
    });

    testWidgets('hapus anggota → hilang dari daftar & file', (tester) async {
      final dir = await pump(tester, members: [mem(_a, 'Siti Aminah')]);
      await tapKey(tester, 'member_tile_$_a');
      await tapKey(tester, 'member_delete_button');
      await tester.tap(find.text('Hapus'));
      await settleIo(tester);
      expect(store.byUid(_a), isNull);
      expect(find.byKey(const Key('member_tile_$_a')), findsNothing);
      final saved = await tester.runAsync(
        () => File('${dir.path}/members_v1.json').readAsString(),
      );
      expect(jsonDecode(saved!), isEmpty);
    });

    testWidgets('ubah anggota tanpa mengganti NIK sendiri → tersimpan', (
      tester,
    ) async {
      await pump(tester, members: [mem(_a, 'Siti Aminah', nik: _nikA)]);
      await tapKey(tester, 'member_tile_$_a');
      await tester.enterText(
        find.byKey(const Key('member_name_field')),
        'Siti Aminah Binti',
      );
      await tester.pump();
      await tapKey(tester, 'member_save_button');
      await settleIo(tester);
      expect(store.byUid(_a)?.profile.name, 'Siti Aminah Binti');
      expect(store.byUid(_a)?.createdAt, DateTime(2026, 10, 1, 9));
    });
  });
}
