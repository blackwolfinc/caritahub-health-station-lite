import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/health_record.dart';
import '../utils/nik.dart';

/// UID kartu NFC dalam bentuk baku: heksadesimal huruf besar tanpa pemisah.
/// "0E 5E 17 11 05 C6 5D" / "0e:5e:17:11:05:c6:5d" → "0E5E171105C65D".
String normalizeUid(String raw) =>
    raw.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();

/// Untuk tampilan: per byte dipisah spasi.
/// "0E5E171105C65D" → "0E 5E 17 11 05 C6 5D".
String formatUid(String uid) {
  final v = normalizeUid(uid);
  final parts = <String>[
    for (var i = 0; i < v.length; i += 2)
      v.substring(i, i + 2 > v.length ? v.length : i + 2),
  ];
  return parts.join(' ');
}

/// Anggota terdaftar: satu kartu NFC ↔ satu identitas lansia.
@immutable
class Member {
  /// Kunci utama, sudah dinormalisasi ([normalizeUid]).
  final String uid;
  final PersonProfile profile;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Member({
    required this.uid,
    required this.profile,
    required this.createdAt,
    required this.updatedAt,
  });

  Member copyWith({String? uid, PersonProfile? profile, DateTime? updatedAt}) =>
      Member(
        uid: uid == null ? this.uid : normalizeUid(uid),
        profile: profile ?? this.profile,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'profile': profile.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  /// null bila datanya tidak lengkap (UID/nama kosong, tanggal rusak).
  static Member? fromJson(Map<String, dynamic> j) {
    final uid = normalizeUid((j['uid'] as String?) ?? '');
    final created = DateTime.tryParse((j['createdAt'] as String?) ?? '');
    final profileJson = j['profile'];
    if (uid.isEmpty || created == null || profileJson is! Map) return null;
    final profile = PersonProfile.fromJson(profileJson.cast<String, dynamic>());
    if (profile.name.trim().isEmpty) return null;
    return Member(
      uid: uid,
      profile: profile,
      createdAt: created,
      updatedAt:
          DateTime.tryParse((j['updatedAt'] as String?) ?? '') ?? created,
    );
  }

  /// Identitas untuk pemeriksaan hari ini: umur dihitung ulang dari tanggal
  /// lahir (NIK) bila diketahui.
  PersonProfile profileOn(DateTime now) {
    final p = profile;
    if (p.birthDate == null) return p;
    return PersonProfile(
      name: p.name,
      gender: p.gender,
      age: Nik.ageOn(p.birthDate!, now),
      heightCm: p.heightCm,
      nik: p.nik,
      birthDate: p.birthDate,
    );
  }
}

/// Kartu sudah terdaftar untuk anggota lain (satu kartu = satu anggota).
class CardInUseException implements Exception {
  /// Pemilik kartu saat ini.
  final Member owner;
  const CardInUseException(this.owner);

  /// Pesan siap tampil untuk petugas.
  String get message => 'Kartu ini sudah terdaftar untuk ${owner.profile.name}';

  @override
  String toString() => 'CardInUseException: $message (${owner.uid})';
}

/// Daftar anggota kartu NFC, disimpan sebagai satu file JSON di penyimpanan
/// internal aplikasi (sama seperti riwayat). Tidak ada yang dikirim ke server.
class MemberStore extends ChangeNotifier {
  MemberStore._();
  static final MemberStore instance = MemberStore._();

  static const _fileName = 'members_v1.json';

  /// Kunci: UID baku.
  Map<String, Member> _members = {};
  bool _loaded = false;
  File? _file;

  bool get isLoaded => _loaded;

  /// Urut nama (tanpa membedakan huruf besar/kecil).
  List<Member> get members => List.unmodifiable(
    _members.values.toList()..sort(
      (a, b) =>
          a.profile.name.toLowerCase().compareTo(b.profile.name.toLowerCase()),
    ),
  );

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

  /// Jumlah data anggota rusak yang dilewati saat memuat (-1 = file rusak).
  int _skippedOnLoad = 0;
  int get skippedOnLoad => _skippedOnLoad;

  /// Ada data anggota yang rusak / file tak terbaca → kartu bisa tampil
  /// "belum terdaftar"; petugas perlu diberi tahu.
  bool get hasCorruptData => _skippedOnLoad != 0;

  /// Pemuatan yang sedang berjalan (dipakai bersama, tidak membaca dua kali).
  Future<void>? _loading;

