import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/health_record.dart';
import '../utils/nik.dart';

/// Semua hasil pengukuran, disimpan sebagai satu file JSON di penyimpanan
/// internal aplikasi. Tidak ada yang dikirim ke server.
class RecordStore extends ChangeNotifier {
  RecordStore._();
  static final RecordStore instance = RecordStore._();

  static const _fileName = 'health_records_v1.json';

  List<HealthRecord> _records = [];
  bool _loaded = false;
  File? _file;

  /// Terbaru di atas.
  List<HealthRecord> get records => List.unmodifiable(_records);
  bool get isLoaded => _loaded;

  /// Direktori penyimpanan — bisa diganti di test.
  @visibleForTesting
  static Future<Directory> Function() directoryProvider =
      getApplicationDocumentsDirectory;

  Future<File> _resolveFile() async {
    if (_file != null) return _file!;
    final dir = await directoryProvider();
    _file = File('${dir.path}/$_fileName');
    return _file!;
  }

  /// Jumlah catatan rusak yang dilewati saat memuat (salinan file disimpan).
  /// -1 = file tidak terbaca, atau masih ada salinan rusak dari sesi
  /// sebelumnya yang belum ditangani petugas (file utama mungkin sudah
  /// ditimpa simpanan baru — riwayat lama hanya ada di salinan).
  int _skippedOnLoad = 0;
  int get skippedOnLoad => _skippedOnLoad;

  /// File utama gagal dibaca pada pemuatan ini.
  bool _loadFailed = false;

  /// Salinan `.corrupt-*` yang belum ditandai "sudah ditangani".
  int _pendingBackups = 0;
  int get pendingCorruptBackups => _pendingBackups;

  /// Salinan file rusak belum berhasil dibuat → file utama jangan ditimpa.
  bool _needsBackup = false;

  /// Teks peringatan untuk banner (null = tidak ada masalah).
  String? get corruptWarning {
    if (_skippedOnLoad == 0) return null;
    if (_loadFailed) {
      return 'File riwayat tidak terbaca. Salinan file asli disimpan; '
          'hubungi tim IT sebelum menghapus aplikasi.';
    }
    if (_skippedOnLoad > 0) {
      return '$_skippedOnLoad data riwayat rusak dan dilewati. Salinan file '
          'asli disimpan di perangkat.';
    }
    return 'Ada salinan file riwayat rusak yang belum ditangani. Riwayat '
        'lama mungkin tidak tampil; hubungi tim IT sebelum menghapus '
        'aplikasi.';
  }

  Future<void> load() async {
    if (_loaded) return;
    var bad = 0;
    var failed = false;
    try {
      final file = await _resolveFile();
      if (await file.exists()) {
        final raw = await file.readAsString();
        final list = jsonDecode(raw) as List;
        final ok = <HealthRecord>[];
        // Satu catatan rusak tidak boleh menyembunyikan seluruh riwayat.
        for (final m in list) {
          try {
            final r = m is Map
                ? HealthRecord.fromJson(m.cast<String, dynamic>())
                : null;
            if (r == null) {
              bad++;
            } else {
              ok.add(r);
            }
          } catch (_) {
            bad++;
          }
        }
        _records = ok..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }
    } catch (e) {
      // File rusak total tidak boleh menghapus data: simpan salinannya dulu.
      debugPrint('[RecordStore] load failed: $e');
      failed = true;
    }
    if (failed || bad > 0) await _tryBackup();
    _pendingBackups = (await _pendingBackupFiles()).length;
    _loadFailed = failed;
    _skippedOnLoad = failed
        ? -1
        : bad > 0
        ? bad
        : (_pendingBackups > 0 ? -1 : 0);
    _loaded = true;
    notifyListeners();
  }

  Future<void> _tryBackup() async {
    try {
      await _backup(await _resolveFile());
      _needsBackup = false;
    } catch (e) {
      debugPrint('[RecordStore] backup failed: $e');
      _needsBackup = true;
    }
  }

  Future<void> _backup(File file) async {
    if (await file.exists()) {
      await file.copy(
        '${file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}',
      );
    }
  }

