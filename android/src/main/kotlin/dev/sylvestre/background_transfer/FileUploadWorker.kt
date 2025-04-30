package dev.sylvestre.background_transfer

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.Data
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.asRequestBody
import okio.Buffer
import okio.BufferedSink
import okio.ForwardingSink
import okio.buffer
import java.io.File
import androidx.work.*
import java.util.concurrent.TimeUnit

class FileUploadWorker(
    private val context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {
    private val notificationHelper = NotificationHelper(context)

    companion object {
        private const val TAG = "FileUploadWorker"
    }

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val filePath = inputData.getString("file_path")
            ?: return@withContext Result.failure()
        val uploadUrl = inputData.getString("upload_url")
            ?: return@withContext Result.failure()
        val headersKeys = inputData.getStringArray("headers_keys") ?: emptyArray()
        val headersValues = inputData.getStringArray("headers_values") ?: emptyArray()
        val fieldsKeys = inputData.getStringArray("fields_keys") ?: emptyArray()
        val fieldsValues = inputData.getStringArray("fields_values") ?: emptyArray()
        
        val headers = headersKeys.zip(headersValues).toMap()
        val fields = fieldsKeys.zip(fieldsValues).toMap()

        // Show start notification
        notificationHelper.showStartNotification("upload", id.toString())

        val file = File(filePath)
        if (!file.exists()) {
            Log.e(TAG, "File does not exist: $filePath")
            notificationHelper.showCompleteNotification("upload", id.toString(), 
                Exception("File does not exist: $filePath"))
            return@withContext Result.failure()
        }

        val client = OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .build()

        val multipartBuilder = MultipartBody.Builder()
            .setType(MultipartBody.FORM)

        fields.forEach { (key, value) ->
            multipartBuilder.addFormDataPart(key, value)
        }

        val mimeType = getMimeType(file.absolutePath)
        val fileRequestBody = file.asRequestBody(mimeType.toMediaTypeOrNull())
        val countingRequestBody = CountingRequestBody(fileRequestBody) { bytesWritten, contentLength ->
            val progress = (bytesWritten * 100 / contentLength).toInt()
            notificationHelper.updateProgressNotification("upload", id.toString(), progress)
            setProgressAsync(Data.Builder()
                .putInt("progress", progress)
                .build())
            
            if (progress >= 100) {
                notificationHelper.showCompleteNotification("upload", id.toString())
            }
        }

        multipartBuilder.addFormDataPart("file", file.name, countingRequestBody)

        val request = Request.Builder()
            .url(uploadUrl)
            .apply {
                headers.forEach { (key, value) ->
                    addHeader(key, value)
                }
            }
            .post(multipartBuilder.build())
            .build()

        return@withContext try {
            Log.i(TAG, "Executing upload request")
            val response = client.newCall(request).execute()
            if (!response.isSuccessful) {
                val errorMessage = "Upload failed with code: ${response.code}"
                Log.e(TAG, errorMessage)
                notificationHelper.showCompleteNotification("upload", id.toString(), 
                    Exception(errorMessage))
                Result.failure(workDataOf("error" to errorMessage))
            } else {
                Log.i(TAG, "Upload completed successfully")
                notificationHelper.showCompleteNotification("upload", id.toString())
                Result.success()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Upload failed with exception", e)
            notificationHelper.showCompleteNotification("upload", id.toString(), e)
            Result.failure(workDataOf("error" to e.message))
        }
    }

    private fun getMimeType(path: String): String {
        val extension = path.substringAfterLast('.', "")
        return when (extension.lowercase()) {
            "png" -> "image/png"
            "jpg", "jpeg" -> "image/jpeg"
            "gif" -> "image/gif"
            "mp4" -> "video/mp4"
            "mov" -> "video/quicktime"
            "pdf" -> "application/pdf"
            "doc" -> "application/msword"
            "docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            "xls" -> "application/vnd.ms-excel"
            "xlsx" -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            "zip" -> "application/zip"
            else -> "application/octet-stream"
        }
    }
}

private class CountingRequestBody(
    private val delegate: RequestBody,
    private val onProgress: (bytesWritten: Long, contentLength: Long) -> Unit
) : RequestBody() {
    override fun contentType() = delegate.contentType()
    override fun contentLength() = delegate.contentLength()

    override fun writeTo(sink: BufferedSink) {
        val countingSink = object : ForwardingSink(sink) {
            private var bytesWritten = 0L

            override fun write(source: Buffer, byteCount: Long) {
                super.write(source, byteCount)
                bytesWritten += byteCount
                onProgress(bytesWritten, contentLength())
            }
        }.buffer()
        delegate.writeTo(countingSink)
        countingSink.flush()
    }
}