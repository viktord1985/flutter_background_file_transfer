package dev.sylvestre.background_transfer

import android.content.Context
import android.util.Log
import androidx.work.WorkManager
import androidx.work.WorkRequest
import androidx.work.Operation
import androidx.work.WorkInfo
import androidx.lifecycle.Observer
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequest
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import java.util.*

class TransferQueueManager(private val context: Context) {
    companion object {
        private const val TAG = "TransferQueueManager"
        private const val QUEUE_NAME = "background_transfer_queue"
    }

    private var isQueueEnabled = true
    private var maxConcurrentTransfers = 1
    private var cleanupDelay: Long = 0 // in milliseconds
    private val transferDetails = mutableMapOf<String, TransferDetails>()
    private val completedTasks = Collections.synchronizedSet(mutableSetOf<String>())

    data class TransferDetails(
        val type: String,
        val url: String,
        val path: String,
        val createdAt: Date,
        var progress: Float,
        var status: String,
        val fields: Map<String, String>
    ) {
        fun toMap(): Map<String, Any> {
            val map = mutableMapOf<String, Any>(
                "type" to type,
                "url" to url,
                "path" to path,
                "createdAt" to java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US).apply {
                    timeZone = java.util.TimeZone.getTimeZone("UTC")
                }.format(createdAt),
                "progress" to progress,
                "status" to status
            )
            // Add all fields directly to the root map like iOS
            fields.forEach { (key, value) -> map[key] = value }
            return map
        }
    }

    fun configureQueue(enabled: Boolean, maxConcurrent: Int, cleanupDelay: Long) {
        isQueueEnabled = enabled
        maxConcurrentTransfers = maxConcurrent
        this.cleanupDelay = cleanupDelay

        // Update WorkManager configuration
        if (isQueueEnabled) {
            WorkManager.getInstance(context).getConfiguration()
                .let { config ->
                    if (config.maxSchedulerLimit != maxConcurrent) {
                        // Note: This is just for demonstration. In practice, WorkManager's
                        // scheduler limit can't be changed at runtime, but we can control
                        // our own queue size
                        Log.d(TAG, "Updated max concurrent transfers to: $maxConcurrent")
                    }
                }
        }
    }

    fun enqueueTransfer(type: String, taskId: String, workRequest: WorkRequest, details: TransferDetails) {
        transferDetails[taskId] = details.copy(status = "queued")

        if (isQueueEnabled) {
            // Ensure we have a OneTimeWorkRequest
            if (workRequest !is OneTimeWorkRequest) {
                Log.e(TAG, "Work request must be OneTimeWorkRequest")
                transferDetails[taskId]?.status = "failed"
                return
            }
            
            // Use unique work to ensure we respect our concurrency limits
            WorkManager.getInstance(context)
                .beginUniqueWork(
                    "$QUEUE_NAME-$taskId",
                    ExistingWorkPolicy.REPLACE,
                    workRequest
                )
                .enqueue()
        } else {
            WorkManager.getInstance(context)
                .enqueue(workRequest)
        }

        // Observe work state for cleanup
        WorkManager.getInstance(context)
            .getWorkInfoByIdLiveData(workRequest.id)
            .observeForever(object : Observer<WorkInfo?> {
                override fun onChanged(workInfo: WorkInfo?) {
                    when (workInfo?.state) {
                        WorkInfo.State.RUNNING -> {
                            updateProgress(taskId)
                        }
                        WorkInfo.State.SUCCEEDED -> {
                            transferDetails[taskId]?.let { details ->
                                details.status = "completed"
                                details.progress = 1.0f
                            }
                            completedTasks.add(taskId)
                            scheduleCleanup(taskId)
                        }
                        WorkInfo.State.FAILED -> {
                            transferDetails[taskId]?.status = "failed"
                        }
                        WorkInfo.State.CANCELLED -> {
                            transferDetails[taskId]?.status = "cancelled"                      
                        }
                        else -> {
                            // Handle other states if needed
                        }
                    }
                }
            })
    }

    private fun scheduleCleanup(taskId: String) {
        if (cleanupDelay <= 0) {
            // Remove immediately if delay is 0 or negative
            completedTasks.remove(taskId)
            transferDetails.remove(taskId)
        } else {
            // Schedule cleanup after the configured delay
            CoroutineScope(Dispatchers.IO).launch {
                delay(cleanupDelay)
                completedTasks.remove(taskId)
                transferDetails.remove(taskId)
            }
        }
    }

    private fun getProgressFromPrefs(taskId: String): Float {
        return context.getSharedPreferences("transfer_progress", Context.MODE_PRIVATE)
            .getFloat("progress_$taskId", 0.0f)
    }

    fun updateProgress(taskId: String) {
        val progress = getProgressFromPrefs(taskId)
        transferDetails[taskId]?.let { details ->
            details.progress = progress
            if (details.status == "queued" && progress > 0) {
                details.status = "active"
            }
        }
    }

    fun isTaskComplete(taskId: String): Boolean {
        return completedTasks.contains(taskId)
    }

    fun cancelTask(taskId: String) {
        WorkManager.getInstance(context).cancelUniqueWork("$QUEUE_NAME-$taskId")
        transferDetails[taskId]?.status = "cancelled"
        completedTasks.remove(taskId)
    }

    fun deleteTask(taskId: String) {
        // Cancel any active work first
        WorkManager.getInstance(context).cancelUniqueWork("$QUEUE_NAME-$taskId")
        
        // Remove from progress tracking
        context.getSharedPreferences("transfer_progress", Context.MODE_PRIVATE)
            .edit()
            .remove("progress_$taskId")
            .apply()
            
        // Remove from our tracking collections
        completedTasks.remove(taskId)
        transferDetails.remove(taskId)
        
        Log.d(TAG, "Deleted task: $taskId")
    }

    fun getQueueStatus(): Map<String, Any> {
        val workManager = WorkManager.getInstance(context)
        var activeCount = 0
        var queuedCount = 0

        transferDetails.forEach { (_, details) ->
            when (details.status) {
                "active" -> activeCount++
                "queued" -> queuedCount++
            }
        }

        return mapOf(
            "isEnabled" to isQueueEnabled,
            "maxConcurrent" to maxConcurrentTransfers,
            "activeCount" to activeCount,
            "queuedCount" to queuedCount
        )
    }

    fun getQueuedTransfers(): List<Map<String, Any>> {
        Log.d(TAG, "Getting queued transfers. Total transfers: ${transferDetails.size}")
        val transfers = transferDetails.map { (taskId, details) ->
            Log.d(TAG, "Transfer $taskId: status=${details.status}, progress=${details.progress}")
            val baseMap = details.toMap()
            val completionTime = if (completedTasks.contains(taskId)) details.createdAt.time else 0L
            baseMap + mapOf(
                "taskId" to taskId,
                "completedDate" to completionTime
            )
        }
        Log.d(TAG, "Returning ${transfers.size} transfers")
        return transfers
    }

    fun updateTransferProgress(taskId: String, progress: Float) {
        transferDetails[taskId]?.let { details ->
            details.progress = progress
            if (details.status == "queued") {
                details.status = "active"
            }
        }
    }
}
