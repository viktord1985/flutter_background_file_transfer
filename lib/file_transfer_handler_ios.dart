import 'dart:async';
import 'package:background_transfer/file_transfer_handler.dart';
import 'package:flutter/services.dart';

/// Implementation of [FileTransferHandler] for iOS platform.
///
/// This handler uses native iOS URLSession background transfer capabilities to handle
/// file downloads and uploads even when the app is in the background. It supports
/// progress tracking and shows native notifications for transfer status.
class IosFileTransferHandler implements FileTransferHandler {
  /// The method channel used to communicate with the native iOS code.
  static const _channel = MethodChannel('background_transfer/task');

  /// Configure the transfer queue behavior
  ///
  /// [isEnabled] - When true, transfers will be queued and processed according to [maxConcurrent].
  /// When false, transfers will start immediately without queueing.
  ///
  /// [maxConcurrent] - The maximum number of concurrent transfers allowed when queue is enabled.
  /// Default is 1, which processes transfers serially.
  @override
  Future<void> configureQueue({
    required bool isEnabled,
    int maxConcurrent = 1,
    double cleanupDelay = 0,
  }) async {
    try {
      // Convert cleanupDelay from milliseconds to seconds for iOS
      await _channel.invokeMethod('configureQueue', {
        'isEnabled': isEnabled,
        'maxConcurrent': maxConcurrent,
        'cleanupDelay': cleanupDelay / 1000.0, // Convert ms to seconds
      });
    } on PlatformException catch (e) {
      throw Exception("Failed to configure queue: ${e.message}");
    }
  }

  /// Starts a file download operation in the background.
  ///
  /// [fileUrl] The URL of the file to download.
  /// [savePath] The local path where the downloaded file should be saved.
  /// [headers] Optional HTTP headers to include in the download request.
  ///
  /// Returns a task ID string that can be used to track the download progress
  /// or cancel the operation.
  ///
  /// Throws an [Exception] if the download fails to start.
  @override
  Future<String> startDownload({
    required String fileUrl,
    required String savePath,
    Map<String, String>? headers,
  }) async {
    try {
      final taskId = await _channel.invokeMethod('startDownload', {
        'file_url': fileUrl,
        'output_path': savePath,
        'headers': headers,
      });
      return taskId as String;
    } on PlatformException catch (e) {
      throw Exception("Failed to start download: ${e.message}");
    }
  }

  /// Gets a stream of download progress updates for a specific task.
  ///
  /// [taskId] The ID of the download task to track.
  ///
  /// Returns a stream that emits progress values between 0.0 and 1.0.
  ///
  /// Throws an [Exception] if tracking the progress fails.
  @override
  Stream<double> getDownloadProgress(String taskId) async* {
    try {
      await _channel.invokeMethod('getDownloadProgress', {
        'task_id': taskId,
      });

      final eventChannel =
          EventChannel('background_transfer/download_progress_$taskId');
      yield* eventChannel.receiveBroadcastStream().map((progress) {
        return (progress as num).toDouble();
      });
    } on PlatformException catch (e) {
      throw Exception("Failed to get download progress: ${e.message}");
    }
  }

  /// Checks if a download task has completed.
  ///
  /// [taskId] The ID of the download task to check.
  ///
  /// Returns true if the download is complete, false otherwise.
  @override
  Future<bool> isDownloadComplete(String taskId) async {
    try {
      return await _channel.invokeMethod('isDownloadComplete', {
            'task_id': taskId,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// Starts a file upload operation in the background.
  ///
  /// [filePath] The local path of the file to upload.
  /// [uploadUrl] The URL where the file should be uploaded to.
  /// [headers] Optional HTTP headers to include in the upload request.
  /// [fields] Optional form fields to include in the multipart upload request.
  ///
  /// Returns a task ID string that can be used to track the upload progress
  /// or cancel the operation.
  ///
  /// Throws an [Exception] if the upload fails to start.
  @override
  Future<String> startUpload({
    required String filePath,
    required String uploadUrl,
    Map<String, String>? headers,
    Map<String, String>? fields,
  }) async {
    try {
      final taskId = await _channel.invokeMethod('startUpload', {
        'file_path': filePath,
        'upload_url': uploadUrl,
        'headers': headers,
        'fields': fields,
      });
      return taskId as String;
    } on PlatformException catch (e) {
      throw Exception("Failed to start upload: ${e.message}");
    }
  }

  /// Gets a stream of upload progress updates for a specific task.
  ///
  /// [taskId] The ID of the upload task to track.
  ///
  /// Returns a stream that emits progress values between 0.0 and 1.0.
  ///
  /// Throws an [Exception] if tracking the progress fails.
  @override
  Stream<double> getUploadProgress(String taskId) async* {
    try {
      await _channel.invokeMethod('getUploadProgress', {
        'task_id': taskId,
      });

      final eventChannel =
          EventChannel('background_transfer/upload_progress_$taskId');
      yield* eventChannel.receiveBroadcastStream().map((progress) {
        return (progress as num).toDouble();
      });
    } on PlatformException catch (e) {
      throw Exception("Failed to get upload progress: ${e.message}");
    }
  }

  /// Checks if an upload task has completed.
  ///
  /// [taskId] The ID of the upload task to check.
  ///
  /// Returns true if the upload is complete, false otherwise.
  @override
  Future<bool> isUploadComplete(String taskId) async {
    try {
      return await _channel.invokeMethod('isUploadComplete', {
            'task_id': taskId,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// Cancels an ongoing transfer task.
  ///
  /// [taskId] The ID of the task to cancel.
  ///
  /// Returns true if the task was successfully cancelled, false otherwise.
  @override
  Future<bool> cancelTask(String taskId) async {
    try {
      return await _channel.invokeMethod('cancelTask', {
            'task_id': taskId,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// Gets the current status of the transfer queue.
  ///
  /// Returns a map containing the queue status information.
  ///
  /// Throws an [Exception] if the status retrieval fails.
  @override
  Future<Map<String, dynamic>> getQueueStatus() async {
    try {
      final status = await _channel.invokeMethod('getQueueStatus');
      return Map<String, dynamic>.from(status);
    } on PlatformException catch (e) {
      throw Exception("Failed to get queue status: ${e.message}");
    }
  }

  /// Gets a list of transfers currently in the queue.
  ///
  /// Returns a list of maps, each containing information about a queued transfer.
  ///
  /// Throws an [Exception] if the retrieval of queued transfers fails.
  @override
  Future<List<Map<String, dynamic>>> getQueuedTransfers() async {
    try {
      final transfers = await _channel.invokeMethod('getQueuedTransfers');
      return (transfers as List)
          .map((t) => Map<String, dynamic>.from(t))
          .toList();
    } on PlatformException catch (e) {
      throw Exception("Failed to get queued transfers: ${e.message}");
    }
  }

  @override
  Future<bool> deleteTask(String taskId) async {
    try {
      return await _channel.invokeMethod('deleteTask', {
            'task_id': taskId,
          }) ??
          false;
    } on PlatformException catch (e) {
      throw Exception("Failed to delete task: ${e.message}");
    }
  }
}
