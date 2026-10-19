import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Hasil satu kali tempel kartu: data mentah dari Android (lihat NfcReader.kt).
class NfcScan {
  final Map<String, Object?> data;
  const NfcScan(this.data);

  String get uid => (data['uid'] as String?) ?? '—';
  List<String> get techs => [
    for (final t in (data['techs'] as List? ?? const [])) '$t',
  ];

  /// UID acak: nomor kartu berubah setiap ditempel — tidak bisa dipakai
  /// sebagai kartu anggota.
  /// - NFC-A 4 byte berawalan 08h (ISO/IEC 14443-3 "random ID"): kartu
  ///   bank/e-money.
  /// - NFC-B (PUPI): e-KTP terbukti berganti PUPI setiap dibaca di Falcon2
  ///   (19 Okt 2026: 6 bacaan, 6 UID berbeda; CPLC tidak bisa dibaca).
  bool get randomUid {
    final hex = uid.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
    if (techs.contains('NfcA')) return hex.length == 8 && hex.startsWith('08');
    return techs.contains('NfcB');
  }

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(
    (data['time'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
  );
}

/// Status NFC perangkat. [model] = Build.MODEL (mis. "I24T02" = iMin Falcon2).
typedef NfcStatus = ({bool available, bool enabled, String model});

/// iMin Falcon2: antena NFC ada DI DALAM LAYAR, area seukuran kartu di
/// tengah-kiri (±35 % dari kiri, tengah vertikal; foto produk iMin).
bool hasInScreenNfc(String model) => model.toUpperCase().startsWith('I24T');

/// Pembungkus kanal NFC native (Android reader mode). Hanya membaca.
///
/// Dipakai bersama (beranda & halaman Pembaca NFC): mode pembaca menyala
/// selama masih ada pemakai ([start]/[stop] berpasangan), dan dinyalakan
/// lagi saat aplikasi kembali ke depan (Android mematikannya saat onPause).
class NfcReader {
  NfcReader._();

  static const _methods = MethodChannel('caritahub/nfc');
  static const _events = EventChannel('caritahub/nfc/tags');

  static int _users = 0;
  static _Resumer? _resumer;

  static Future<NfcStatus> status() async {
    try {
      final m = await _methods.invokeMapMethod<String, Object?>('status');
      return (
        available: m?['available'] == true,
        enabled: m?['enabled'] == true,
        model: (m?['model'] as String?) ?? '',
      );
    } on MissingPluginException {
      return (available: false, enabled: false, model: '');
    }
  }

  static Future<bool> _nativeStart() async {
    try {
      return await _methods.invokeMethod<bool>('start') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Tambah satu pemakai; false bila NFC tidak ada / mati.
  static Future<bool> start() async {
    _users++;
    _resumer ??= _Resumer()..attach();
    return _nativeStart();
  }

  /// Lepas satu pemakai; mode pembaca mati bila tidak ada lagi.
  static Future<void> stop() async {
    if (_users > 0) _users--;
    if (_users > 0) return;
    try {
      await _methods.invokeMethod<void>('stop');
    } on MissingPluginException {
      // bukan Android
    }
  }

  /// Kartu yang sama dalam jendela ini dianggap satu kali tempel (kartu yang
  /// diletakkan di pembaca bisa terbaca berkali-kali per detik).
  static const sameCardWindow = Duration(seconds: 4);
  static String? _lastUid;
  static DateTime? _lastAt;

  /// Pendengar [scans] (beranda, dialog kartu baru, Pembaca NFC, …).
  static final _sinks = <MultiStreamController<NfcScan>>[];
  static StreamSubscription<dynamic>? _upstream;

  /// Tempelan yang sedang dibagikan & berapa pendengar mengabaikannya.
  static NfcScan? _current;
  static int _ignored = 0;

  /// Satu aliran bersama untuk semua pendengar, tanpa bacaan berulang.
  /// Saringan kartu sama dijalankan SEKALI per bacaan (bukan per pendengar),
  /// lalu bacaan dibagikan serentak ke semua pendengar.
  static final Stream<NfcScan> scans = Stream.multi((c) {
    _sinks.add(c);
    c.onCancel = () {
      _sinks.remove(c);
      if (_sinks.isEmpty) {
        final up = _upstream;
        _upstream = null;
        return up?.cancel();
      }
    };
    _upstream ??= _events.receiveBroadcastStream().listen(
      _dispatch,
      onError: (Object e, StackTrace st) {
        for (final s in List.of(_sinks)) {
          s.addErrorSync(e, st);
        }
      },
    );
  });

  static void _dispatch(dynamic event) {
    final NfcScan scan;
    final String uid;
    try {
      scan = NfcScan(Map<String, Object?>.from(event as Map));
      uid = scan.uid;
    } catch (e, st) {
      // Event rusak: teruskan sebagai galat, jangan sampai crash.
      for (final s in List.of(_sinks)) {
        s.addErrorSync(e, st);
      }
      return;
    }
    final prevUid = _lastUid, prevAt = _lastAt;
    if (!isNewTap(uid, DateTime.now())) return;
    final targets = List.of(_sinks);
    _current = scan;
    _ignored = 0;
    try {
      for (final s in targets) {
        s.addSync(scan);
      }
    } finally {
      _current = null;
    }
    // Tidak ada yang memproses (mis. beranda tertutup layar lain): tempelan
    // ini tidak dihitung, jadi tempel ulang segera tetap diterima.
    if (targets.isNotEmpty && _ignored >= targets.length) {
      _lastUid = prevUid;
      _lastAt = prevAt;
    }
  }

  /// Dipanggil pendengar yang TIDAK memproses [scan] (layar tidak di depan,
  /// sedang sibuk). Bila semua pendengar mengabaikannya, jendela kartu sama
  /// tidak dipakai.
  static void ignore(NfcScan scan) {
    if (identical(scan, _current)) _ignored++;
  }

  /// true bila [uid] bukan bacaan ulang kartu yang sama dalam
  /// [sameCardWindow]. Jendela bergeser: kartu yang terus diletakkan tetap
  /// diabaikan sampai diangkat lebih dari [sameCardWindow].
  @visibleForTesting
  static bool isNewTap(String uid, DateTime now) {
    final repeat =
        uid == _lastUid &&
        _lastAt != null &&
        now.difference(_lastAt!) < sameCardWindow;
    _lastUid = uid;
    _lastAt = now;
    return !repeat;
  }
}

class _Resumer with WidgetsBindingObserver {
  void attach() => WidgetsBinding.instance.addObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && NfcReader._users > 0) {
      NfcReader._nativeStart();
    }
  }
}
