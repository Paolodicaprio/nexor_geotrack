package com.nexor.geotrack

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Production-grade foreground service that runs during boot/update.
 * Starts MainActivity minimized to initialize Flutter and background service.
 * Uses FLAG_ACTIVITY_NO_ANIMATION to reduce UI flash.
 */
class BootStartService : Service() {
    companion object {
        private const val TAG = "GeoTrackBootService"
        private const val CHANNEL_ID = "geotrack_boot_channel"
        private const val NOTIFICATION_ID = 999
        // Allow 10 seconds for Flutter to initialize and start background service
        private const val FLUTTER_INIT_DELAY_MS = 10000L
        private const val MAIN_ACTIVITY_CLASS = "com.example.geotrack_frontend.MainActivity"
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "BootStartService created")
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i(TAG, "BootStartService starting - initializing Flutter background service")

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("GeoTrack Service")
            .setContentText("Initialisation du service en arrière-plan...")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()

        startForeground(NOTIFICATION_ID, notification)
        startMainActivity()

        return START_STICKY
    }

    private fun startMainActivity() {
        try {
            Log.d(TAG, "Starting MainActivity to initialize Flutter")
            
            val mainActivityClass = Class.forName(MAIN_ACTIVITY_CLASS)
            val mainActivityIntent = Intent(this, mainActivityClass)
            
            mainActivityIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            mainActivityIntent.addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION)
            mainActivityIntent.addFlags(Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS)
            mainActivityIntent.action = "com.nexor.geotrack.BOOT_RESTART"
            
            startActivity(mainActivityIntent)
            Log.d(TAG, "MainActivity started for Flutter initialization")
            
            Handler(Looper.getMainLooper()).postDelayed({
                shutdownService()
            }, FLUTTER_INIT_DELAY_MS)
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start MainActivity", e)
            shutdownService()
        }
    }

    private fun shutdownService() {
        Log.d(TAG, "Shutting down BootStartService")
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        
        stopSelf()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "BootStartService destroyed")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "GeoTrack Boot Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Service de démarrage pour GeoTrack"
                setShowBadge(false)
            }

            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
            Log.d(TAG, "Notification channel created")
        }
    }
}
