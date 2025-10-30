import 'dart:async';
import 'dart:io';
import 'package:background_transfer/file_transfer_handler.dart';

class MockFileTransferHandler implements FileTransferHandler {
  final Map<String, StreamController<double>> _progressControllers = {};
  final Map<String, StreamController<int>> _statusControllers = {};
  final Map<String, bool> _completedTasks = {};
  final Map<String, Map<String, dynamic>> _taskDetails = {};
  final Map<String, double> _currentProgress = {};
  bool _isQueueEnabled = true;
  int _maxConcurrent = 1;
  final List<Function> _queuedOperations = [];
  int _activeOperations = 0;

  @override
  Future<void> configureQueue({
    required bool isEnabled,
    int maxConcurrent = 1,
    double cleanupDelay = 0,
  }) async {
    _isQueueEnabled = isEnabled;
    _maxConcurrent = maxConcurrent;
    _processQueue();
  }

  void _processQueue() {
    if (!_isQueueEnabled) {
      // Execute all queued operations immediately
      while (_queuedOperations.isNotEmpty) {
        final operation = _queuedOperations.removeAt(0);
        operation();
      }
      return;
    }

    while (_activeOperations < _maxConcurrent && _queuedOperations.isNotEmpty) {
      _activeOperations++;
      final operation = _queuedOperations.removeAt(0);
      operation();
    }
  }

  Future<void> _enqueueOperation(Function operation) async {
    if (!_isQueueEnabled || _activeOperations < _maxConcurrent) {
      _activeOperations++;
      operation();
    } else {
      _queuedOperations.add(operation);
    }
  }

  void _operationComplete() {
    _activeOperations--;
    _processQueue();
  }

  @override
  Future<Map<String, dynamic>> getQueueStatus() async {
    return {
      'isEnabled': _isQueueEnabled,
      'maxConcurrent': _maxConcurrent,
      'activeCount': _activeOperations,
      'queuedCount': _queuedOperations.length,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> getQueuedTransfers() async {
    return _taskDetails.entries.map((entry) {
      final taskId = entry.key;
      final details = entry.value;

      return {
        'taskId': taskId,
        ...details,
        'progress': _currentProgress[taskId] ?? 0.0,
        'status': _getTaskStatus(taskId),
      };
    }).toList();
  }

  String _getTaskStatus(String taskId) {
    if (_completedTasks[taskId] == true) return 'completed';
    final isActive = _progressControllers[taskId]?.hasListener ?? false;
    return isActive ? 'active' : 'queued';
  }

  void _updateProgress(String taskId, double progress) {
    _currentProgress[taskId] = progress;
  }

  @override
  Future<String> startDownload({
    required String fileUrl,
    required String savePath,
    Map<String, String>? headers,
  }) async {
    final taskId = DateTime.now().toIso8601String();
    _taskDetails[taskId] = {
      'type': 'download',
      'url': fileUrl,
      'path': savePath,
      'createdAt': DateTime.now().toIso8601String(),
    };
    _progressControllers[taskId] = StreamController<double>();
    _currentProgress[taskId] = 0.0;

    await _enqueueOperation(() {
      // Simulate download progress
      Timer.periodic(const Duration(milliseconds: 100), (timer) {
        final controller = _progressControllers[taskId];
        if (controller == null || controller.isClosed) {
          timer.cancel();
          _operationComplete();
          return;
        }

        double progress = 0.0;
        controller.addStream(Stream.periodic(
          const Duration(milliseconds: 100),
          (count) {
            progress = (count + 1) / 10;
            _updateProgress(taskId, progress);
            if (progress >= 1.0) {
              timer.cancel();
              _completedTasks[taskId] = true;
              _createMockFile(savePath);
              _operationComplete();
            }
            return progress;
          },
        ).take(10));
      });
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
    _taskDetails[taskId] = {
      'type': 'upload',
      'url': uploadUrl,
      'path': filePath,
      'createdAt': DateTime.now().toIso8601String(),
    };
    _progressControllers[taskId] = StreamController<double>();

    // Verify file exists
    if (!await File(filePath).exists()) {
      throw Exception('File not found: $filePath');
    }

    await _enqueueOperation(() {
      // Simulate upload progress
      Timer.periodic(const Duration(milliseconds: 100), (timer) {
        final controller = _progressControllers[taskId];
        if (controller == null || controller.isClosed) {
          timer.cancel();
          _operationComplete();
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
              _operationComplete();
            }
            return progress;
          },
        ).take(10));
      });
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
  Stream<int> getResultStatus(String taskId) {
    final controller = _statusControllers[taskId];
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

  @override
  Future<bool> deleteTask(String taskId) async {
    // First cancel any active task
    await cancelTask(taskId);

    // Remove from task details and current progress
    _taskDetails.remove(taskId);
    _currentProgress.remove(taskId);
    _completedTasks.remove(taskId);

    // Remove from queued operations if present
    _queuedOperations.removeWhere((operation) {
      // Since operations are functions, we can't directly identify which one
      // belongs to this taskId. The cleanup above is sufficient since the
      // task won't have any data to work with even if it runs.
      return false;
    });

    return true;
  }
}