  Future<void> load() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final file = await _resolveFile();
      if (await file.exists()) {
        final list = jsonDecode(await file.readAsString()) as List;
        final ok = <String, Member>{};
        var bad = 0;
        // Satu data rusak tidak boleh menyembunyikan anggota lain.
        for (final m in list) {
          try {
            final member = m is Map
                ? Member.fromJson(m.cast<String, dynamic>())
                : null;
            if (member == null) {
              bad++;
            } else {
              ok[member.uid] = member;
            }
          } catch (_) {
            bad++;
          }
        }
        if (bad > 0) {
          _skippedOnLoad = bad;
          await _backup(file);
        }
        _members = ok;
      }
    } catch (e) {
      // File rusak total: simpan salinannya dulu, mulai dengan daftar kosong.
      debugPrint('[MemberStore] load failed: $e');
      _skippedOnLoad = -1;
      try {
        await _backup(await _resolveFile());
      } catch (_) {}
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _backup(File file) async {
    if (await file.exists()) {
      await file.copy(
        '${file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}',
      );
    }
  }

  /// UID boleh belum baku ("0e 5e …").
  Member? byUid(String uid) => _members[normalizeUid(uid)];

  Member? byNik(String nik) {
    final v = Nik.normalize(nik);
    if (v.isEmpty) return null;
    for (final m in _members.values) {
      final n = m.profile.nik;
      if (n != null && Nik.normalize(n) == v) return m;
    }
    return null;
  }

  /// Perubahan diproses berurutan supaya tidak saling menimpa.
  Future<void> _queue = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task());
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Ubah daftar lalu simpan; bila gagal, memori dikembalikan seperti semula.
  Future<T> _mutate<T>(
    (Map<String, Member>, T) Function(Map<String, Member> current) change,
  ) => _serial(() async {
    // Perubahan sebelum file dimuat akan menimpa anggota yang tersimpan.
    if (!_loaded) await load();
    final previous = _members;
    final (next, result) = change(Map.of(previous));
    _members = next;
    try {
      await _persist(next.values);
    } catch (e) {
      _members = previous;
      rethrow;
    }
    notifyListeners();
    return result;
  });

  /// Anggota baru. Satu kartu = satu anggota: UID yang sudah dipakai
  /// ditolak dengan [CardInUseException].
  Future<void> add(Member m) => _mutate((cur) {
    final member = m.copyWith(uid: m.uid);
    final owner = cur[member.uid];
    if (owner != null) throw CardInUseException(owner);
    cur[member.uid] = member;
    return (cur, null);
  });

  /// Simpan perubahan data anggota (UID sama), atau tambah bila UID belum
  /// terdaftar. Kartu milik anggota LAIN tidak pernah ditimpa: anggota yang
  /// sama dikenali dari [Member.createdAt] (tidak berubah sejak didaftarkan),
  /// selain itu [CardInUseException].
  Future<void> upsert(Member m) => _mutate((cur) {
    final member = m.copyWith(uid: m.uid);
    final owner = cur[member.uid];
    if (owner != null && owner.createdAt != member.createdAt) {
      throw CardInUseException(owner);
    }
    cur[member.uid] = member;
    return (cur, null);
  });

  /// Pindahkan anggota ke kartu baru (kartu hilang/diganti). Tanggal daftar
  /// tetap; kartu lama tidak berlaku lagi. Kartu baru milik anggota lain →
  /// [CardInUseException].
  Future<Member> relink(String oldUid, String newUid) => _mutate((cur) {
    final from = normalizeUid(oldUid);
    final to = normalizeUid(newUid);
    final member = cur[from];
    if (member == null) throw StateError('Kartu $from tidak terdaftar');
    if (to.isEmpty) throw ArgumentError.value(newUid, 'newUid', 'UID kosong');
    if (from == to) return (cur, member);
    final owner = cur[to];
    if (owner != null) throw CardInUseException(owner);
    final moved = member.copyWith(uid: to, updatedAt: DateTime.now());
    cur
      ..remove(from)
      ..[to] = moved;
    return (cur, moved);
  });

  Future<void> delete(String uid) => _mutate((cur) {
    cur.remove(normalizeUid(uid));
    return (cur, null);
  });

  /// Tulis ke file sementara lalu rename — file lama tidak pernah setengah
  /// tertulis kalau daya mati di tengah proses.
  Future<void> _persist(Iterable<Member> members) async {
    final file = await _resolveFile();
    final tmp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    final data = jsonEncode([for (final m in members) m.toJson()]);
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
    _members = {};
    _loaded = false;
    _loading = null;
    _file = null;
    _skippedOnLoad = 0;
  }
}
