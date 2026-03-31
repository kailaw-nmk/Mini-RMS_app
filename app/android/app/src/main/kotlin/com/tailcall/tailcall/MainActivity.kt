package com.tailcall.tailcall

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.tailcall/foreground_service"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startService" -> {
                        startCallService()
                        result.success(true)
                    }
                    "stopService" -> {
                        stopCallService()
                        result.success(true)
                    }
                    "updateNotification" -> {
                        val statusText = call.argument<String>("statusText") ?: "接続中"
                        val duration = call.argument<String>("duration") ?: ""
                        updateServiceNotification(statusText, duration)
                        result.success(true)
                    }
                    "isBatteryOptimizationExcluded" -> {
                        result.success(isBatteryOptimizationExcluded())
                    }
                    "requestBatteryOptimizationExclusion" -> {
                        requestBatteryOptimizationExclusion()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startCallService() {
        val intent = Intent(this, CallForegroundService::class.java).apply {
            action = CallForegroundService.ACTION_START
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopCallService() {
        val intent = Intent(this, CallForegroundService::class.java).apply {
            action = CallForegroundService.ACTION_STOP
        }
        startService(intent)
    }

    private fun updateServiceNotification(statusText: String, duration: String) {
        val intent = Intent(this, CallForegroundService::class.java).apply {
            action = CallForegroundService.ACTION_UPDATE
            putExtra(CallForegroundService.EXTRA_STATUS_TEXT, statusText)
            putExtra(CallForegroundService.EXTRA_DURATION, duration)
        }
        startService(intent)
    }

    private fun isBatteryOptimizationExcluded(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestBatteryOptimizationExclusion() {
        if (!isBatteryOptimizationExcluded()) {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
        }
    }
}
