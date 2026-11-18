package com.mochirondesu.lap_deck

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.mochirondesu.lap_deck/platform"
        private const val REQ_POST_NOTIFICATIONS = 4101
    }

    private var pendingPermResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createNotificationChannels()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "areNotificationsGranted" -> {
                    result.success(checkNotificationsGranted())
                }
                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        if (checkNotificationsGranted()) {
                            result.success(true)
                        } else {
                            pendingPermResult = result
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                REQ_POST_NOTIFICATIONS
                            )
                        }
                    } else {
                        result.success(checkNotificationsGranted())
                    }
                }
                "showNotification" -> {
                    val id = call.argument<Int>("id") ?: (System.currentTimeMillis() % Int.MAX_VALUE).toInt()
                    val channelId = call.argument<String>("channelId") ?: "lapdeck_devices"
                    val title = call.argument<String>("title") ?: "LapDeck"
                    val body = call.argument<String>("body") ?: ""
                    val shown = showNativeNotification(id, channelId, title, body)
                    result.success(shown)
                }
                "canInstallPackages" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        result.success(packageManager.canRequestPackageInstalls())
                    } else {
                        result.success(true)
                    }
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath.isNullOrBlank()) {
                        result.error("INVALID_PATH", "APK file path is empty", null)
                    } else {
                        try {
                            val ok = launchApkInstaller(filePath)
                            result.success(ok)
                        } catch (e: Exception) {
                            result.error("INSTALL_ERROR", e.message ?: "Failed to launch installer", null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_POST_NOTIFICATIONS) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermResult?.success(granted)
            pendingPermResult = null
        }
    }

    private fun checkNotificationsGranted(): Boolean {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (!nm.areNotificationsEnabled()) return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channels = listOf(
                NotificationChannel(
                    "lapdeck_devices",
                    "Peer Connectivity & Status",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Alerts when remote workstations come online, go offline, or change mesh roles."
                },
                NotificationChannel(
                    "lapdeck_errors",
                    "Subsystem & Connector Errors",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Alerts for SSH/Telemetry failures, operation timeouts, and Connector daemon errors."
                },
                NotificationChannel(
                    "lapdeck_security",
                    "Lapdog Security & Session Alerts",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Alerts for Lapdog security events, Away Mode changes, and workstation lock states."
                },
                NotificationChannel(
                    "lapdeck_ai",
                    "Antigravity AI Console",
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply {
                    description = "Notifications when an Antigravity AI conversation turn finishes or fails."
                },
                NotificationChannel(
                    "lapdeck_updates",
                    "App Hotfix & Git OTA Updates",
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply {
                    description = "Notifications when a new LapDeck Git commit or hotfix APK update is available."
                }
            )
            for (ch in channels) {
                nm.createNotificationChannel(ch)
            }
        }
    }

    private fun showNativeNotification(
        id: Int,
        channelId: String,
        title: String,
        body: String
    ): Boolean {
        if (!checkNotificationsGranted()) return false
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getActivity(this, id, launchIntent, pendingFlags)

        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setColor(0xFFE89A50.toInt())

        nm.notify(id, builder.build())
        return true
    }

    private fun launchApkInstaller(filePath: String): Boolean {
        val apkFile = File(filePath)
        if (!apkFile.exists()) {
            throw IllegalArgumentException("APK file does not exist at $filePath")
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            val settingsIntent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName")
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(settingsIntent)
            return false
        }

        val apkUri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            apkFile
        )

        val installIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(installIntent)
        return true
    }
}
