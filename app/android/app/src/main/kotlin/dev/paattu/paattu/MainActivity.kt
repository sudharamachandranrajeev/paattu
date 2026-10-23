package dev.paattu.paattu

import android.content.Intent
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
}
