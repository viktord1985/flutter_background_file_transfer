package dev.sylvestre.background_transfer

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.Data
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.ResponseBody
import okio.Buffer
import okio.ForwardingSink
import okio.buffer
import java.io.File
import android.util.Log
import androidx.work.workDataOf
import okio.sink
import java.util.concurrent.TimeUnit

class FileDownloadWorker(
    private val context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {
    private val notificationHelper = NotificationHelper(context)

    companion object {
        private const val TAG = "FileDownloadWorker"
    }

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val fileUrl = inputData.getString("file_url")
            ?: return@withContext Result.failure()
        val outputPath = inputData.getString("output_path")
            ?: return@withContext Result.failure()
        val headersKeys = inputData.getStringArray("headers_keys") ?: emptyArray()
        val headersValues = inputData.getStringArray("headers_values") ?: emptyArray()
        
        val headers = headersKeys.zip(headersValues).toMap()

        // Show start notification
        notificationHelper.showStartNotification("download", id.toString())

        val client = OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .build()

        val request = Request.Builder()
            .url(fileUrl)
            .apply {
                headers.forEach { (key, value) ->
                    addHeader(key, value)
                }
            }
            .build()

        return@withContext try {
            Log.i(TAG, "Executing download request")
            val response = client.newCall(request).execute()
            if (!response.isSuccessful) {
                Log.e(TAG, "Download failed with code: ${response.code}")
                notificationHelper.showCompleteNotification("download", id.toString(), 
                    Exception("Download failed with code: ${response.code}"))
                Result.failure()
            } else {
                val responseBody = response.body
                if (responseBody == null) {
                    Log.e(TAG, "Download failed: Empty response body")
                    notificationHelper.showCompleteNotification("download", id.toString(),
                        Exception("Download failed: Empty response body"))
                    return@withContext Result.failure()
                }

                val file = File(outputPath)
                file.parentFile?.mkdirs()

                var totalBytesRead = 0L
                val contentLength = responseBody.contentLength()

                // Save initial progress in SharedPreferences
                context.getSharedPreferences("download_prefs", Context.MODE_PRIVATE)
                    .edit()
                    .putInt("download_progress_${id}", 0)
                    .apply()

                file.sink().buffer().use { sink ->
                    responseBody.source().use { source ->
                        val buffer = Buffer()
                        var bytesRead: Long
                        
                        while (source.read(buffer, 8192L).also { bytesRead = it } != -1L) {
                            sink.write(buffer, bytesRead)
                            totalBytesRead += bytesRead
                            
                            val progress = if (contentLength > 0) {
                                (totalBytesRead * 100 / contentLength).toInt()
                            } else {
                                0
                            }
                            
                            // Update progress in SharedPreferences
                            context.getSharedPreferences("download_prefs", Context.MODE_PRIVATE)
                                .edit()
                                .putInt("download_progress_${id}", progress)
                                .apply()
                            
                            notificationHelper.updateProgressNotification("download", id.toString(), progress)
                            setProgressAsync(Data.Builder()
                                .putInt("progress", progress)
                                .build())

                            if (progress >= 100) {
                                notificationHelper.showCompleteNotification("download", id.toString())
                            }
                        }
                    }
                }

                // Save final completion state
                context.getSharedPreferences("download_prefs", Context.MODE_PRIVATE)
                    .edit()
                    .putInt("download_progress_${id}", 100)
                    .apply()

                Log.i(TAG, "Download completed successfully")
                notificationHelper.showCompleteNotification("download", id.toString())
                Result.success()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Download failed with exception", e)
            notificationHelper.showCompleteNotification("download", id.toString(), e)
            Result.failure()
        }
    }
}