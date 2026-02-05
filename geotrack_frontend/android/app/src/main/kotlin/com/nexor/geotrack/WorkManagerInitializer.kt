package com.nexor.geotrack

import android.content.Context
import android.util.Log
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/**
 * Initializes WorkManager periodic tasks for service health monitoring.
 * Sets up a periodic worker to check if the background service is running
 * and restart it if necessary.
 */
object WorkManagerInitializer {
    private const val TAG = "WorkManagerInit"
    private const val HEALTH_CHECK_WORK_NAME = "service_health_check"
    // 30-minute interval balances reliability with battery conservation
    private const val HEALTH_CHECK_INTERVAL_MINUTES = 30L

    fun initialize(context: Context) {
        try {
            Log.d(TAG, "Initializing WorkManager health checks")

            val constraints = Constraints.Builder()
                .setRequiresBatteryNotLow(false)
                .setRequiresCharging(false)
                .setRequiresDeviceIdle(false)
                .setRequiresStorageNotLow(false)
                .setRequiredNetworkType(NetworkType.NOT_REQUIRED)
                .build()

            val healthCheckRequest = PeriodicWorkRequestBuilder<ServiceHealthWorker>(
                HEALTH_CHECK_INTERVAL_MINUTES,
                TimeUnit.MINUTES,
                15,
                TimeUnit.MINUTES
            )
                .setConstraints(constraints)
                .addTag(HEALTH_CHECK_WORK_NAME)
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                HEALTH_CHECK_WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                healthCheckRequest
            )

            Log.i(TAG, "WorkManager health checks initialized: checking every $HEALTH_CHECK_INTERVAL_MINUTES minutes")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize WorkManager", e)
        }
    }

    fun cancel(context: Context) {
        try {
            WorkManager.getInstance(context).cancelUniqueWork(HEALTH_CHECK_WORK_NAME)
            Log.i(TAG, "WorkManager health checks cancelled")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cancel WorkManager", e)
        }
    }
}
