// QA persona 9 (perbaikan D) — penyimpanan riwayat & pengaturan.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/data/app_settings.dart';
import 'package:health_station_lite/data/record_store.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';
import 'package:shared_preferences/shared_preferences.dart';

HealthRecord rec(String id, DateTime at, {String name = 'Siti'}) =>
    HealthRecord(
      id: id,
      createdAt: at,
      startedAt: at.subtract(const Duration(seconds: 200)),
      profile: PersonProfile(name: name, gender: Gender.female, age: 68),
      measurements: const AllMeasurements(
        tensimeter: TensimeterData(systolic: 130, diastolic: 85, pulse: 72),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  final store = RecordStore.instance;
  File file() => File('${dir.path}/health_records_v1.json');
  List<File> backups() => dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.contains('.corrupt-'))
      .toList();

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('qa_p9');
    RecordStore.directoryProvider = () async => dir;
    store.debugReset();
  });

  tearDown(() async {
    store.debugReset();
    try {
      await Process.run('chmod', ['-R', 'u+w', dir.path]);
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  group('RecordStore.load', () {
    test('file belum ada → kosong, tanpa peringatan, tanpa salinan', () async {
      await store.load();
      expect(store.records, isEmpty);
      expect(store.skippedOnLoad, 0);
      expect(backups(), isEmpty);
    });

    test(
      'file rusak total (teks acak) → -1 + salinan berisi aslinya',
      () async {
        file().writeAsStringSync('{{{ bukan json');
        await store.load();
        expect(store.records, isEmpty);
        expect(store.skippedOnLoad, -1);
        expect(backups(), hasLength(1));
        expect(backups().first.readAsStringSync(), '{{{ bukan json');
        expect(store.isLoaded, isTrue);
      },
    );

    test(
      'JSON valid tapi bukan list → dianggap rusak, salinan dibuat',
      () async {
        file().writeAsStringSync('{"id":"x"}');
        await store.load();
        expect(store.skippedOnLoad, -1);
        expect(backups(), hasLength(1));
      },
    );

    test('file kosong (0 byte) → dianggap rusak, salinan dibuat', () async {
      file().writeAsStringSync('');
      await store.load();
      expect(store.skippedOnLoad, -1);
      expect(backups(), hasLength(1));
    });

    test(
      'sebagian rusak → yang valid tetap dimuat, jumlah dilewati benar',
      () async {
        final good = rec('A', DateTime(2026, 10, 1, 9)).toJson();
        file().writeAsStringSync(
          jsonEncode([
            good,
            42,
            'teks',
            {'id': null, 'createdAt': '2026-10-01T09:00:00'},
            {'id': 'B', 'createdAt': 'bukan tanggal'},
            {'id': 'C', 'createdAt': '2026-10-01T09:00:00', 'profile': 'str'},
            {
              'id': 'D',
              'createdAt': '2026-10-01T10:00:00',
              'measurements': {'tensimeter': 'abc'},
            },
          ]),
        );
        await store.load();
        expect(store.records.map((r) => r.id), ['A']);
        expect(store.skippedOnLoad, 6);
        expect(backups(), hasLength(1));
      },
    );

    test('urutan di file acak → dimuat terbaru dulu', () async {
      file().writeAsStringSync(
        jsonEncode([
          rec('old', DateTime(2026, 1, 1)).toJson(),
          rec('new', DateTime(2026, 10, 1)).toJson(),
          rec('mid', DateTime(2026, 5, 1)).toJson(),
        ]),
      );
      await store.load();
      expect(store.records.map((r) => r.id), ['new', 'mid', 'old']);
    });

    test('toJson → fromJson utuh (printCount, startedAt, ekspor)', () async {
      await store.load();
      final r = rec('A', DateTime(2026, 10, 1, 9)).copyWith(
        printCount: 3,
        lastPrintedAt: DateTime(2026, 10, 1, 9, 5),
        satusehatExportedAt: DateTime(2026, 10, 2),
      );
      await store.add(r);
      store.debugReset();
      await store.load();
      final back = store.byId('A')!;
      expect(back.printCount, 3);
      expect(back.lastPrintedAt, DateTime(2026, 10, 1, 9, 5));
      expect(back.satusehatExportedAt, DateTime(2026, 10, 2));
      expect(back.durationSeconds, 200);
      expect(back.measurements.tensimeter.systolic, 130);
    });
  });

  group('RecordStore tulis', () {
    test('id ganda ditolak, daftar tidak berubah', () async {
      await store.load();
      await store.add(rec('A', DateTime(2026, 10, 1)));
      await expectLater(
        store.add(rec('A', DateTime(2026, 10, 2))),
        throwsStateError,
      );
      expect(store.records, hasLength(1));
    });

    test('jam mundur → tetap urut terbaru dulu', () async {
      await store.load();
      await store.add(rec('B', DateTime(2026, 10, 2)));
      await store.add(rec('A', DateTime(2026, 10, 1)));
      await store.add(rec('C', DateTime(2026, 10, 3)));
      expect(store.records.map((r) => r.id), ['C', 'B', 'A']);
    });

    test('20 simpan bersamaan → semua tersimpan di file', () async {
      await store.load();
      await Future.wait([
        for (var i = 0; i < 20; i++)
          store.add(
            rec('R$i', DateTime(2026, 10, 1, 8).add(Duration(minutes: i))),
          ),
      ]);
      store.debugReset();
      await store.load();
      expect(store.records, hasLength(20));
    });

    test('tidak ada sisa file .tmp setelah simpan', () async {
      await store.load();
      for (var i = 0; i < 5; i++) {
        await store.add(rec('R$i', DateTime(2026, 10, 1, 8, i)));
      }
      final tmp = dir.listSync().where((f) => f.path.endsWith('.tmp'));
      expect(tmp, isEmpty);
    });

    test(
      'gagal tulis (folder read-only) → error & memori dikembalikan',
      () async {
        await store.load();
        await store.add(rec('A', DateTime(2026, 10, 1)));
        await Process.run('chmod', ['555', dir.path]);
        await expectLater(
          store.add(rec('B', DateTime(2026, 10, 2))),
          throwsA(anything),
        );
        expect(store.records.map((r) => r.id), ['A']);
        await Process.run('chmod', ['755', dir.path]);
        // Coba lagi berhasil, tanpa duplikat.
        await store.add(rec('B', DateTime(2026, 10, 2)));
        expect(store.records.map((r) => r.id), ['B', 'A']);
      },
    );

    test('hapus & modify bekerja dan tersimpan', () async {
      await store.load();
      await store.add(rec('A', DateTime(2026, 10, 1)));
      await store.add(rec('B', DateTime(2026, 10, 2)));
      await store.modify('A', (r) => r.copyWith(printCount: r.printCount + 1));
      await store.delete('B');
      store.debugReset();
      await store.load();
      expect(store.records.map((r) => r.id), ['A']);
      expect(store.byId('A')!.printCount, 1);
    });

    test(
      'P9-2: file rusak total → 1 simpan baru → buka ulang: peringatan tetap '
      'ada karena riwayat lama hanya ada di salinan .corrupt',
      () async {
        file().writeAsStringSync(
          '[{"id":"A","createdAt":"2026-10-01T09:00:00"',
        ); // terpotong
        await store.load();
        expect(store.skippedOnLoad, -1);
        await store.add(rec('NEW', DateTime(2026, 10, 19, 9)));
        // Aplikasi dibuka ulang.
        store.debugReset();
        await store.load();
        expect(backups(), isNotEmpty, reason: 'salinan tetap ada');
        // Harapan: petugas tetap diberi tahu ada riwayat lama yang belum
        // dipulihkan (banner di beranda), karena file utama sudah ditimpa.
        expect(
          store.skippedOnLoad,
          isNot(0),
          reason:
              'Banner "File riwayat tidak terbaca" hilang setelah restart; '
              'riwayat lama diam-diam tidak tampil lagi',
        );
      },
    );
  });

  group('P9-2 peringatan salinan rusak bertahan sampai ditangani', () {
    test('file rusak total → teks "tidak terbaca"; setelah restart teks '
        '"belum ditangani"', () async {
      file().writeAsStringSync('{{{');
      await store.load();
      expect(store.corruptWarning, contains('tidak terbaca'));
      await store.add(rec('NEW', DateTime(2026, 10, 19, 9)));
      store.debugReset();
      await store.load();
      expect(store.records.map((r) => r.id), ['NEW']);
      expect(store.pendingCorruptBackups, 1);
      expect(store.corruptWarning, contains('belum ditangani'));
    });

    test('sebagian rusak → simpan → restart: peringatan tetap', () async {
      file().writeAsStringSync(
        jsonEncode([rec('A', DateTime(2026, 10, 1, 9)).toJson(), 42]),
      );
      await store.load();
      expect(store.skippedOnLoad, 1);
      expect(store.corruptWarning, contains('1 data riwayat rusak'));
      await store.add(rec('B', DateTime(2026, 10, 2)));
      store.debugReset();
      await store.load();
      expect(store.records, hasLength(2));
      expect(store.skippedOnLoad, isNot(0));
    });

    test('ditandai ditangani → peringatan hilang, salinan TIDAK dihapus, '
        'restart tetap bersih', () async {
      file().writeAsStringSync('garbage');
      await store.load();
      await store.dismissCorruptWarning();
      expect(store.skippedOnLoad, 0);
      expect(store.corruptWarning, isNull);
      expect(backups(), hasLength(1));
      expect(backups().first.readAsStringSync(), 'garbage');
      await store.add(rec('NEW', DateTime(2026, 10, 19, 9)));
      store.debugReset();
      await store.load();
      expect(store.skippedOnLoad, 0);
      expect(store.corruptWarning, isNull);
    });

    test('salinan lama (versi sebelumnya) tanpa file utama rusak → tetap '
        'diperingatkan', () async {
      File('${file().path}.corrupt-1700000000000').writeAsStringSync('x');
      file().writeAsStringSync(
        jsonEncode([rec('A', DateTime(2026, 10, 1)).toJson()]),
      );
      await store.load();
      expect(store.records, hasLength(1));
      expect(store.skippedOnLoad, -1);
      expect(store.pendingCorruptBackups, 1);
    });

    test('file bersih tanpa salinan → tidak ada peringatan', () async {
      file().writeAsStringSync(
        jsonEncode([rec('A', DateTime(2026, 10, 1)).toJson()]),
      );
      await store.load();
      expect(store.skippedOnLoad, 0);
      expect(store.corruptWarning, isNull);
    });

    test(
      'salinan gagal dibuat → simpan ditolak, file rusak asli utuh',
      () async {
        file().writeAsStringSync('rusak-asli');
        // Folder read-only: salinan tidak bisa dibuat.
        await Process.run('chmod', ['555', dir.path]);
        await store.load();
        expect(store.skippedOnLoad, -1);
        await expectLater(
          store.add(rec('NEW', DateTime(2026, 10, 19))),
          throwsA(isA<FileSystemException>()),
        );
        await Process.run('chmod', ['755', dir.path]);
        expect(file().readAsStringSync(), 'rusak-asli');
        // Folder pulih → salinan dibuat dulu, baru simpan.
        await store.add(rec('NEW', DateTime(2026, 10, 19)));
        expect(backups(), hasLength(1));
        expect(backups().first.readAsStringSync(), 'rusak-asli');
      },
    );
  });

  group('P9-5 hitungan per orang', () {
    PersonProfile p(String name, {String? nik, Gender? g, int? age}) =>
        PersonProfile(name: name, nik: nik, gender: g, age: age);
    HealthRecord r(String id, PersonProfile prof) => HealthRecord(
      id: id,
      createdAt: DateTime(2026, 10, 19, 9),
      profile: prof,
      measurements: const AllMeasurements(),
    );

    test('NIK sama = satu orang walau nama beda ejaan', () {
      expect(
        RecordStore.countPeople([
          r('1', p('Siti', nik: '3201015203580001')),
          r('2', p('Siti A.', nik: '3201 0152 0358 0001')),
        ]),
        1,
      );
    });

    test('tanpa NIK: nama dinormalkan + jenis kelamin + umur', () {
      expect(
        RecordStore.countPeople([
          r('1', p('Siti  Aminah', g: Gender.female, age: 68)),
          r('2', p(' siti aminah', g: Gender.female, age: 68)),
          r('3', p('Siti Aminah', g: Gender.female, age: 72)), // orang lain
          r('4', p('Budi', g: Gender.male, age: 70)),
        ]),
        3,
      );
    });

    test('recordsOn hanya tanggal kalender yang sama', () async {
      await store.load();
      await store.add(rec('A', DateTime(2026, 10, 19, 0, 1)));
      await store.add(rec('B', DateTime(2026, 10, 18, 23, 59)));
      expect(store.recordsOn(DateTime(2026, 10, 19, 15)).map((r) => r.id), [
        'A',
      ]);
    });
  });

  group('AppSettings', () {
    test('default saat kosong', () async {
      SharedPreferences.setMockInitialValues({});
      await AppSettings.instance.load();
      final s = AppSettings.instance;
      expect(s.paper, PaperWidth.mm58);
      expect(s.paperChosen, isFalse);
      expect(s.autoPrint, isTrue);
      expect(s.autoFinish, isTrue);
      expect(s.onScreenKeyboard, isNull);
      expect(s.kioskMode, isFalse);
      expect(s.locationName, '');
    });

    test('simpan → muat ulang: nilai sama; ID SATUSEHAT dibersihkan', () async {
      SharedPreferences.setMockInitialValues({});
      final s = AppSettings.instance;
      await s.load();
      await s.setPaper(PaperWidth.mm80);
      await s.setLocationName('  Posyandu Melati  ');
      await s.setAutoPrint(false);
      await s.setSatusehat(
        orgId: ' Organization/1000 0004 ',
        locationId: 'Location/ef01-1065',
        practitionerId: 'Practitioner/N10000001',
        practitionerName: '  dr.   Ani ',
      );
      await s.load();
      expect(s.paper, PaperWidth.mm80);
      expect(s.paperChosen, isTrue);
      expect(s.locationName, 'Posyandu Melati');
      expect(s.autoPrint, isFalse);
      expect(s.ssOrgId, '10000004');
      expect(s.ssLocationId, 'ef01-1065');
      expect(s.ssPractitionerId, 'N10000001');
      expect(s.ssPractitionerName, 'dr. Ani');
    });

    test('P9-3: satu nilai bertipe salah tidak membuat pengaturan lain kembali '
        'ke default', () async {
      SharedPreferences.setMockInitialValues({
        'settings_paper_mm': '80', // tipe salah (String)
        'settings_location_name': 'Posyandu Mawar',
        'settings_auto_finish': false,
        'settings_ss_org_id': '20000009',
      });
      await AppSettings.instance.load();
      final s = AppSettings.instance;
      expect(s.locationName, 'Posyandu Mawar');
      expect(s.autoFinish, isFalse);
      expect(s.ssOrgId, '20000009');
    });
    test('P9-3: bool/String tertukar → hanya kunci itu default', () async {
      SharedPreferences.setMockInitialValues({
        'settings_paper_mm': 80,
        'settings_location_name': 123, // salah
        'settings_auto_print': 'false', // salah
        'settings_auto_finish': false,
        'settings_kiosk_mode': true,
        'settings_ss_practitioner_name': 'Ns. Dewi',
      });
      await AppSettings.instance.load();
      final s = AppSettings.instance;
      expect(s.paper, PaperWidth.mm80);
      expect(s.locationName, '');
      expect(s.autoPrint, isTrue);
      expect(s.autoFinish, isFalse);
      expect(s.kioskMode, isTrue);
      expect(s.ssPractitionerName, 'Ns. Dewi');
    });

    test(
      'P9-3: lebar kertas tersimpan sebagai teks "80" tetap dikenali',
      () async {
        SharedPreferences.setMockInitialValues({'settings_paper_mm': '80'});
        await AppSettings.instance.load();
        expect(AppSettings.instance.paper, PaperWidth.mm80);
        expect(AppSettings.instance.paperChosen, isTrue);
      },
    );
  });
}
