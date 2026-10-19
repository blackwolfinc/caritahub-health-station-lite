import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:imin_printer/enums.dart';
import 'package:imin_printer/imin_printer.dart';
import 'package:imin_printer/imin_style.dart';

import '../data/app_settings.dart';

class PrintResult {
  final bool ok;
  final String message;

  /// Ada catatan walau berhasil (mis. kertas hampir habis).
  final String? warning;
  const PrintResult(this.ok, this.message, {this.warning});
}

/// Pembungkus printer thermal bawaan iMin (paket resmi `imin_printer`).
/// Mendukung SDK 1.0 (Android ≤ 11) dan SDK 2.0 (Android 13+).
class PrinterService {
  PrinterService._();
  static final PrinterService instance = PrinterService._();

  final IminPrinter _printer = IminPrinter();
  bool _initialized = false;

  static const _timeout = Duration(seconds: 12);

  bool get platformSupported => !kIsWeb && Platform.isAndroid;

  /// Pengganti cetak untuk tes: jalur sukses tidak bisa dijalankan di host.
  @visibleForTesting
  Future<PrintResult> Function(Uint8List png)? debugPrintOverride;

  static String describeStatus(String? code) => switch (code) {
    '0' => 'Printer siap',
    '1' => 'Printer tidak tersambung atau belum menyala',
    '2' => 'Library printer tidak cocok dengan perangkat ini',
    '3' => 'Penutup printer terbuka',
    '4' => 'Pisau pemotong belum kembali ke posisinya',
    '5' => 'Kepala printer terlalu panas',
    '6' => 'Kesalahan penanda kertas (black label)',
    '7' => 'Kertas habis',
    '8' => 'Kertas hampir habis',
    '-1' => 'Printer gagal diinisialisasi',
    null || '' => 'Status printer tidak terbaca. Coba lagi.',
    _ => 'Printer bermasalah (kode $code)',
  };

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await _printer.initPrinter().timeout(_timeout);
    _initialized = true;
  }

  /// Langsung ke method channel: `IminPrinter.getPrinterStatus()` melempar
  /// StateError bila kode status tidak ada di enum paketnya (terjadi di
  /// beberapa versi SDK 2.0).
  static const MethodChannel _channel = MethodChannel('imin_printer');

  Future<String?> _statusCode() async {
    final code = await _channel
        .invokeMethod<String>('getPrinterStatus')
        .timeout(_timeout);
    return code?.trim();
  }

  /// Lebar kertas dari printer iMin, null bila tidak terbaca.
  Future<PaperWidth?> detectPaper() async {
    if (!platformSupported) return null;
    try {
      await _ensureInit();
      final type = await _channel
          .invokeMethod<Object?>('getPrinterPaperType')
          .timeout(_timeout);
      debugPrint('[Printer] paperType=$type');
      return paperFromIminType(type);
    } catch (e) {
      debugPrint('[Printer] deteksi kertas gagal: $e');
      return null;
    }
  }

  /// Cek status tanpa mencetak.
  Future<PrintResult> check() async {
    if (!platformSupported) {
      return const PrintResult(
        false,
        'Printer iMin hanya tersedia di perangkat iMin (Android).',
      );
    }
    try {
      await _ensureInit();
      final code = await _statusCode();
      return PrintResult(code == '0' || code == '8', describeStatus(code));
    } on MissingPluginException {
      return const PrintResult(false, 'Printer iMin tidak terdeteksi.');
    } catch (e) {
      _initialized = false;
      return PrintResult(false, 'Printer tidak merespons ($e)');
    }
  }

  /// Cetak gambar struk (PNG hitam-putih selebar area cetak).
  Future<PrintResult> printReceipt(Uint8List png) async {
    final override = debugPrintOverride;
    if (override != null) return override(png);
    if (!platformSupported) {
      return const PrintResult(
        false,
        'Printer iMin hanya tersedia di perangkat iMin (Android).',
      );
    }
    try {
      await _ensureInit();
      final code = await _statusCode();
      if (code != '0' && code != '8') {
        return PrintResult(false, describeStatus(code));
      }
      await _printer
          .printSingleBitmap(
            png,
            pictureStyle: IminPictureStyle(alignment: IminPrintAlign.center),
          )
          .timeout(_timeout);
      // Cukup untuk melewati pisau pemotong; lebih dari ini membuang kertas.
      await _printer.printAndFeedPaper(80).timeout(_timeout);
      // Hanya model desktop yang punya pemotong; di model lain ini diabaikan.
      try {
        await _printer.partialCut().timeout(const Duration(seconds: 3));
      } catch (_) {}
      return PrintResult(
        true,
        'Catatan tes kesehatan dicetak',
        warning: code == '8' ? 'Kertas hampir habis' : null,
      );
    } on MissingPluginException {
      return const PrintResult(false, 'Printer iMin tidak terdeteksi.');
    } on TimeoutException {
      _initialized = false;
      return const PrintResult(false, 'Printer tidak merespons. Coba lagi.');
    } catch (e) {
      _initialized = false;
      return PrintResult(false, 'Gagal mencetak: $e');
    }
  }
}

/// Terjemahkan jawaban `getPrinterPaperType` iMin (lebar dalam mm, mis.
/// 80 di Falcon2) ke lebar kertas.
@visibleForTesting
PaperWidth? paperFromIminType(Object? type) => switch (int.tryParse('$type')) {
  80 => PaperWidth.mm80,
  58 => PaperWidth.mm58,
  _ => null,
};
