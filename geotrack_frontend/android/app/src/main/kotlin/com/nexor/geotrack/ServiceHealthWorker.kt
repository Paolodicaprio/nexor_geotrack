package com.nexor.geotrack

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters

/**
 * WorkManager worker that periodically attempts to restart the background service.
 * Provides a fallback mechanism if the service dies unexpectedly between reboots.
 */
class ServiceHealthWorker(
    context: Context,
    params: WorkerParameters
) : Worker(context, params) {

    companion object {
        private const val TAG = "ServiceHealthWorker"
    }

    override fun doWork(): Result {
        Log.d(TAG, "Running service health check - ensuring background service is running")

        return try {
            ensureBackgroundServiceRunning()
            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "Health check failed", e)
            Result.retry()
        }
    }

    private fun ensureBackgroundServiceRunning() {
        try {
            val serviceIntent = Intent(applicationContext, BootStartService::class.java)
            serviceIntent.putExtra("restart_reason", "health_check")
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                applicationContext.startForegroundService(serviceIntent)
            } else {
                applicationContext.startService(serviceIntent)
            }
            
            Log.i(TAG, "Triggered BootStartService to ensure background service is running")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to trigger BootStartService", e)
            throw e
        }
    }
}