  /// Salinan rusak yang belum ditangani: `<file>.corrupt-<waktu>`. Yang
  /// sudah ditangani diberi akhiran `.dismissed` (isinya tetap disimpan).
  Future<List<File>> _pendingBackupFiles() async {
    try {
      final file = await _resolveFile();
      final name = RegExp('^${RegExp.escape(_fileName)}\\.corrupt-\\d+\$');
      return [
        await for (final e in file.parent.list())
          if (e is File && name.hasMatch(e.uri.pathSegments.last)) e,
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Petugas menyatakan salinan rusak sudah ditangani (mis. sudah diambil
  /// tim IT). Salinan TIDAK dihapus — hanya ditandai, peringatan hilang.
  Future<void> dismissCorruptWarning() async {
    for (final f in await _pendingBackupFiles()) {
      await f.rename('${f.path}.dismissed');
    }
    _pendingBackups = 0;
    _loadFailed = false;
    _skippedOnLoad = 0;
    notifyListeners();
  }

  // ── Hitungan per orang ──

  /// Kunci orang: NIK bila ada, selain itu nama (dinormalkan) + jenis
  /// kelamin + umur — ukur ulang orang yang sama tidak dihitung dua kali.
  static String personKey(PersonProfile p) {
    final nik = p.nik == null ? '' : Nik.normalize(p.nik!);
    if (nik.isNotEmpty) return 'nik:$nik';
    final name = p.name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return 'nama:$name|${p.gender?.name ?? '-'}|${p.age ?? '-'}';
  }

  /// Jumlah orang berbeda di [records].
  static int countPeople(Iterable<HealthRecord> records) =>
      {for (final r in records) personKey(r.profile)}.length;

  /// Hasil pada tanggal kalender [day] (jam lokal), terbaru di atas.
  List<HealthRecord> recordsOn(DateTime day) => [
    for (final r in _records)
      if (r.createdAt.year == day.year &&
          r.createdAt.month == day.month &&
          r.createdAt.day == day.day)
        r,
  ];

  HealthRecord? byId(String id) {
    for (final r in _records) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Semua perubahan diproses berurutan (antrean), masing-masing dibangun
  /// dari daftar TERBARU — simpan lansia berikutnya bersamaan dengan antrean
  /// cetak yang menaikkan jumlah cetak tidak saling menimpa.
  Future<void> _queue = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task());
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Selesai setelah semua perubahan yang sudah diantrekan tersimpan ke file.
  Future<void> flush() => _serial(() async {});

  /// Ubah daftar lalu simpan; bila penyimpanan gagal, daftar di memori
  /// dikembalikan supaya tidak berbeda dengan isi file (dan tidak ada
  /// duplikat saat petugas mencoba lagi).
  Future<void> _mutate(
    List<HealthRecord> Function(List<HealthRecord> current) change,
  ) => _serial(() async {
    final previous = _records;
    final next = change(previous);
    _records = next;
    try {
      await _persist(next);
    } catch (e) {
      _records = previous;
      rethrow;
    }
    notifyListeners();
  });

  /// Tambah hasil baru. Id yang sudah ada ditolak (tidak menimpa diam-diam).
  Future<void> add(HealthRecord record) => _mutate((cur) {
    if (cur.any((r) => r.id == record.id)) {
      throw StateError('Id ${record.id} sudah dipakai');
    }
    // Tetap urut terbaru dulu, juga bila jam perangkat sempat mundur.
    final i = cur.indexWhere((r) => !r.createdAt.isAfter(record.createdAt));
    return [...cur]..insert(i < 0 ? cur.length : i, record);
  });

  Future<void> update(HealthRecord record) =>
      _mutate((cur) => [for (final r in cur) r.id == record.id ? record : r]);

  /// Ubah satu hasil dari versi TERBARU-nya (bukan salinan lama di layar).
  Future<void> modify(
    String id,
    HealthRecord Function(HealthRecord latest) change,
  ) => _mutate((cur) => [for (final r in cur) r.id == id ? change(r) : r]);

  /// Tandai hasil sudah diekspor ke file SATUSEHAT (satu kali tulis).
  Future<void> markSatusehatExported(Set<String> ids, DateTime at) => _mutate(
    (cur) => [
      for (final r in cur)
        ids.contains(r.id) ? r.copyWith(satusehatExportedAt: at) : r,
    ],
  );

  Future<void> delete(String id) =>
      _mutate((cur) => cur.where((r) => r.id != id).toList());

  /// Tulis ke file sementara lalu rename — file lama tidak pernah setengah
  /// tertulis kalau daya mati di tengah proses.
  Future<void> _persist(List<HealthRecord> records) async {
    // File rusak belum tersalin → coba lagi; gagal = jangan timpa aslinya.
    if (_needsBackup) {
      await _tryBackup();
      if (_needsBackup) {
        throw const FileSystemException(
          'Salinan file riwayat rusak gagal dibuat; simpan dibatalkan',
        );
      }
    }
    final file = await _resolveFile();
    final tmp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    final data = jsonEncode([for (final r in records) r.toJson()]);
    try {
      await tmp.writeAsString(data, flush: true);
      await tmp.rename(file.path);
    } catch (e) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      rethrow;
    }
  }

  /// Untuk test: kosongkan memori & muat ulang dari file.
  @visibleForTesting
  void debugReset() {
    _queue = Future<void>.value();
    _records = [];
    _loaded = false;
    _file = null;
    _skippedOnLoad = 0;
    _loadFailed = false;
    _pendingBackups = 0;
    _needsBackup = false;
  }
}
