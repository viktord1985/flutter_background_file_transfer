package dev.sylvestre.background_transfer

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class NotificationHelper(private val context: Context) {
    companion object {
        private const val CHANNEL_ID = "background_transfer_channel"
        private const val CHANNEL_NAME = "Background Transfer"
        private const val CHANNEL_DESCRIPTION = "Shows transfer progress and status"
    }

    private var lastProgressUpdate = mutableMapOf<String, Int>()
    private var activeNotifications = mutableSetOf<String>()

    init {
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = CHANNEL_DESCRIPTION
                setShowBadge(false)
            }
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    fun showStartNotification(type: String, taskId: String) {
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(if (type == "download") "Download Started" else "Upload Started")
            .setContentText(if (type == "download") "Your download has begun" else "Your upload has begun")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setAutoCancel(false)
            .setOngoing(true)
            .setProgress(100, 0, true)
            .build()

        try {
            NotificationManagerCompat.from(context).notify(taskId.hashCode(), notification)
            lastProgressUpdate[taskId] = 0
            activeNotifications.add(taskId)
        } catch (e: SecurityException) {
            // Handle notification permission not granted
        }
    }

    fun updateProgressNotification(type: String, taskId: String, progress: Int) {
        // Don't update if we already showed completion notification
        if (!activeNotifications.contains(taskId)) return
        
        // Only update if progress has changed significantly (at least 1%)
        if (lastProgressUpdate[taskId] == progress) return
        
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(if (type == "download") "Downloading..." else "Uploading...")
            .setContentText("${progress}%")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setAutoCancel(false)
            .setOngoing(true)
            .setProgress(100, progress, false)
            .build()

        try {
            NotificationManagerCompat.from(context).notify(taskId.hashCode(), notification)
            lastProgressUpdate[taskId] = progress
            activeNotifications.add(taskId)
        } catch (e: SecurityException) {
            // Handle notification permission not granted
        }
    }

    fun showCompleteNotification(type: String, taskId: String, error: Exception? = null) {
        // Remove from active notifications to prevent further progress updates
        activeNotifications.remove(taskId)
        
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(if (error == null) android.R.drawable.stat_sys_download_done else android.R.drawable.stat_notify_error)
            .setContentTitle(
                if (error == null) {
                    if (type == "download") "Download Complete" else "Upload Complete"
                } else {
                    if (type == "download") "Download Failed" else "Upload Failed"
                }
            )
            .setContentText(error?.message ?: if (type == "download") "Your download has finished" else "Your upload has finished")
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setOngoing(false)
            .build()

        try {
            NotificationManagerCompat.from(context).notify(taskId.hashCode(), notification)
            // Clean up progress tracking
            lastProgressUpdate.remove(taskId)
        } catch (e: SecurityException) {
            // Handle notification permission not granted
        }
    }

    fun showCancelNotification(type: String, taskId: String) {
        // Remove from active notifications to prevent further progress updates
        activeNotifications.remove(taskId)
        
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_error)
            .setContentTitle(if (type == "download") "Download Cancelled" else "Upload Cancelled")
            .setContentText(if (type == "download") "Download was cancelled" else "Upload was cancelled")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setAutoCancel(true)
            .setOngoing(false)
            .build()

        try {
            NotificationManagerCompat.from(context).notify(taskId.hashCode(), notification)
            // Clean up progress tracking
            lastProgressUpdate.remove(taskId)
        } catch (e: SecurityException) {
            // Handle notification permission not granted
        }
    }
}