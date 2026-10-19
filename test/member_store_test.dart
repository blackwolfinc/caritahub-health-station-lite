import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/data/member_store.dart';
import 'package:health_station_lite/models/health_record.dart';

const _uid = '0E5E171105C65D';

Member member(String uid, String name, {String? nik, DateTime? created}) {
  final at = created ?? DateTime(2026, 10, 1, 9);
  return Member(
    uid: uid,
    profile: PersonProfile(name: name, nik: nik),
    createdAt: at,
    updatedAt: at,
  );
}

void main() {
  late Directory dir;
  final store = MemberStore.instance;
  File file() => File('${dir.path}/members_v1.json');

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hs_members');
    MemberStore.directoryProvider = () async => dir;
    store.debugReset();
    await store.load();
  });

  tearDown(() async {
    store.debugReset();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('UID kartu', () {
    test('normalizeUid: spasi/titik dua/huruf kecil → hex besar', () {
      expect(normalizeUid('0E 5E 17 11 05 C6 5D'), _uid);
      expect(normalizeUid('0e5e171105c65d'), _uid);
      expect(normalizeUid(' 0e:5e-17:11 05:c6:5d\n'), _uid);
      expect(normalizeUid(''), '');
    });

    test('formatUid: per byte dipisah spasi', () {
      expect(formatUid(_uid), '0E 5E 17 11 05 C6 5D');
      expect(formatUid('0e5e171105c65d'), '0E 5E 17 11 05 C6 5D');
      expect(formatUid('0E5'), '0E 5');
      expect(formatUid(''), '');
    });
  });

  group('Member', () {
    test('toJson → fromJson utuh; data tidak lengkap → null', () {
      final m = Member(
        uid: _uid,
        profile: PersonProfile(
          name: 'Siti Aminah',
          gender: Gender.female,
          age: 67,
          heightCm: 152.5,
          nik: '3201015203580001',
          birthDate: DateTime(1958, 3, 12),
        ),
        createdAt: DateTime(2026, 1, 2, 3, 4),
        updatedAt: DateTime(2026, 5, 6, 7, 8),
      );
      final back = Member.fromJson(
        jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>,
      )!;
      expect(back.uid, _uid);
      expect(back.profile.name, 'Siti Aminah');
      expect(back.profile.gender, Gender.female);
      expect(back.profile.heightCm, 152.5);
      expect(back.profile.nik, '3201015203580001');
      expect(back.profile.birthDate, DateTime(1958, 3, 12));
      expect(back.createdAt, m.createdAt);
      expect(back.updatedAt, m.updatedAt);

      final created = DateTime(2026).toIso8601String();
      expect(Member.fromJson({'uid': _uid, 'createdAt': created}), isNull);
      expect(
        Member.fromJson({
          'uid': ' ',
          'profile': {'name': 'A'},
          'createdAt': created,
        }),
        isNull,
      );
      expect(
        Member.fromJson({
          'uid': _uid,
          'profile': {'name': ''},
          'createdAt': created,
        }),
        isNull,
      );
    });

    test('profileOn: umur dihitung ulang dari tanggal lahir', () {
      final m = Member(
        uid: _uid,
        profile: PersonProfile(
          name: 'Siti',
          age: 60,
          birthDate: DateTime(1958, 3, 12),
        ),
        createdAt: DateTime(2018),
        updatedAt: DateTime(2018),
      );
      expect(m.profileOn(DateTime(2026, 3, 11)).age, 67);
      expect(m.profileOn(DateTime(2026, 3, 12)).age, 68);
      // Tanpa tanggal lahir: umur apa adanya.
      expect(member(_uid, 'Budi').profileOn(DateTime(2030)).age, isNull);
    });
  });

  group('MemberStore', () {
    test('upsert + byUid dengan UID belum baku; ganti bila UID sama', () async {
      await store.upsert(member('0e 5e 17 11 05 c6 5d', 'Siti'));
      expect(store.byUid('0E:5E:17:11:05:C6:5D')!.profile.name, 'Siti');
      expect(store.byUid(_uid)!.uid, _uid);
      expect(store.byUid('AABBCC'), isNull);

      await store.upsert(member(_uid, 'Siti Aminah'));
      expect(store.members, hasLength(1));
      expect(store.byUid(_uid)!.profile.name, 'Siti Aminah');
    });

    test('members urut nama tanpa membedakan huruf besar/kecil', () async {
      await store.upsert(member('03', 'budi'));
      await store.upsert(member('01', 'Citra'));
      await store.upsert(member('02', 'Ani'));
      expect(
        [for (final m in store.members) m.profile.name],
        ['Ani', 'budi', 'Citra'],
      );
    });

    test('byNik mencocokkan NIK baku', () async {
      await store.upsert(member('01', 'Siti', nik: '3201015203580001'));
      expect(store.byNik('3201 0152 0358 0001')!.uid, '01');
      expect(store.byNik('3201015203580002'), isNull);
      expect(store.byNik(''), isNull);
    });

    test(
      'relink: UID lama hilang, UID baru ada, tanggal daftar tetap',
      () async {
        final created = DateTime(2025, 1, 1, 8);
        await store.upsert(member('AA BB', 'Siti', created: created));
        final moved = await store.relink('aabb', '0e 5e 17 11 05 c6 5d');
        expect(moved.uid, _uid);
        expect(moved.createdAt, created);
        expect(moved.updatedAt.isAfter(created), isTrue);
        expect(store.byUid('AABB'), isNull);
        expect(store.byUid(_uid)!.profile.name, 'Siti');
        expect(store.members, hasLength(1));

        // Tersimpan ke file.
        store.debugReset();
        await store.load();
        expect(store.byUid(_uid)!.createdAt, created);
        expect(store.byUid('AABB'), isNull);
      },
    );

    test(
      'relink ke kartu milik orang lain / kartu tak dikenal ditolak',
      () async {
        await store.upsert(member('01', 'Siti'));
        await store.upsert(member('02', 'Budi'));
        await expectLater(
          store.relink('01', '02'),
          throwsA(
            isA<CardInUseException>().having(
              (e) => e.owner.profile.name,
              'owner',
              'Budi',
            ),
          ),
        );
        await expectLater(store.relink('99', '03'), throwsStateError);
        expect(store.byUid('01')!.profile.name, 'Siti');
        expect(store.byUid('02')!.profile.name, 'Budi');
        // Kartu sama → tidak berubah.
        expect((await store.relink('01', '01')).uid, '01');
      },
    );

    test(
      'satu kartu = satu anggota: add menolak UID yang sudah dipakai',
      () async {
        await store.add(member('0e 5e 17 11 05 c6 5d', 'Siti'));
        expect(store.byUid(_uid)!.profile.name, 'Siti');
        final before = await file().readAsString();
        try {
          await store.add(member(_uid, 'Budi', created: DateTime(2026, 10, 5)));
          fail('harus ditolak');
        } on CardInUseException catch (e) {
          expect(e.owner.profile.name, 'Siti');
          expect(e.message, 'Kartu ini sudah terdaftar untuk Siti');
        }
        // Anggota yang sama pun tidak boleh "ditambah" dua kali.
        await expectLater(
          store.add(member(_uid, 'Siti')),
          throwsA(isA<CardInUseException>()),
        );
        expect(store.members.single.profile.name, 'Siti');
        expect(await file().readAsString(), before);
      },
    );

    test(
      'upsert: ubah anggota sendiri boleh, timpa anggota lain ditolak',
      () async {
        final created = DateTime(2025, 1, 1);
        final siti = member(_uid, 'Siti', created: created);
        await store.add(siti);
        // Ubah data anggota yang sama (UID & tanggal daftar sama).
        await store.upsert(
          siti.copyWith(
            profile: const PersonProfile(name: 'Siti Aminah'),
            updatedAt: DateTime(2026, 2, 2),
          ),
        );
        expect(store.byUid(_uid)!.profile.name, 'Siti Aminah');
        // Anggota baru (tanggal daftar lain) dengan kartu yang sama → ditolak.
        await expectLater(
          store.upsert(member(_uid, 'Budi', created: DateTime(2026, 10, 1))),
          throwsA(
            isA<CardInUseException>().having(
              (e) => e.owner.profile.name,
              'owner',
              'Siti Aminah',
            ),
          ),
        );
        expect(store.byUid(_uid)!.profile.name, 'Siti Aminah');
        expect(store.members, hasLength(1));
      },
    );

    test('delete', () async {
      await store.upsert(member('01', 'Siti'));
      await store.upsert(member('02', 'Budi'));
      await store.delete('0 1');
      expect(store.byUid('01'), isNull);
      expect(store.members.single.profile.name, 'Budi');
    });

    test('persistensi: simpan → muat ulang dari file', () async {
      await store.upsert(
        Member(
          uid: _uid,
          profile: PersonProfile(
            name: 'Siti Aminah',
            gender: Gender.female,
            heightCm: 150,
            nik: '3201015203580001',
            birthDate: DateTime(1958, 3, 12),
          ),
          createdAt: DateTime(2026, 10, 1),
          updatedAt: DateTime(2026, 10, 2),
        ),
      );
      expect(await file().exists(), isTrue);
      // Tidak ada file sementara yang tertinggal.
      expect(dir.listSync().where((e) => e.path.endsWith('.tmp')), isEmpty);

      store.debugReset();
      expect(store.members, isEmpty);
      await store.load();
      final m = store.byUid(_uid)!;
      expect(m.profile.name, 'Siti Aminah');
      expect(m.profile.gender, Gender.female);
      expect(m.profile.nik, '3201015203580001');
      expect(m.profile.birthDate, DateTime(1958, 3, 12));
      expect(m.updatedAt, DateTime(2026, 10, 2));
      expect(store.skippedOnLoad, 0);
    });

    test(
      'file berisi data rusak: yang rusak dilewati, salinan disimpan',
      () async {
        final ok = member(_uid, 'Siti').toJson();
        await file().writeAsString(
          jsonEncode([
            ok,
            42,
            'teks',
            {
              'uid': '',
              'profile': {'name': 'Tanpa UID'},
            },
            {'uid': 'AB', 'profile': 'bukan map', 'createdAt': 'x'},
            {
              'uid': 'CD',
              'profile': {'name': 'Budi', 'age': 'enam puluh'},
              'createdAt': DateTime(2026).toIso8601String(),
            },
          ]),
        );
        store.debugReset();
        await store.load();
        expect(store.members.single.uid, _uid);
        expect(store.skippedOnLoad, 5);
        expect(
          dir.listSync().where((e) => e.path.contains('.corrupt-')),
          hasLength(1),
        );
      },
    );

    test(
      'file bukan JSON: tidak crash, daftar kosong, salinan disimpan',
      () async {
        await file().writeAsString('{{ rusak');
        store.debugReset();
        await store.load();
        expect(store.isLoaded, isTrue);
        expect(store.members, isEmpty);
        expect(store.skippedOnLoad, -1);
        expect(
          dir.listSync().where((e) => e.path.contains('.corrupt-')),
          hasLength(1),
        );
        // Masih bisa dipakai setelahnya.
        await store.upsert(member('01', 'Siti'));
        expect(store.byUid('01'), isNotNull);
      },
    );
  });
}
