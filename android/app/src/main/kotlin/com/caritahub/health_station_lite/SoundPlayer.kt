package com.caritahub.health_station_lite

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/// Efek suara pendek (res/raw/sfx_*.wav) lewat SoundPool: dimuat sekali,
/// diputar tanpa jeda. Memakai aliran suara sistem (bunyi antarmuka), jadi
/// tetap terdengar walau volume media/musik di perangkat dimatikan.
class SoundPlayer(context: Context, messenger: BinaryMessenger) {
    private val pool = SoundPool.Builder()
        .setMaxStreams(4)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build(),
        )
        .build()

    private val ids = mapOf(
        "tap" to R.raw.sfx_tap,
        "card" to R.raw.sfx_card,
        "done" to R.raw.sfx_done,
        "success" to R.raw.sfx_success,
        "error" to R.raw.sfx_error,
        "tick" to R.raw.sfx_tick,
    ).mapValues { (_, res) -> pool.load(context, res, 1) }

    init {
        MethodChannel(messenger, "caritahub/sound").setMethodCallHandler { call, result ->
            when (call.method) {
                "play" -> {
                    val id = ids[call.argument<String>("name")]
                    val volume = (call.argument<Double>("volume") ?: 1.0).toFloat()
                    if (id != null) pool.play(id, volume, volume, 1, 0, 1f)
                    result.success(id != null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun release() = pool.release()
}
