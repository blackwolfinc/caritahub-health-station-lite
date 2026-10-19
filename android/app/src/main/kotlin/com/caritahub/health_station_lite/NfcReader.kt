package com.caritahub.health_station_lite

import android.app.Activity
import android.nfc.NdefMessage
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.tech.IsoDep
import android.nfc.tech.MifareClassic
import android.nfc.tech.MifareUltralight
import android.nfc.tech.Ndef
import android.nfc.tech.NfcA
import android.nfc.tech.NfcB
import android.nfc.tech.NfcF
import android.nfc.tech.NfcV
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Pembaca NFC untuk analisa kartu: UID, teknologi, parameter ISO 14443 A/B,
 * isi NDEF, dan respons APDU baca-saja (SELECT MF). Tidak menulis ke kartu.
 */
class NfcReader(private val activity: Activity, messenger: BinaryMessenger) {
    private val adapter: NfcAdapter? = NfcAdapter.getDefaultAdapter(activity)
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null

    init {
        MethodChannel(messenger, "caritahub/nfc").setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(
                    mapOf(
                        "available" to (adapter != null),
                        "enabled" to (adapter?.isEnabled == true),
                        // Model perangkat: posisi antena NFC di layar (Falcon2: dalam layar).
                        "model" to android.os.Build.MODEL,
                    )
                )
                "start" -> result.success(start())
                "stop" -> { stop(); result.success(true) }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "caritahub/nfc/tags").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
            override fun onCancel(arguments: Any?) { sink = null }
        })
    }

    private fun start(): Boolean {
        val a = adapter ?: return false
        if (!a.isEnabled) return false
        val flags = NfcAdapter.FLAG_READER_NFC_A or NfcAdapter.FLAG_READER_NFC_B or
            NfcAdapter.FLAG_READER_NFC_F or NfcAdapter.FLAG_READER_NFC_V or
            NfcAdapter.FLAG_READER_NO_PLATFORM_SOUNDS
        a.enableReaderMode(activity, { tag -> onTag(tag) }, flags, null)
        return true
    }

    fun stop() {
        try { adapter?.disableReaderMode(activity) } catch (_: Exception) {}
    }

    private fun hex(b: ByteArray?): String? =
        b?.joinToString(" ") { String.format("%02X", it) }

    private fun onTag(tag: Tag) {
        val info = mutableMapOf<String, Any?>(
            "uid" to hex(tag.id),
            "techs" to tag.techList.map { it.substringAfterLast('.') },
            "time" to System.currentTimeMillis(),
        )
        NfcA.get(tag)?.let {
            info["nfcA"] = mapOf("atqa" to hex(it.atqa), "sak" to String.format("0x%02X", it.sak.toInt()),
                "maxTransceive" to it.maxTransceiveLength)
        }
        NfcB.get(tag)?.let {
            info["nfcB"] = mapOf("applicationData" to hex(it.applicationData),
                "protocolInfo" to hex(it.protocolInfo), "maxTransceive" to it.maxTransceiveLength)
        }
        NfcF.get(tag)?.let {
            info["nfcF"] = mapOf("manufacturer" to hex(it.manufacturer), "systemCode" to hex(it.systemCode))
        }
        NfcV.get(tag)?.let {
            info["nfcV"] = mapOf("dsfId" to it.dsfId.toInt(), "responseFlags" to it.responseFlags.toInt())
        }
        MifareClassic.get(tag)?.let {
            info["mifareClassic"] = mapOf("type" to it.type, "size" to it.size,
                "sectors" to it.sectorCount, "blocks" to it.blockCount)
        }
        MifareUltralight.get(tag)?.let {
            info["mifareUltralight"] = mapOf("type" to it.type)
        }
        IsoDep.get(tag)?.let { iso ->
            val m = mutableMapOf<String, Any?>(
                "historicalBytes" to hex(iso.historicalBytes),
                "hiLayerResponse" to hex(iso.hiLayerResponse),
                "extendedLength" to iso.isExtendedLengthApduSupported,
                "maxTransceive" to iso.maxTransceiveLength,
            )
            // Hanya perintah baca: SELECT Master File (3F00). Tidak menulis.
            try {
                iso.connect()
                iso.timeout = 1500
                val resp = iso.transceive(byteArrayOf(0x00, 0xA4.toByte(), 0x00, 0x00, 0x02, 0x3F, 0x00))
                m["selectMf"] = hex(resp)
            } catch (e: Exception) {
                m["selectMfError"] = e.javaClass.simpleName + ": " + (e.message ?: "")
            } finally {
                try { iso.close() } catch (_: Exception) {}
            }
            info["isoDep"] = m
        }
        Ndef.get(tag)?.let { ndef ->
            val m = mutableMapOf<String, Any?>(
                "type" to ndef.type, "maxSize" to ndef.maxSize, "writable" to ndef.isWritable,
            )
            try {
                ndef.connect()
                val msg: NdefMessage? = ndef.ndefMessage
                m["records"] = msg?.records?.map { r ->
                    mapOf("tnf" to r.tnf.toInt(), "type" to String(r.type),
                        "payloadHex" to hex(r.payload),
                        "payloadText" to String(r.payload, Charsets.UTF_8))
                } ?: emptyList<Any>()
            } catch (e: Exception) {
                m["error"] = e.javaClass.simpleName + ": " + (e.message ?: "")
            } finally {
                try { ndef.close() } catch (_: Exception) {}
            }
            info["ndef"] = m
        }
        main.post { sink?.success(info) }
    }
}
