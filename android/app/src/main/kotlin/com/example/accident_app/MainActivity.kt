package com.example.accident_app

import android.Manifest
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.RingtoneManager
import android.media.Ringtone
import android.net.Uri
import android.os.*
import android.util.Log
import android.util.Base64
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import android.telephony.SmsManager
import java.nio.ByteBuffer
import java.util.UUID

class MainActivity : FlutterActivity() {

    private val tag = "BleSOSEngine"
    private val methodChannel  = "com.example.accident_app/ble_sos"
    private val eventChannel   = "com.example.accident_app/ble_sos_events"
    private val smsChannel     = "com.example.accident_app/sms"
    private val sosAlertChannel = "com.example.accident_app/sos_alert"

    // BLE SOS service UUID — matches iOS and Dart side
    private val sosServiceUuid = UUID.fromString("0000FFF0-0000-1000-8000-00805F9B34FB")

    private var advertiser: BluetoothLeAdvertiser? = null
    private var scanner: BluetoothLeScanner? = null
    private var scanCallback: ScanCallback? = null
    private var advertiseCallback: AdvertiseCallback? = null
    private var eventSink: EventChannel.EventSink? = null
    private var meshAdvertiserCallback: AdvertiseCallback? = null

    // SOS Alert state
    private var vibratorRunning = false
    private var sosRingtone: Ringtone? = null
    private var savedVolume: Int = -1
    private val vibrateHandler = Handler(Looper.getMainLooper())
    private var vibrateRunnable: Runnable? = null

