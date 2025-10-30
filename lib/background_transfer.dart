/// A Flutter plugin for handling background file transfers with progress tracking.
///
/// This plugin provides a high-level interface for uploading and downloading files
/// in the background on both iOS and Android platforms. It handles platform-specific
/// implementations to ensure reliable background transfers that continue even when
/// the app is in the background.
///
/// Features:
/// * Background download and upload operations
/// * Progress tracking through streams
/// * Support for HTTP headers and multipart form fields
/// * Transfer status notifications
/// * Task cancellation
///
/// Platform-specific details:
/// * iOS: Uses URLSession background transfer capabilities
/// * Android: Uses WorkManager for reliable background processing
///
/// Example usage:
/// ```dart
/// final transfer = BackgroundTransfer();
///
/// // Start a download
/// final downloadTaskId = await transfer.startDownload(
///   fileUrl: 'https://example.com/large-file.zip',
///   savePath: '/path/to/save/file.zip',
///   headers: {'Authorization': 'Bearer token'},
/// );
///
/// // Track download progress
/// transfer.getDownloadProgress(downloadTaskId).listen(
///   (progress) => print('Download progress: ${(progress * 100).toStringAsFixed(1)}%'),
///   onDone: () => print('Download complete!'),
///   onError: (error) => print('Download failed: $error'),
/// );
///
/// // Start an upload
/// final uploadTaskId = await transfer.startUpload(
///   filePath: '/path/to/file.pdf',
///   uploadUrl: 'https://example.com/upload',
///   headers: {'Authorization': 'Bearer token'},
///   fields: {'title': 'My Document'},
/// );
///
/// // Track upload progress
/// transfer.getUploadProgress(uploadTaskId).listen(
///   (progress) => print('Upload progress: ${(progress * 100).toStringAsFixed(1)}%'),
///   onDone: () => print('Upload complete!'),
///   onError: (error) => print('Upload failed: $error'),
/// );
///
/// // Cancel a transfer if needed
/// await transfer.cancelTask(taskId);
/// ```
///
/// See also:
/// * [FileTransferHandler] - The interface implemented by platform-specific handlers
/// * [AndroidFileTransferHandler] - Android-specific implementation
/// * [IosFileTransferHandler] - iOS-specific implementation
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:background_transfer/file_transfer_handler.dart';
import 'package:background_transfer/file_transfer_handler_android.dart';
import 'package:background_transfer/file_transfer_handler_ios.dart';
import 'package:background_transfer/file_transfer_handler_mock.dart' as mock;

export 'file_transfer_handler.dart' show FileTransferHandler;

/// Get the platform-specific implementation of FileTransferHandler
FileTransferHandler getBackgroundTransfer() {
  if (kDebugMode && Platform.environment.containsKey('FLUTTER_TEST')) {
    return mock.MockFileTransferHandler();
  } else if (Platform.isAndroid) {
    return AndroidFileTransferHandler();
  } else if (Platform.isIOS) {
    return IosFileTransferHandler();
  }
  throw UnsupportedError(
      'Background transfer is not supported on this platform.');
}

/// The type of transfer operation
enum TransferType {
  /// A download operation from a remote URL to local storage
  download,

  /// An upload operation from local storage to a remote URL
  upload
}

/// The current status of a transfer task
enum TransferStatus {
  /// Task is actively being processed
  active,

  /// Task is waiting in the queue
  queued,

  /// Task has completed successfully
  completed,

  /// Task has failed
  failed,

  /// Task has canceled
  cancelled
}

/// Represents a file transfer task with its metadata and status
class TaskTransfer {
  /// All fields of the transfer task, including standard and custom fields
  final Map<String, dynamic> fields;

  /// Creates a new [TaskTransfer] instance
  TaskTransfer({
    required String taskId,
    required TransferType type,
    required String url,
    required String path,
    required DateTime createdAt,
    required double progress,
    required TransferStatus status,
    required int? code,
    Map<String, dynamic>? fields,
  }) : fields = {
          'taskId': taskId,
          'type': type.name,
          'url': url,
          'path': path,
          'createdAt': createdAt.toIso8601String(),
          'progress': progress,
          'status': status.name,
          'code': code,
          if (fields != null) ...fields, // Include all provided fields
        };

