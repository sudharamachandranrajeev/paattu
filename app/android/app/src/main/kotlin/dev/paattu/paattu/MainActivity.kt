package dev.paattu.paattu

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// audio_service keeps playing in the background with a media notification.
class MainActivity : AudioServiceActivity() {
    // The updater's one job for the platform: hand a downloaded APK to the
    // system's installer. Since Android 7 the installer refuses a file: URI,
    // so it goes through a FileProvider (res/xml/file_paths.xml).
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.paattu.paattu/power")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "keepAwake" -> {
                        keepWifi(applicationContext, call.argument<Boolean>("on") == true)
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
