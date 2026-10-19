package com.caritahub.health_station_lite

import android.app.ActivityManager
import android.content.Context
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var nfc: NfcReader? = null
    private var sound: SoundPlayer? = null

    override fun onPause() {
        // Mode pembaca NFC hanya boleh aktif saat aplikasi di depan.
        nfc?.stop()
        super.onPause()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        nfc = NfcReader(this, flutterEngine.dartExecutor.binaryMessenger)
        sound = SoundPlayer(this, flutterEngine.dartExecutor.binaryMessenger)
        // Mode kiosk: aplikasi dipin (Lock Task / "sematkan aplikasi") supaya
        // lansia/pengunjung tidak bisa keluar ke layar lain, layar tetap menyala.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "caritahub/kiosk")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "start" -> {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            startLockTask()
                            result.success(true)
                        }
                        "stop" -> {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            if (isLocked()) stopLockTask()
                            result.success(true)
                        }
                        "isActive" -> result.success(isLocked())
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("kiosk", e.message, null)
                }
            }
    }

    override fun onDestroy() {
        sound?.release()
        super.onDestroy()
    }

    private fun isLocked(): Boolean {
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return am.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
    }
}