  /// Creates a [TaskTransfer] from a JSON map
  factory TaskTransfer.fromJson(Map<String, dynamic> json) {
    // Don't filter out any fields, keep them all
    return TaskTransfer(
      taskId: json['taskId']?.toString() ?? '', // Handle both String and int
      type: TransferType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => TransferType.download,
      ),
      url: json['url'] as String,
      path: json['path'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      progress: (json['progress'] as num).toDouble(),
      status: TransferStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => TransferStatus.queued,
      ),
      code: json['code'] as int?,
      fields: Map<String, dynamic>.from(
          json), // Create a new map to ensure type safety
    );
  }

  /// Converts this task to a JSON map
  Map<String, dynamic> toJson() => fields;

  /// Get a value from fields by key
  dynamic operator [](String key) => fields[key];

  /// Check if a field exists
  bool hasField(String key) => fields.containsKey(key);

  /// Get all field names
  Set<String> get allFields => fields.keys.toSet();

  /// Creates a copy of this TaskTransfer with optional changes
  TaskTransfer copyWith({
    String? taskId,
    TransferType? type,
    String? url,
    String? path,
    DateTime? createdAt,
    double? progress,
    TransferStatus? status,
    int? code,
    Map<String, dynamic>? additionalFields,
  }) {
    return TaskTransfer(
      taskId: taskId ?? this.taskId,
      type: type ?? this.type,
      url: url ?? this.url,
      path: path ?? this.path,
      createdAt: createdAt ?? this.createdAt,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      code: code ?? this.code,
      fields: Map.from(fields)
        ..removeWhere((key, _) => {
              'taskId',
              'type',
              'url',
              'path',
              'createdAt',
              'progress',
              'status',
              'code'
            }.contains(key)),
    );
  }

  /// Unique identifier for this task
  String get taskId => fields['taskId'] as String;

  /// The type of transfer (download or upload)
  TransferType get type => TransferType.values.firstWhere(
        (t) => t.name == fields['type'],
        orElse: () => TransferType.download,
      );

  /// The URL of the remote resource
  String get url => fields['url'] as String;

  /// The local file path
  String get path => fields['path'] as String;

  /// When the task was created
  DateTime get createdAt => DateTime.parse(fields['createdAt'] as String);

  /// Current progress (0.0 to 1.0)
  double get progress => (fields['progress'] as num).toDouble();

  int? get code => fields['code'] as int?;

  /// Current status of the task
  TransferStatus get status => TransferStatus.values.firstWhere(
        (s) => s.name == fields['status'],
        orElse: () => TransferStatus.queued,
      );
}

class BackgroundTransfer {
  static final FileTransferHandler _handler = getBackgroundTransfer();
  static final _transferStreamController =
      StreamController<List<TaskTransfer>>.broadcast();
  static Timer? _updateTimer;

  static Stream<List<TaskTransfer>> get transferStream {
    // Start periodic updates if not already started
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      getQueuedTransfers().then((transfers) {
        if (!_transferStreamController.isClosed) {
          _transferStreamController.add(transfers);
        }
      });
    });

    // Initial data
    getQueuedTransfers().then((transfers) {
      if (!_transferStreamController.isClosed) {
        _transferStreamController.add(transfers);
      }
    });

    return _transferStreamController.stream;
  }

  /// Clean up resources
  static void dispose() {
    _updateTimer?.cancel();
    _transferStreamController.close();
  }

  /// Configure the transfer queue behavior
  static Future<void> configureQueue({
    required bool isEnabled,
    int maxConcurrent = 1,
    double cleanupDelay = 0,
  }) async {
    await _handler.configureQueue(
        isEnabled: isEnabled,
        maxConcurrent: maxConcurrent,
        cleanupDelay: cleanupDelay);
  }

  /// Start a download task
  static Future<String> startDownload({
    required String fileUrl,
    required String savePath,
    Map<String, String> headers = const {},
  }) async {
    return await _handler.startDownload(
      fileUrl: fileUrl,
      savePath: savePath,
      headers: headers,
    );
  }

  /// Get a stream of progress updates for a download task
  static Stream<double> getDownloadProgress(String taskId) {
    return _handler.getDownloadProgress(taskId);
  }

  /// Check if a download task is complete
  static Future<bool> isDownloadComplete(String taskId) async {
    return await _handler.isDownloadComplete(taskId);
  }

  /// Start an upload task
  static Future<String> startUpload({
    required String filePath,
    required String uploadUrl,
    Map<String, String> headers = const {},
    Map<String, String> fields = const {},
  }) async {
    return await _handler.startUpload(
      filePath: filePath,
      uploadUrl: uploadUrl,
      headers: headers,
      fields: fields,
    );
  }

  /// Get a stream of progress updates for an upload task
  static Stream<double> getUploadProgress(String taskId) {
    return _handler.getUploadProgress(taskId);
  }

  /// Get a stream of progress updates for an upload task
  static Stream<int> getResultStatus(String taskId) {
    return _handler.getResultStatus(taskId);
  }

  /// Check if an upload task is complete
  static Future<bool> isUploadComplete(String taskId) async {
    return await _handler.isUploadComplete(taskId);
  }

  /// Cancel a transfer task
  static Future<bool> cancelTask(String taskId) async {
    return await _handler.cancelTask(taskId);
  }

  /// Delete a task from the queue and clean up associated resources
  ///
  /// This will:
  /// 1. Remove it from the queue
  /// 2. Clean up associated resources
  /// 3. Remove it from the transfer history
  ///
  /// Returns true if the task was successfully deleted, false if the task wasn't found
  static Future<bool> deleteTask(String taskId) async {
    return await _handler.deleteTask(taskId);
  }

  /// Get details about the current queue status
  ///
  /// Returns a Map containing:
  /// - isEnabled: whether queue is enabled
  /// - maxConcurrent: maximum number of concurrent transfers
  /// - activeCount: number of currently active transfers
  /// - queuedCount: number of transfers waiting in queue
  static Future<Map<String, dynamic>> getQueueStatus() async {
    return await _handler.getQueueStatus();
  }

  /// Get list of queued transfers with their details
  ///
  /// Returns a List of [TaskTransfer] objects containing:
  /// - taskId: unique identifier of the transfer
  /// - type: download or upload
  /// - status: active, queued, completed, cancelled or failed
  /// - progress: current progress (0.0 to 1.0)
  /// - url: source URL for downloads or destination URL for uploads
  /// - path: local file path
  /// - createdAt: when the transfer was created
  static Future<List<TaskTransfer>> getQueuedTransfers() async {
    final transfers = await _handler.getQueuedTransfers();
    return transfers.map((t) => TaskTransfer.fromJson(t)).toList();
  }
}
