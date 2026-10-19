import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import '../data/app_settings.dart';

/// Mode kiosk: aplikasi dipin (Android Lock Task / "sematkan aplikasi"),
/// layar penuh tanpa bilah status & navigasi, dan layar tetap menyala.
/// Keluar hanya lewat tombol kiosk di beranda (atau tahan Kembali + Ringkasan
/// bila sistem meminta).
class Kiosk {
  Kiosk._();

  static const _channel = MethodChannel('caritahub/kiosk');

  static Future<void> apply(bool on) async {
    await SystemChrome.setEnabledSystemUIMode(
      on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    try {
      await _channel.invokeMethod<bool>(on ? 'start' : 'stop');
    } on MissingPluginException {
      // Bukan Android (test/desktop) — cukup layar penuh.
    } catch (e) {
      debugPrint('[Kiosk] ${on ? 'start' : 'stop'} gagal: $e');
    }
  }

  /// Nyalakan/matikan dan simpan pilihan (dipulihkan saat aplikasi dibuka).
  static Future<void> setEnabled(bool on) async {
    await AppSettings.instance.setKioskMode(on);
    await apply(on);
  }

  /// Dipanggil saat aplikasi mulai: pulihkan mode kiosk yang tersimpan, dan
  /// pasang lagi bila pin terlepas (mis. lewat gestur sistem) saat aplikasi
  /// kembali aktif.
  static Future<void> restore() async {
    WidgetsBinding.instance.addObserver(_KioskObserver());
    if (AppSettings.instance.kioskMode) await apply(true);
  }
}

class _KioskObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && AppSettings.instance.kioskMode) {
      Kiosk.apply(true);
    }
  }
}
