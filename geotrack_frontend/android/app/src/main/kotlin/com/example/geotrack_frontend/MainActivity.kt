package com.example.geotrack_frontend

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.nexor.geotrack/battery"
    private val TAG = "GeoTrackMainActivity"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBatteryOptimizations(result)
                }
                "isIgnoringBatteryOptimizations" -> {
                    result.success(isIgnoringBatteryOptimizations())
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        if (intent?.action == "com.nexor.geotrack.BOOT_RESTART") {
            Log.i(TAG, "MainActivity started from boot/update restart")
        }
        
        initializeWorkManager()
    }
    
    private fun initializeWorkManager() {
        try {
            com.nexor.geotrack.WorkManagerInitializer.initialize(this)
            Log.i(TAG, "WorkManager initialized for service health monitoring")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize WorkManager", e)
        }
    }

    private fun requestIgnoreBatteryOptimizations(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val intent = Intent()
                val packageName = packageName
                
                intent.action = Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                intent.data = Uri.parse("package:$packageName")
                
                startActivity(intent)
                result.success(true)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to open battery optimization settings", e)
                try {
                    val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                    startActivity(intent)
                    result.success(true)
                } catch (e2: Exception) {
                    Log.e(TAG, "Failed to open general battery settings", e2)
                    result.error("UNAVAILABLE", "Battery optimization settings not available", null)
                }
            }
        } else {
            result.success(false)
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            return powerManager.isIgnoringBatteryOptimizations(packageName)
        }
        return false
    }
}
