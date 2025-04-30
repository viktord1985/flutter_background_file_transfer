import 'dart:async';
import 'package:background_transfer/file_transfer_handler.dart';
import 'package:flutter/services.dart';

/// Implementation of [FileTransferHandler] for Android platform.
/// 
/// This handler uses Android WorkManager to handle background file transfers,
/// providing reliable background processing with automatic retry capability
/// and progress tracking through notifications.
class AndroidFileTransferHandler implements FileTransferHandler {
  /// The method channel used to communicate with the native Android code.
  static const _channel = MethodChannel('background_transfer/task');

  /// Starts a file download operation in the background.
  /// 
  /// Uses Android's WorkManager to schedule and manage the download task,
  /// which continues even if the app is terminated.
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
  /// Monitors WorkManager progress updates through a broadcast stream.
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
  /// Uses Android's WorkManager to schedule and manage the upload task,
  /// which continues even if the app is terminated.
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
  /// Monitors WorkManager progress updates through a broadcast stream.
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
        if (progress is String && progress.startsWith('error:')) {
          throw Exception(progress.substring(6));
        }
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
  /// Attempts to cancel the WorkManager task with the given ID.
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
}
