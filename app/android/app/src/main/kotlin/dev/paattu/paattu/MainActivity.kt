package dev.paattu.paattu

import android.Manifest
import android.app.UiModeManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.audiofx.Virtualizer
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteOrder

// audio_service keeps playing in the background with a media notification.
class MainActivity : AudioServiceActivity() {
    // The updater's one job for the platform: hand a downloaded APK to the
    // system's installer. Since Android 7 the installer refuses a file: URI,
    // so it goes through a FileProvider (res/xml/file_paths.xml).
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // A TV (lib/src/device.dart): its UI mode, or a box that says it has
        // the TV launcher.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.paattu.paattu/device")
            .setMethodCallHandler { call, result ->
                if (call.method == "isTv") {
                    val mode = (getSystemService(Context.UI_MODE_SERVICE) as UiModeManager).currentModeType
                    result.success(mode == Configuration.UI_MODE_TYPE_TELEVISION ||
                        packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK))
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.paattu.paattu/power")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "keepAwake" -> {
                        keepWifi(applicationContext, call.argument<Boolean>("on") == true)
                        result.success(null)
                    }
                    // A window flag: Android honours it only while this
                    // activity is showing.
                    "screenAwake" -> {
                        if (call.argument<Boolean>("on") == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    "notificationsAllowed" -> result.success(notificationsAllowed())
                    "askNotifications" -> {
                        if (!notificationsAllowed()) {
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
                        }
                        result.success(null)
                    }
                    "filesAllowed" -> result.success(filesAllowed())
                    "askFiles" -> {
                        if (!filesAllowed()) {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                try {
                                    startActivity(
                                        Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                                            .setData(Uri.parse("package:$packageName"))
                                    )
                                } catch (error: Exception) {
                                    startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
                                }
                            } else {
                                requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 2)
                            }
                        }
                        result.success(null)
                    }
                    "batteryExempt" -> result.success(batteryExempt())
                    "askBatteryExempt" -> {
                        try {
                            // Straight to "allow running in the background?",
                            // else the list of apps' battery settings.
                            startActivity(
                                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                                    .setData(Uri.parse("package:$packageName"))
                            )
                        } catch (error: Exception) {
                            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        // Now Playing's rings follow the song's rhythm (rhythm.dart): its file
        // decoded to 16-bit mono, off the main thread.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.paattu.paattu/rhythm")
            .setMethodCallHandler { call, result ->
                val path = call.argument<String>("path")
                val out = call.argument<String>("out")
                if (call.method != "decode" || path == null || out == null) {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val wanted = call.argument<Int>("rate") ?: 11025
                val main = Handler(Looper.getMainLooper())
                Thread {
                    try {
                        val rate = decodeMono(path, out, wanted)
                        main.post { result.success(rate) }
                    } catch (error: Exception) {
                        main.post { result.error("decode_failed", error.toString(), null) }
                    }
                }.start()
            }
        // Surround (android_surround.dart): the phone's virtualizer on a
        // player's audio session, at 0 … 1000.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.paattu.paattu/sound")
            .setMethodCallHandler { call, result ->
                val session = call.argument<Int>("session")
                val strength = call.argument<Int>("strength")
                val live = call.argument<List<Int>>("live") ?: listOf(session ?: 0)
                if (call.method != "surround" || session == null || strength == null) {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    surround(session, strength, live)
                    result.success(null)
                } catch (error: Exception) {
                    result.error("surround_failed", error.toString(), null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.paattu.paattu/update")
            .setMethodCallHandler { call, result ->
                if (call.method != "installApk") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("no_path", "no APK path given", null)
                    return@setMethodCallHandler
                }
                try {
                    val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", File(path))
                    startActivity(
                        Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                        }
                    )
                    result.success(true)
                } catch (error: Exception) {
                    result.error("install_failed", error.message, null)
                }
            }
    }

    private fun notificationsAllowed(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    // A folder picked for the kept songs: written with plain file paths.
    private fun filesAllowed(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        }

    private fun batteryExempt(): Boolean =
        (getSystemService(Context.POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(packageName)

    companion object {
        // [path] decoded into [out] as 16-bit little-endian mono, near [wanted]
        // samples a second: the channels averaged, then runs of samples
        // averaged down (MediaCodec gives the file's own rate). Returns the
        // rate written.
        fun decodeMono(path: String, out: String, wanted: Int): Int {
            val extractor = MediaExtractor()
            var codec: MediaCodec? = null
            try {
                extractor.setDataSource(path)
                val track = (0 until extractor.trackCount).firstOrNull {
                    extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
                } ?: throw IllegalArgumentException("no sound in $path")
                extractor.selectTrack(track)
                val format = extractor.getTrackFormat(track)
                val decoder = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
                codec = decoder
                decoder.configure(format, null, null, 0)
                decoder.start()
                var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                var rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                var floats = false
                // Fixed at the first sound out, when the real rate is known.
                var step = 0
                var sum = 0.0
                var count = 0
                val info = MediaCodec.BufferInfo()
                BufferedOutputStream(FileOutputStream(out)).use { sink ->
                    var inputDone = false
                    while (true) {
                        if (!inputDone) {
                            val input = decoder.dequeueInputBuffer(10_000)
                            if (input >= 0) {
                                val size = extractor.readSampleData(decoder.getInputBuffer(input)!!, 0)
                                if (size < 0) {
                                    decoder.queueInputBuffer(input, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                    inputDone = true
                                } else {
                                    decoder.queueInputBuffer(input, 0, size, extractor.sampleTime, 0)
                                    extractor.advance()
                                }
                            }
                        }
                        val output = decoder.dequeueOutputBuffer(info, 10_000)
                        if (output == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                            val now = decoder.outputFormat
                            channels = now.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                            rate = now.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                            floats = Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
                                now.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                                now.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
                        } else if (output >= 0) {
                            if (step == 0) step = maxOf(1, rate / wanted)
                            val buffer = decoder.getOutputBuffer(output)!!.order(ByteOrder.LITTLE_ENDIAN)
                            buffer.position(info.offset)
                            buffer.limit(info.offset + info.size)
                            val frames = info.size / ((if (floats) 4 else 2) * channels)
                            for (i in 0 until frames) {
                                var mono = 0.0
                                for (c in 0 until channels) {
                                    mono += if (floats) buffer.getFloat() * 32767.0 else buffer.getShort().toDouble()
                                }
                                sum += mono / channels
                                if (++count == step) {
                                    val sample = (sum / step).toInt().coerceIn(-32768, 32767)
                                    sink.write(sample and 0xff)
                                    sink.write((sample shr 8) and 0xff)
                                    sum = 0.0
                                    count = 0
                                }
                            }
                            decoder.releaseOutputBuffer(output, false)
                            if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                        }
                    }
                }
                return rate / maxOf(1, step)
            } finally {
                try {
                    codec?.stop()
                } catch (ignored: Exception) {
                }
                codec?.release()
                extractor.release()
            }
        }

        // A virtualizer for each audio session given some surround, held by
        // the application like the players; those of players gone (not in
        // [live]) or turned down to none are let go, so with surround off
        // the phone's effect engine is never touched.
        private val virtualizers = HashMap<Int, Virtualizer>()

        @Suppress("DEPRECATION")
        fun surround(session: Int, strength: Int, live: List<Int>) {
            for (gone in virtualizers.keys.filter { it != session && it !in live }) {
                virtualizers.remove(gone)?.release()
            }
            if (strength <= 0) {
                virtualizers.remove(session)?.release()
                return
            }
            val effect = virtualizers.getOrPut(session) { Virtualizer(0, session) }
            if (effect.strengthSupported) effect.setStrength(strength.coerceIn(0, 1000).toShort())
            effect.enabled = true
        }

        // Wi-Fi kept awake while music plays: audio_service holds the CPU,
        // but with the screen off some phones let Wi-Fi doze and the stream
        // runs dry. Held by the application, so it outlives the activity.
        private var wifiLock: WifiManager.WifiLock? = null

        @Suppress("DEPRECATION")
        fun keepWifi(context: Context, on: Boolean) {
            if (on) {
                val lock = wifiLock ?: (context.getSystemService(Context.WIFI_SERVICE) as WifiManager)
                    .createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "paattu:playback")
                    .also { it.setReferenceCounted(false); wifiLock = it }
                if (!lock.isHeld) lock.acquire()
            } else {
                wifiLock?.let { if (it.isHeld) it.release() }
            }
        }
    }
}
