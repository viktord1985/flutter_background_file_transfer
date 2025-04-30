import 'dart:async';
import 'package:background_transfer/file_transfer_handler.dart';
import 'package:flutter/services.dart';

class IosFileTransferHandler implements FileTransferHandler {
  static const _channel = MethodChannel('background_transfer/task');

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

  @override
  Stream<double> getDownloadProgress(String taskId) async* {
    try {
      await _channel.invokeMethod('getDownloadProgress', {
        'task_id': taskId,
      });
      
      final eventChannel = EventChannel('background_transfer/download_progress_$taskId');
      yield* eventChannel.receiveBroadcastStream().map((progress) {
        return (progress as num).toDouble();
      });
    } on PlatformException catch (e) {
      throw Exception("Failed to get download progress: ${e.message}");
    }
  }

  @override
  Future<bool> isDownloadComplete(String taskId) async {
    try {
      return await _channel.invokeMethod('isDownloadComplete', {
        'task_id': taskId,
      }) ?? false;
    } on PlatformException {
      return false;
    }
  }

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

  @override
  Stream<double> getUploadProgress(String taskId) async* {
    try {
      await _channel.invokeMethod('getUploadProgress', {
        'task_id': taskId,
      });
      
      final eventChannel = EventChannel('background_transfer/upload_progress_$taskId');
      yield* eventChannel.receiveBroadcastStream().map((progress) {
        return (progress as num).toDouble();
      });
    } on PlatformException catch (e) {
      throw Exception("Failed to get upload progress: ${e.message}");
    }
  }

  @override
  Future<bool> isUploadComplete(String taskId) async {
    try {
      return await _channel.invokeMethod('isUploadComplete', {
        'task_id': taskId,
      }) ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> cancelTask(String taskId) async {
    try {
      return await _channel.invokeMethod('cancelTask', {
        'task_id': taskId,
      }) ?? false;
    } on PlatformException {
      return false;
    }
  }
}