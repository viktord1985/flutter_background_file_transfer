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
import java.io.IOException
import java.net.URLConnection
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
        val filePath = inputData.getString("file_path") ?: return@withContext Result.failure()
        val uploadUrl = inputData.getString("upload_url") ?: return@withContext Result.failure()

        val headers = inputData.getStringArray("headers_keys")
            ?.zip(inputData.getStringArray("headers_values") ?: emptyArray())?.toMap() ?: emptyMap()

        val fields = inputData.getStringArray("fields_keys")
            ?.zip(inputData.getStringArray("fields_values") ?: emptyArray())?.toMap() ?: emptyMap()

        notificationHelper.showStartNotification("upload", id.toString())

        val file = File(filePath)
        if (!file.exists()) {
            val error = "File does not exist: $filePath"
            Log.e(TAG, error)
            notificationHelper.showCompleteNotification("upload", id.toString(), Exception(error))
            return@withContext Result.failure()
        }

        val client = OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .build()

        val multipartBuilder = MultipartBody.Builder().setType(MultipartBody.FORM)
        fields.forEach { (key, value) -> multipartBuilder.addFormDataPart(key, value) }

        var lastProgress = -1
        val mimeType = getMimeType(file.absolutePath)
        val fileRequestBody = file.asRequestBody(mimeType.toMediaTypeOrNull())

        val countingRequestBody = CountingRequestBody(fileRequestBody) { bytesWritten, contentLength ->
            if (isStopped) return@CountingRequestBody  // Exit early on cancel

            val progress = if (contentLength > 0) {
                (bytesWritten * 100 / contentLength).toInt()
            } else 0

            if (progress != lastProgress && progress in 0..100) {
                notificationHelper.updateProgressNotification("upload", id.toString(), progress)

                context.getSharedPreferences("transfer_progress", Context.MODE_PRIVATE)
                    .edit()
                    .putFloat("progress_${id}", progress / 100.0f)
                    .apply()

                setProgressAsync(workDataOf("progress" to progress))

                lastProgress = progress
            }
        }

        multipartBuilder.addFormDataPart("file", file.name, countingRequestBody)

        val request = Request.Builder()
            .url(uploadUrl)
            .apply { headers.forEach { (k, v) -> addHeader(k, v) } }
            .post(multipartBuilder.build())
            .build()

        try {
            Log.i(TAG, "Executing upload request")
            val response = client.newCall(request).execute()

            if (!response.isSuccessful) {
                val errorMessage = "Upload failed: ${response.code}"
                Log.e(TAG, errorMessage)
                notificationHelper.showCompleteNotification("upload", id.toString(), Exception(errorMessage))
                return@withContext Result.retry() // Retry on failure
            }

            Log.i(TAG, "Upload success")
            notificationHelper.showCompleteNotification("upload", id.toString())
            return@withContext Result.success()

        } catch (e: Exception) {
            Log.e(TAG, "Upload exception", e)
            notificationHelper.showCompleteNotification("upload", id.toString(), e)
            return@withContext Result.retry() // Retry network exceptions
        }
    }

    private fun getMimeType(path: String): String {
        return URLConnection.guessContentTypeFromName(path)
            ?: when (path.substringAfterLast('.', "").lowercase()) {
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

    override fun contentLength(): Long {
        return try {
            delegate.contentLength()
        } catch (e: IOException) {
            -1L
        }
    }

    override fun writeTo(sink: BufferedSink) {
        val countingSink = object : ForwardingSink(sink) {
            var bytesWritten = 0L
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
