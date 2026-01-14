package com.nexor.geotrack

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * BroadcastReceiver that handles device boot and app update events.
 * Starts BootStartService to ensure the background service is restarted.
 */
class BootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "GeoTrackBootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "Received intent: ${intent.action}")

        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED -> {
                Log.i(TAG, "Device boot completed, starting BootStartService")
                startBootService(context)
            }
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                Log.i(TAG, "App updated, starting BootStartService")
                startBootService(context)
            }
            else -> {
                Log.w(TAG, "Unexpected intent action: ${intent.action}")
            }
        }
    }

    private fun startBootService(context: Context) {
        try {
            val serviceIntent = Intent(context, BootStartService::class.java)
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
            
            Log.d(TAG, "BootStartService started successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start BootStartService", e)
        }
    }
}
