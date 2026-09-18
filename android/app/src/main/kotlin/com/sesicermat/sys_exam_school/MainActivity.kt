package com.sesicermat.sys_exam_school

import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.sesicermat.sys_exam_school/app_installer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "installApk") {
                val filePath = call.argument<String>("filePath")
                if (filePath != null) {
                    val file = File(filePath)
                    if (file.exists() && file.length() > 0) {
                        try {
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                val uri: Uri = FileProvider.getUriForFile(
                                    context,
                                    "${applicationContext.packageName}.fileprovider",
                                    file
                                )
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL_ERROR", e.message, null)
                        }
                    } else {
                        result.error("FILE_NOT_FOUND", "File APK tidak ditemukan atau kosong", null)
                    }
                } else {
                    result.error("INVALID_ARGUMENT", "File path tidak boleh kosong", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
