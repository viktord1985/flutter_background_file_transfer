import 'dart:io';
import 'dart:async';

/// Interface for handling file transfers (uploads and downloads)
abstract class FileTransferHandler {
  Future<String> startDownload({
    required String fileUrl,
    required String savePath,
    Map<String, String>? headers,
  });

  Stream<double> getDownloadProgress(String taskId);
  Future<bool> isDownloadComplete(String taskId);

  Future<String> startUpload({
    required String filePath,
    required String uploadUrl,
    Map<String, String>? headers,
    Map<String, String>? fields,
  });

  Stream<double> getUploadProgress(String taskId);
  Future<bool> isUploadComplete(String taskId);
  Future<bool> cancelTask(String taskId);
}

/// Mock implementation of FileTransferHandler for testing
class MockFileTransferHandler implements FileTransferHandler {
  final _activeTasks = <String, bool>{};
  final _completedTasks = <String>{};
  final _cancelledTasks = <String>{};

  @override
  Future<String> startDownload({
    required String fileUrl,
    required String savePath,
    Map<String, String>? headers,
  }) async {
    final taskId = 'download-${DateTime.now().millisecondsSinceEpoch}';
    _activeTasks[taskId] = true;

    if (fileUrl.contains('invalid')) {
      _activeTasks[taskId] = false;
      return taskId;
    }

    // Simulate actual file download
    await Future.delayed(const Duration(milliseconds: 100));
    await File(savePath).writeAsString('Mock downloaded content');
    _completedTasks.add(taskId);
    _activeTasks[taskId] = false;

    return taskId;
  }

  @override
  Stream<double> getDownloadProgress(String taskId) async* {
    if (!_activeTasks.containsKey(taskId)) {
      throw Exception('Task not found');
    }

    if (_cancelledTasks.contains(taskId)) {
      throw Exception('Task was cancelled');
    }

    if (!_activeTasks[taskId]! && !_completedTasks.contains(taskId)) {
      throw Exception('Download failed');
    }

    yield 0.0;
    await Future.delayed(const Duration(milliseconds: 50));
    yield 0.5;
    await Future.delayed(const Duration(milliseconds: 50));
    yield 1.0;
  }

  @override
  Future<bool> isDownloadComplete(String taskId) async {
    return _completedTasks.contains(taskId);
  }

  @override
  Future<String> startUpload({
    required String filePath,
    required String uploadUrl,
    Map<String, String>? headers,
    Map<String, String>? fields,
  }) async {
    final taskId = 'upload-${DateTime.now().millisecondsSinceEpoch}';
    _activeTasks[taskId] = true;

    if (uploadUrl.contains('invalid')) {
      _activeTasks[taskId] = false;
      return taskId;
    }

    // Simulate actual file upload
    await Future.delayed(const Duration(milliseconds: 100));
    _completedTasks.add(taskId);
    _activeTasks[taskId] = false;

    return taskId;
  }

  @override
  Stream<double> getUploadProgress(String taskId) async* {
    if (!_activeTasks.containsKey(taskId)) {
      throw Exception('Task not found');
    }

    if (_cancelledTasks.contains(taskId)) {
      throw Exception('Task was cancelled');
    }

    if (!_activeTasks[taskId]! && !_completedTasks.contains(taskId)) {
      throw Exception('Upload failed');
    }

    yield 0.0;
    await Future.delayed(const Duration(milliseconds: 50));
    yield 0.5;
    await Future.delayed(const Duration(milliseconds: 50));
    yield 1.0;
  }

  @override
  Future<bool> isUploadComplete(String taskId) async {
    return _completedTasks.contains(taskId);
  }

  @override
  Future<bool> cancelTask(String taskId) async {
    if (!_activeTasks.containsKey(taskId)) {
      return false;
    }

    if (_activeTasks[taskId]!) {
      _cancelledTasks.add(taskId);
      _activeTasks[taskId] = false;
      return true;
    }

    return false;
  }
}
