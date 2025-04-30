import 'dart:async';
import 'dart:io';
import 'package:background_transfer/file_transfer_handler.dart';

class MockFileTransferHandler implements FileTransferHandler {
  final Map<String, StreamController<double>> _progressControllers = {};
  final Map<String, bool> _completedTasks = {};

  @override
  Future<String> startDownload({
    required String fileUrl,
    required String savePath,
    Map<String, String>? headers,
  }) async {
    final taskId = DateTime.now().toIso8601String();
    _progressControllers[taskId] = StreamController<double>();

    // Simulate download progress
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      final controller = _progressControllers[taskId];
      if (controller == null || controller.isClosed) {
        timer.cancel();
        return;
      }

      double progress = 0.0;
      controller.addStream(Stream.periodic(
        const Duration(milliseconds: 100),
        (count) {
          progress = (count + 1) / 10;
          if (progress >= 1.0) {
            timer.cancel();
            _completedTasks[taskId] = true;
            _createMockFile(savePath);
          }
          return progress;
        },
      ).take(10));
    });

    return taskId;
  }

  @override
  Future<String> startUpload({
    required String filePath,
    required String uploadUrl,
    Map<String, String>? headers,
    Map<String, String>? fields,
  }) async {
    final taskId = DateTime.now().toIso8601String();
    _progressControllers[taskId] = StreamController<double>();

    // Verify file exists
    if (!await File(filePath).exists()) {
      throw Exception('File not found: $filePath');
    }

    // Simulate upload progress
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      final controller = _progressControllers[taskId];
      if (controller == null || controller.isClosed) {
        timer.cancel();
        return;
      }

      double progress = 0.0;
      controller.addStream(Stream.periodic(
        const Duration(milliseconds: 100),
        (count) {
          progress = (count + 1) / 10;
          if (progress >= 1.0) {
            timer.cancel();
            _completedTasks[taskId] = true;
          }
          return progress;
        },
      ).take(10));
    });

    return taskId;
  }

  @override
  Stream<double> getDownloadProgress(String taskId) {
    final controller = _progressControllers[taskId];
    if (controller == null) {
      throw Exception('Task not found: $taskId');
    }
    return controller.stream;
  }

  @override
  Stream<double> getUploadProgress(String taskId) {
    final controller = _progressControllers[taskId];
    if (controller == null) {
      throw Exception('Task not found: $taskId');
    }
    return controller.stream;
  }

  @override
  Future<bool> cancelTask(String taskId) async {
    final controller = _progressControllers[taskId];
    if (controller == null) {
      return false;
    }

    await controller.close();
    _progressControllers.remove(taskId);
    _completedTasks.remove(taskId);
    return true;
  }

  @override
  Future<bool> isDownloadComplete(String taskId) async {
    return _completedTasks[taskId] ?? false;
  }

  @override
  Future<bool> isUploadComplete(String taskId) async {
    return _completedTasks[taskId] ?? false;
  }

  void _createMockFile(String path) {
    File(path).writeAsStringSync('Mock file content');
  }
}
