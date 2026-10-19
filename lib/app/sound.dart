import 'dart:async';

import 'package:flutter/services.dart';

import '../data/app_settings.dart';

/// Efek suara aplikasi (lihat SoundPlayer.kt). Nada lembut & pendek supaya
/// lansia tahu ada yang terjadi tanpa kaget.
enum Sfx {
  /// Ketuk tombol keyboard layar.
  tap,

  /// Kartu NFC terbaca.
  card,

  /// Satu alat selesai mengukur / catatan tercetak.
  done,

  /// Hasil pemeriksaan tersimpan.
  success,

  /// Ada masalah (kartu ditolak, gagal cetak, isian salah).
  error,

  /// Detak hitung mundur.
  tick,
}

class Sound {
  Sound._();

  static const _channel = MethodChannel('caritahub/sound');

  /// Volume relatif per efek (ketuk & detak lebih pelan).
  static const _volume = {Sfx.tap: 0.35, Sfx.tick: 0.5};

  static void play(Sfx s) {
    final settings = AppSettings.instance;
    if (!settings.sound) return;
    if (s == Sfx.tap && !settings.keySound) return;
    unawaited(
      _channel
          .invokeMethod<bool>('play', {
            'name': s.name,
            'volume': _volume[s] ?? 1.0,
          })
          // Tanpa plugin (tes/desktop) atau gagal: diam saja.
          .catchError((_) => false),
    );
  }
}
