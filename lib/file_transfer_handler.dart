import 'dart:async';

/// A platform-independent interface for handling background file transfers.
///
/// This interface provides methods for uploading and downloading files in the background,
/// with support for progress tracking and cancellation. The implementation handles
/// platform-specific details for iOS and Android to ensure reliable background transfers
/// that continue even when the app is in the background.
///
/// Features:
/// * Background download and upload operations that continue when app is inactive
/// * Progress tracking through Dart streams
/// * Support for HTTP headers and multipart form fields
/// * Transfer status notifications
/// * Task cancellation
///
/// Platform-specific implementations:
/// * iOS: Uses URLSession background transfer capabilities
/// * Android: Uses WorkManager for reliable background processing
abstract class FileTransferHandler {
  /// Starts a file download operation in the background.
  ///
  /// The download continues even if the app moves to the background.
  /// Progress can be tracked using [getDownloadProgress].
  ///
  /// Parameters:
  /// * [fileUrl]: The URL of the file to download
  /// * [savePath]: Local path where the downloaded file should be saved
  /// * [headers]: Optional HTTP headers to include in the request
  ///
  /// Returns a task ID string that can be used to track progress or cancel the task.
  ///
  /// Throws an [Exception] if the download fails to start.
  Future<String> startDownload({
    required String fileUrl,
    required String savePath,
    Map<String, String>? headers,
  });

  /// Gets a stream of progress updates for a download task.
  ///
  /// Parameters:
  /// * [taskId]: The ID returned by [startDownload]
  ///
  /// Returns a stream that emits double values between 0.0 and 1.0,
  /// representing the download progress percentage.
  ///
  /// The stream completes when the download finishes or throws an error
  /// if the download fails.
  Stream<double> getDownloadProgress(String taskId);

  /// Checks if a download task has completed successfully.
  ///
  /// Parameters:
  /// * [taskId]: The ID returned by [startDownload]
  ///
  /// Returns true if the download is complete, false otherwise.
  Future<bool> isDownloadComplete(String taskId);

  /// Starts a file upload operation in the background.
  ///
  /// The upload continues even if the app moves to the background.
  /// Progress can be tracked using [getUploadProgress].
  ///
  /// Parameters:
  /// * [filePath]: Local path of the file to upload
  /// * [uploadUrl]: The URL where the file should be uploaded to
  /// * [headers]: Optional HTTP headers to include in the request
  /// * [fields]: Optional form fields to include in the multipart request
  ///
  /// Returns a task ID string that can be used to track progress or cancel the task.
  ///
  /// Throws an [Exception] if the upload fails to start.
  Future<String> startUpload({
    required String filePath,
    required String uploadUrl,
    Map<String, String>? headers,
    Map<String, String>? fields,
  });

  /// Gets a stream of progress updates for an upload task.
  ///
  /// Parameters:
  /// * [taskId]: The ID returned by [startUpload]
  ///
  /// Returns a stream that emits double values between 0.0 and 1.0,
  /// representing the upload progress percentage.
  ///
  /// The stream completes when the upload finishes or throws an error
  /// if the upload fails.
  Stream<double> getUploadProgress(String taskId);

  /// Checks if an upload task has completed successfully.
  ///
  /// Parameters:
  /// * [taskId]: The ID returned by [startUpload]
  ///
  /// Returns true if the upload is complete, false otherwise.
  Future<bool> isUploadComplete(String taskId);

  /// Cancels an ongoing transfer task.
  ///
  /// Parameters:
  /// * [taskId]: The ID of the task to cancel, from either [startDownload] or [startUpload]
  ///
  /// Returns true if the task was successfully cancelled, false otherwise.
  Future<bool> cancelTask(String taskId);
}
