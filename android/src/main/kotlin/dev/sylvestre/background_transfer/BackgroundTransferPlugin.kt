package dev.sylvestre.background_transfer

import io.flutter.embedding.engine.plugins.FlutterPlugin
import java.util.Date
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.BinaryMessenger
import android.content.Context
import android.content.pm.PackageManager
import android.Manifest
import android.app.Activity
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.work.*
import java.util.UUID
import androidx.annotation.NonNull
import android.util.Log
import androidx.lifecycle.Observer

/** BackgroundTransferPlugin */
class BackgroundTransferPlugin: FlutterPlugin, MethodCallHandler, ActivityAware {
  private lateinit var methodChannel: MethodChannel
  private lateinit var context: Context
  private lateinit var activity: Activity
  private lateinit var binaryMessenger: BinaryMessenger
  private val queueManager by lazy {
      QueueManagerHolder.getInstance(context)
  }
  private val progressChannels = mutableMapOf<String, EventChannel.EventSink>()
  private val uploadProgressChannels = mutableMapOf<String, EventChannel>()
  private val downloadProgressChannels = mutableMapOf<String, EventChannel>()
  
  companion object {
    private const val TAG = "BackgroundTransfer"
    private const val PERMISSION_REQUEST_CODE = 123
  }

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    Log.i(TAG, "Registering BackgroundTransferPlugin")
    context = flutterPluginBinding.applicationContext
    binaryMessenger = flutterPluginBinding.binaryMessenger
    methodChannel = MethodChannel(binaryMessenger, "background_transfer/task")
    methodChannel.setMethodCallHandler(this)
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
    checkNotificationPermission()
  }

  override fun onDetachedFromActivityForConfigChanges() {
    // No-op
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivity() {
    // No-op
  }

  private fun checkNotificationPermission() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      val permission = ContextCompat.checkSelfPermission(
        context,
        Manifest.permission.POST_NOTIFICATIONS
      )
      
      if (permission != PackageManager.PERMISSION_GRANTED) {
        ActivityCompat.requestPermissions(
          activity,
          arrayOf(Manifest.permission.POST_NOTIFICATIONS),
          PERMISSION_REQUEST_CODE
        )
      }
    }
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    Log.i(TAG, "Handling method call: ${call.method}")
    when (call.method) {
      "startDownload" -> handleStartDownload(call, result)
      "startUpload" -> handleStartUpload(call, result)
      "getDownloadProgress" -> handleGetProgress(call, result, "download")
      "getUploadProgress" -> handleGetProgress(call, result, "upload")
      "configureQueue" -> handleConfigureQueue(call, result)
      "getQueueStatus" -> handleGetQueueStatus(call, result)
      "getQueuedTransfers" -> handleGetQueuedTransfers(call, result)
      "isDownloadComplete" -> handleIsComplete(call, result, "download")
      "isUploadComplete" -> handleIsComplete(call, result, "upload")
      "cancelTask" -> handleCancelTask(call, result)
      "deleteTask" -> handleDeleteTask(call, result)
      "getPlatformVersion" -> {
        result.success("Android " + android.os.Build.VERSION.RELEASE)
      }
      else -> result.notImplemented()
    }
  }

  private fun handleStartDownload(call: MethodCall, result: Result) {
    Log.i(TAG, "Starting download")
    val fileUrl = call.argument<String>("file_url") ?: run {
      Log.e(TAG, "Missing file_url argument")
      result.error("INVALID_ARGUMENTS", "file_url is required", null)
      return
    }
    val outputPath = call.argument<String>("output_path") ?: run {
      Log.e(TAG, "Missing output_path argument")
      result.error("INVALID_ARGUMENTS", "output_path is required", null)
      return
    }
    val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
    val details = TransferQueueManager.TransferDetails(
        type = "download",
        url = fileUrl,
        path = outputPath,
        createdAt = Date(),
        progress = 0.0f,
        status = "queued",
        fields = emptyMap() // Downloads don't have fields
    )
    
    val data = workDataOf(
      "file_url" to fileUrl,
      "output_path" to outputPath,
      "headers_keys" to headers.keys.toTypedArray(),
      "headers_values" to headers.values.toTypedArray()
    )
    
    val downloadRequest = OneTimeWorkRequest.Builder(FileDownloadWorker::class.java)
      .setInputData(data)
      .build()
    
    // Observe work state changes
    WorkManager.getInstance(context)
      .getWorkInfoByIdLiveData(downloadRequest.id)
      .observeForever { workInfo ->
        if (workInfo != null) {
          when (workInfo.state) {
            WorkInfo.State.CANCELLED -> {
              val notificationHelper = NotificationHelper(context)
              notificationHelper.showCancelNotification("download", downloadRequest.id.toString())
            }
            WorkInfo.State.FAILED -> {
              val notificationHelper = NotificationHelper(context)
              val error = workInfo.outputData.getString("error") ?: "Unknown error"
              notificationHelper.showCompleteNotification("download", downloadRequest.id.toString(), Exception(error))
            }
            else -> {} // Other states are handled by the worker
          }
        }
      }
    
    val taskId = downloadRequest.id.toString()
    queueManager.enqueueTransfer("download", taskId, downloadRequest, details)
    Log.i(TAG, "Download started with taskId: $taskId")
    result.success(taskId)
  }

  private fun handleStartUpload(call: MethodCall, result: Result) {
    Log.i(TAG, "Starting upload")
    val filePath = call.argument<String>("file_path") ?: run {
      Log.e(TAG, "Missing file_path argument")
      result.error("INVALID_ARGUMENTS", "file_path is required", null)
      return
    }
    val uploadUrl = call.argument<String>("upload_url") ?: run {
      Log.e(TAG, "Missing upload_url argument")
      result.error("INVALID_ARGUMENTS", "upload_url is required", null)
      return
    }
    val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
    val fields = call.argument<Map<String, String>>("fields") ?: emptyMap()
    
    val details = TransferQueueManager.TransferDetails(
        type = "upload",
        url = uploadUrl,
        path = filePath,
        createdAt = Date(),
        progress = 0.0f,
        status = "queued",
        fields = fields  // Only include form fields for uploads, not headers
    )
    
    val data = workDataOf(
      "file_path" to filePath,
      "upload_url" to uploadUrl,
      "headers_keys" to headers.keys.toTypedArray(),
      "headers_values" to headers.values.toTypedArray(),
      "fields_keys" to fields.keys.toTypedArray(),
      "fields_values" to fields.values.toTypedArray()
    )
    
    val uploadRequest = OneTimeWorkRequest.Builder(FileUploadWorker::class.java)
      .setInputData(data)
      .build()

    // Observe work state changes
    WorkManager.getInstance(context)
      .getWorkInfoByIdLiveData(uploadRequest.id)
      .observeForever { workInfo ->
        if (workInfo != null) {
          when (workInfo.state) {
            WorkInfo.State.CANCELLED -> {
              val notificationHelper = NotificationHelper(context)
              notificationHelper.showCancelNotification("upload", uploadRequest.id.toString())
            }
            WorkInfo.State.FAILED -> {
              val notificationHelper = NotificationHelper(context)
              val error = workInfo.outputData.getString("error") ?: "Unknown error"
              notificationHelper.showCompleteNotification("upload", uploadRequest.id.toString(), Exception(error))
            }
            else -> {} // Other states are handled by the worker
          }
        }
      }
    
    val taskId = uploadRequest.id.toString()
    queueManager.enqueueTransfer("upload", taskId, uploadRequest, details)
    Log.i(TAG, "Upload started with taskId: $taskId")
    result.success(taskId)
  }

  private fun handleGetProgress(call: MethodCall, result: Result, type: String) {
    Log.i(TAG, "Setting up progress tracking for $type")
    val taskId = call.argument<String>("task_id") ?: run {
      Log.e(TAG, "Missing task_id argument")
      result.error("INVALID_ARGUMENTS", "Task ID is required", null)
      return
    }

    val channelName = "background_transfer/${type}_progress_$taskId"
    Log.d(TAG, "Creating event channel: $channelName")
    val eventChannel = EventChannel(binaryMessenger, channelName)
    
    eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
      private var workInfoObserver: Observer<WorkInfo>? = null
      
      override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        Log.d(TAG, "Stream handler listen callback for taskId: $taskId")
        progressChannels[taskId] = events
        
        // Send initial progress value from SharedPreferences
        val prefs = context.getSharedPreferences("${type}_prefs", Context.MODE_PRIVATE)
        val progress = prefs.getInt("${type}_progress_$taskId", 0)
        events.success(progress.toDouble() / 100.0)

        // Observe WorkManager progress
        workInfoObserver = Observer<WorkInfo> { workInfo ->
          when (workInfo.state) {
            WorkInfo.State.SUCCEEDED -> {
              events.success(1.0) // Ensure 100% progress
              events.endOfStream()
              workInfoObserver?.let { observer ->
                WorkManager.getInstance(context)
                  .getWorkInfoByIdLiveData(UUID.fromString(taskId))
                  .removeObserver(observer)
              }
            }
            WorkInfo.State.FAILED, WorkInfo.State.CANCELLED -> {
              val error = workInfo.outputData.getString("error")
              if (error != null) {
                events.error("TRANSFER_FAILED", error, null)
              }
              events.endOfStream()
              workInfoObserver?.let { observer ->
                WorkManager.getInstance(context)
                  .getWorkInfoByIdLiveData(UUID.fromString(taskId))
                  .removeObserver(observer)
              }
            }
            else -> {
              workInfo.progress.getInt("progress", -1).let { progress ->
                if (progress >= 0) {
                  events.success(progress.toDouble() / 100.0)
                }
              }
            }
          }
        }
        
        WorkManager.getInstance(context)
          .getWorkInfoByIdLiveData(UUID.fromString(taskId))
          .observeForever(workInfoObserver!!)
      }

      override fun onCancel(arguments: Any?) {
        Log.d(TAG, "Stream handler cancel callback for taskId: $taskId")
        progressChannels.remove(taskId)
        workInfoObserver?.let { observer ->
          WorkManager.getInstance(context)
            .getWorkInfoByIdLiveData(UUID.fromString(taskId))
            .removeObserver(observer)
        }
      }
    })

    result.success(null)
  }

  private fun handleIsComplete(call: MethodCall, result: Result, type: String) {
    val taskId = call.argument<String>("task_id") ?: run {
      Log.e(TAG, "Missing task_id argument")
      result.error("INVALID_ARGUMENTS", "Task ID is required", null)
      return
    }
    val isComplete = queueManager.isTaskComplete(taskId)
    Log.d(TAG, "Task $taskId completion status: $isComplete")
    result.success(isComplete)
  }

  private fun handleCancelTask(call: MethodCall, result: Result) {
    val taskId = call.argument<String>("task_id") ?: run {
      Log.e(TAG, "Missing task_id argument")
      result.error("INVALID_ARGUMENTS", "Task ID is required", null)
      return
    }
    Log.i(TAG, "Cancelling task: $taskId")
    
    // Determine if this was a download or upload task
    val type = if (downloadProgressChannels.containsKey(taskId)) "download" else "upload"
    
    // Show cancellation notification
    val notificationHelper = NotificationHelper(context)
    notificationHelper.showCancelNotification(type, taskId)
    
    // Cancel the work
    WorkManager.getInstance(context).cancelWorkById(UUID.fromString(taskId))
    result.success(true)
  }

  private fun handleConfigureQueue(call: MethodCall, result: Result) {
    val isEnabled = call.argument<Boolean>("isEnabled") ?: run {
      Log.e(TAG, "Missing isEnabled argument")
      result.error("INVALID_ARGUMENTS", "isEnabled is required", null)
      return
    }
    val maxConcurrent = call.argument<Int>("maxConcurrent") ?: 1
    val cleanupDelay = (call.argument<Double>("cleanupDelay") ?: 0.0).toLong() // Already in milliseconds from Dart

    queueManager.configureQueue(isEnabled, maxConcurrent, cleanupDelay)
    result.success(null)
  }

  private fun handleGetQueueStatus(call: MethodCall, result: Result) {
    result.success(queueManager.getQueueStatus())
  }

  private fun handleGetQueuedTransfers(call: MethodCall, result: Result) {
    val transfers = queueManager.getQueuedTransfers()
    Log.d(TAG, "Queued transfers: ${transfers.size} items")
    transfers.forEach { transfer ->
      Log.d(TAG, "Transfer: $transfer")
    }
    result.success(transfers)
  }

  private fun handleDeleteTask(call: MethodCall, result: Result) {
    val taskId = call.argument<String>("task_id") ?: run {
      Log.e(TAG, "Missing task_id argument")
      result.error("INVALID_ARGUMENTS", "Task ID is required", null)
      return
    }
    Log.i(TAG, "Deleting task: $taskId")

    // First cancel any active work
    WorkManager.getInstance(context).cancelWorkById(UUID.fromString(taskId))

    // Clean up resources in queue manager
    queueManager.deleteTask(taskId)

    // Clean up any progress channels
    progressChannels.remove(taskId)?.let { events ->
      events.endOfStream()
    }
    uploadProgressChannels.remove(taskId)?.setStreamHandler(null)
    downloadProgressChannels.remove(taskId)?.setStreamHandler(null)

    result.success(true)
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    Log.i(TAG, "Detaching BackgroundTransferPlugin")
    methodChannel.setMethodCallHandler(null)
    progressChannels.clear()
    uploadProgressChannels.clear()
    downloadProgressChannels.clear()
  }
}