    // Dedup: device → last-seen time
    private val seenDevices = mutableMapOf<String, Long>()
    private val dedupWindowMs = 60_000L

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── EventChannel: push SOS discoveries to Dart ──────────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannel)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                }
                override fun onCancel(args: Any?) {
                    eventSink = null
                }
            })

        // ── MethodChannel: called from Dart ─────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startAdvertising" -> {
                        val lat = call.argument<Double>("lat")
                        val lng = call.argument<Double>("lng")
                        val userId = call.argument<String>("userId") ?: "unknown"
                        startAdvertising(lat, lng, userId, result)
                    }
                    "stopAdvertising" -> {
                        stopAdvertising()
                        result.success(null)
                    }
                    "startScanning" -> {
                        startScanning(result)
                    }
                    "stopScanning" -> {
                        stopScanning()
                        result.success(null)
                    }
                    "isSupported" -> {
                        result.success(isBleSupportedAndEnabled())
                    }
                    "startMeshScanning" -> startMeshScanning(result)
                    "stopMeshScanning" -> {
                        stopMeshScanning()
                        result.success(null)
                    }
                    "stopMeshAdvertising" -> {
                        stopAdvertising()
                        result.success(null)
                    }
                    "broadcastMeshPayload" -> {
                        val fragments = call.argument<List<String>>("fragments") ?: emptyList()
                        val intervalMs = call.argument<Int>("intervalMs") ?: 140
                        val repeatCount = call.argument<Int>("repeatCount") ?: 2
                        broadcastMeshPayload(fragments, intervalMs, repeatCount, result)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── SMS MethodChannel (avoid legacy broadcast receivers) ─────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, smsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sendSms" -> {
                        val to = call.argument<String>("to") ?: ""
                        val message = call.argument<String>("message") ?: ""
                        sendSms(to, message, result)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── SOS Alert MethodChannel (max volume + vibration + DnD override) ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, sosAlertChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startSosAlert" -> {
                        startSosAlert()
                        result.success(null)
                    }
                    "stopSosAlert" -> {
                        stopSosAlert()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun sendSms(to: String, message: String, result: MethodChannel.Result) {
        if (to.isBlank()) {
            result.error("INVALID", "Recipient number is empty", null); return
        }
        if (message.isBlank()) {
            result.error("INVALID", "Message is empty", null); return
        }
        if (!hasPermission(Manifest.permission.SEND_SMS)) {
            result.error("PERMISSION", "SEND_SMS permission not granted", null); return
        }
        try {
            val sms = SmsManager.getDefault()
            val parts = sms.divideMessage(message)
            sms.sendMultipartTextMessage(to, null, parts, null, null)
            result.success(true)
        } catch (e: Exception) {
            result.error("FAILED", e.message, null)
        }
    }

    // ── SOS Alert: max volume + continuous vibration + DnD override ──────────

    @Suppress("DEPRECATION")
    private fun startSosAlert() {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        // Override DnD / silent — best-effort (requires MODIFY_AUDIO_SETTINGS)
        try {
            audio.ringerMode = AudioManager.RINGER_MODE_NORMAL
        } catch (_: Exception) {}

        // Force max ring volume
        val stream = AudioManager.STREAM_RING
        savedVolume = audio.getStreamVolume(stream)
        val maxVol  = audio.getStreamMaxVolume(stream)
        try {
            audio.setStreamVolume(stream, maxVol, AudioManager.FLAG_SHOW_UI)
        } catch (_: Exception) {}

        // Play alarm ringtone
        try {
            val alarmUri: Uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            sosRingtone = RingtoneManager.getRingtone(this, alarmUri)
            sosRingtone?.audioAttributes = android.media.AudioAttributes.Builder()
                .setUsage(android.media.AudioAttributes.USAGE_ALARM)
                .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            sosRingtone?.isLooping = true
            sosRingtone?.play()
        } catch (e: Exception) {
            Log.e(tag, "SOS ringtone error: ${e.message}")
        }

        // Continuous vibration pattern
        startContinuousVibration()
        Log.d(tag, "SOS alert started")
    }

    @Suppress("DEPRECATION")
    private fun stopSosAlert() {
        // Stop ringtone
        try {
            sosRingtone?.stop()
            sosRingtone = null
        } catch (_: Exception) {}

        // Restore volume
        if (savedVolume >= 0) {
            try {
                val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                audio.setStreamVolume(AudioManager.STREAM_RING, savedVolume, 0)
            } catch (_: Exception) {}
            savedVolume = -1
        }

        // Stop vibration
        stopContinuousVibration()
        Log.d(tag, "SOS alert stopped")
    }

    @Suppress("DEPRECATION")
    private fun startContinuousVibration() {
        if (vibratorRunning) return
        vibratorRunning = true
        val pattern  = longArrayOf(0, 600, 200) // on 600ms, off 200ms
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val mgr = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            mgr.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(
                VibrationEffect.createWaveform(pattern, 0 /* repeat */)
            )
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(pattern, 0)
        }
    }

    @Suppress("DEPRECATION")
    private fun stopContinuousVibration() {
        vibratorRunning = false
        vibrateRunnable?.let { vibrateHandler.removeCallbacks(it) }
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val mgr = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                mgr.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            vibrator.cancel()
        } catch (_: Exception) {}
    }

    // ── Advertise SOS payload ────────────────────────────────────────────────

    private fun startAdvertising(lat: Double?, lng: Double?, userId: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (!hasPermission(Manifest.permission.BLUETOOTH_ADVERTISE)) {
                result.error("PERMISSION", "BLUETOOTH_ADVERTISE permission not granted", null)
                return
            }
            // Accessing adapter / advertiser can require CONNECT on Android 12+
            if (!hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
                result.error("PERMISSION", "BLUETOOTH_CONNECT permission not granted", null)
                return
            }
        }
        val adapter = getBluetoothAdapter() ?: run {
            result.error("BT_UNAVAILABLE", "Bluetooth adapter unavailable", null)
            return
        }
        if (!adapter.isEnabled) {
            result.error("BT_DISABLED", "Bluetooth is disabled", null)
            return
        }
        advertiser = adapter.bluetoothLeAdvertiser
        if (advertiser == null) {
            result.error("LE_UNSUPPORTED", "BLE advertising not supported on this device", null)
            return
        }

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .setConnectable(false)
            .setTimeout(0) // indefinite
            .build()

        val payload = buildPayload(lat, lng, userId)
        val data = AdvertiseData.Builder()
            .addServiceUuid(ParcelUuid(sosServiceUuid))
            // Service data is more interoperable than manufacturer data across devices.
            .addServiceData(ParcelUuid(sosServiceUuid), payload)
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
            .build()

        advertiseCallback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
                Log.d(tag, "BLE advertising started")
                result.success("started")
            }
            override fun onStartFailure(errorCode: Int) {
                Log.e(tag, "BLE advertising failed: $errorCode")
                result.error("ADVERTISE_FAIL", "Failed to start advertising: $errorCode", null)
            }
        }

        try {
            advertiser?.startAdvertising(settings, data, advertiseCallback)
        } catch (e: Exception) {
            result.error("EXCEPTION", e.message, null)
        }
    }

    private fun stopAdvertising() {
        try {
            advertiser?.stopAdvertising(advertiseCallback)
        } catch (_: Exception) {}
        advertiser = null
        advertiseCallback = null
        Log.d(tag, "BLE advertising stopped")
    }

    // ── Scan for nearby SOS beacons ─────────────────────────────────────────

    private fun startScanning(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (!hasPermission(Manifest.permission.BLUETOOTH_SCAN)) {
                result.error("PERMISSION", "BLUETOOTH_SCAN permission not granted", null)
                return
            }
            if (!hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
                result.error("PERMISSION", "BLUETOOTH_CONNECT permission not granted", null)
                return
            }
        }
        val adapter = getBluetoothAdapter() ?: run {
            result.error("BT_UNAVAILABLE", "Bluetooth adapter unavailable", null)
            return
        }
        if (!adapter.isEnabled) {
            result.error("BT_DISABLED", "Bluetooth is disabled", null)
            return
        }
        scanner = adapter.bluetoothLeScanner
        if (scanner == null) {
            result.error("LE_UNSUPPORTED", "BLE scanning not supported", null)
            return
        }

        val filter = ScanFilter.Builder()
            .setServiceUuid(ParcelUuid(sosServiceUuid))
            .build()

        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_POWER)
            .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
            .setMatchMode(ScanSettings.MATCH_MODE_AGGRESSIVE)
            .build()

        scanCallback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, sr: ScanResult) {
                processScanResult(sr)
            }
            override fun onScanFailed(errorCode: Int) {
                Log.e(tag, "BLE scan failed: $errorCode")
            }
        }

        try {
            scanner?.startScan(listOf(filter), settings, scanCallback)
            result.success("scanning")
            Log.d(tag, "BLE scanning started")
        } catch (e: Exception) {
            result.error("EXCEPTION", e.message, null)
        }
    }

    private fun stopScanning() {
        try {
            scanner?.stopScan(scanCallback)
        } catch (_: Exception) {}
        scanner = null
        scanCallback = null
        Log.d(tag, "BLE scanning stopped")
    }

    private fun processScanResult(sr: ScanResult) {
        val payload = sr.scanRecord
            ?.serviceData
            ?.get(ParcelUuid(sosServiceUuid))
            ?: return
        runOnUiThread {
            eventSink?.success(
                mapOf("rawPayload" to Base64.encodeToString(payload, Base64.NO_WRAP))
            )
        }
        if (payload.size < 18) return

        // Byte layout: [0..7]=userId hash, [8]=flags, [9..12]=lat float, [13..16]=lng float
        val flags = payload[8].toInt() and 0xFF
        val isSos = (flags and 0x01) != 0
        if (!isSos) return

        val deviceId = sr.device.address ?: return
        val now = System.currentTimeMillis()
        if ((seenDevices[deviceId] ?: 0) + dedupWindowMs > now) return
        seenDevices[deviceId] = now

        val lat = ByteBuffer.wrap(payload, 9, 4).float.toDouble()
        val lng = ByteBuffer.wrap(payload, 13, 4).float.toDouble()

        val event = mapOf(
            "deviceId" to deviceId,
            "lat"      to if (lat.isNaN()) null else lat,
            "lng"      to if (lng.isNaN()) null else lng,
            "rssi"     to sr.rssi,
        )
        runOnUiThread { eventSink?.success(event) }
        Log.d(tag, "SOS received from $deviceId @ $lat,$lng")
    }

    private fun startMeshScanning(result: MethodChannel.Result) {
        startScanning(result)
    }

    private fun stopMeshScanning() {
        stopScanning()
    }

    private fun broadcastMeshPayload(
        fragments: List<String>,
        intervalMs: Int,
        repeatCount: Int,
        result: MethodChannel.Result
    ) {
        val adapter = getBluetoothAdapter() ?: run {
            result.error("BT_UNAVAILABLE", "Bluetooth adapter unavailable", null)
            return
        }
        if (!adapter.isEnabled) {
            result.error("BT_DISABLED", "Bluetooth is disabled", null)
            return
        }
        val advertiserLocal = adapter.bluetoothLeAdvertiser ?: run {
            result.error("LE_UNSUPPORTED", "BLE advertising not supported", null)
            return
        }
        advertiser = advertiserLocal

        val decoded = fragments.mapNotNull {
            try {
                Base64.decode(it, Base64.DEFAULT)
            } catch (_: Exception) {
                null
            }
        }
        if (decoded.isEmpty()) {
            result.success(null)
            return
        }

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .setConnectable(false)
            .build()

        try {
            repeat(maxOf(1, repeatCount)) {
                for (fragment in decoded) {
                    val data = AdvertiseData.Builder()
                        .addServiceUuid(ParcelUuid(sosServiceUuid))
                        .addServiceData(ParcelUuid(sosServiceUuid), fragment)
                        .setIncludeDeviceName(false)
                        .setIncludeTxPowerLevel(false)
                        .build()
                    val cb = object : AdvertiseCallback() {}
                    meshAdvertiserCallback = cb
                    advertiserLocal.startAdvertising(settings, data, cb)
                    Thread.sleep(intervalMs.toLong().coerceAtLeast(50))
                    advertiserLocal.stopAdvertising(cb)
                }
            }
            result.success(null)
        } catch (e: Exception) {
            result.error("MESH_ADVERTISE_FAIL", e.message, null)
        }
    }

    // ── Payload builder ─────────────────────────────────────────────────────

    private fun buildPayload(lat: Double?, lng: Double?, userId: String): ByteArray {
        // 18 bytes: [0..7] userId hash, [8] flags, [9..12] lat, [13..16] lng, [17] reserved
        val buf = ByteArray(18)
        val hash = userId.hashCode().toLong() and 0xFFFFFFFFL
        for (i in 0..7) buf[i] = ((hash shr (i * 8)) and 0xFF).toByte()
        buf[8] = 0x01.toByte() // SOS flag
        val latBytes = ByteBuffer.allocate(4).putFloat((lat ?: Float.NaN.toDouble()).toFloat()).array()
        val lngBytes = ByteBuffer.allocate(4).putFloat((lng ?: Float.NaN.toDouble()).toFloat()).array()
        latBytes.copyInto(buf, 9)
        lngBytes.copyInto(buf, 13)
        buf[17] = 0x00 // reserved
        return buf
    }

    // ── Helpers ─────────────────────────────────────────────────────────────

    private fun getBluetoothAdapter(): BluetoothAdapter? {
        val mgr = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        return mgr?.adapter
    }

    private fun hasPermission(permission: String): Boolean {
        return ContextCompat.checkSelfPermission(this, permission) ==
                PackageManager.PERMISSION_GRANTED
    }

    private fun isBleSupportedAndEnabled(): Boolean {
        val adapter = getBluetoothAdapter() ?: return false
        return adapter.isEnabled && packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)
    }
}
