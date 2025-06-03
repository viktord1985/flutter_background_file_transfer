/// Represents a file transfer task with its current state and progress
class TaskTransfer {
  /// Unique identifier for the transfer task
  final String taskId;

  /// Type of transfer ('download' or 'upload')
  final String type;

  /// URL for the transfer (source URL for downloads, destination URL for uploads)
  final String url;

  /// Local file path (destination path for downloads, source path for uploads)
  final String path;

  /// HTTP headers used in the transfer
  final Map<String, String> headers;

  /// Form fields for multipart uploads
  final Map<String, String> fields;

  /// When the transfer was created
  final String createdAt;

  /// Current progress (0.0 to 1.0)
  final double progress;

  /// Current status of the transfer
  final String status;

  TaskTransfer({
    required this.taskId,
    required this.type,
    required this.url,
    required this.path,
    this.headers = const {},
    this.fields = const {},
    required this.createdAt,
    required this.progress,
    required this.status,
  });

  /// Creates a TaskTransfer instance from a map
  factory TaskTransfer.fromMap(Map<String, dynamic> map) {
    return TaskTransfer(
      taskId: map['taskId'] as String,
      type: map['type'] as String,
      url: map['url'] as String,
      path: map['path'] as String,
      headers: Map<String, String>.from(map['headers'] ?? {}),
      fields: Map<String, String>.from(map['fields'] ?? {}),
      createdAt: map['createdAt'] as String,
      progress: (map['progress'] as num).toDouble(),
      status: map['status'] as String,
    );
  }

  /// Converts the TaskTransfer instance to a map
  Map<String, dynamic> toMap() {
    return {
      'taskId': taskId,
      'type': type,
      'url': url,
      'path': path,
      'headers': headers,
      'fields': fields,
      'createdAt': createdAt,
      'progress': progress,
      'status': status,
    };
  }

  @override
  String toString() {
    return 'TaskTransfer(taskId: $taskId, type: $type, url: $url, path: $path, headers: $headers, fields: $fields, createdAt: $createdAt, progress: $progress, status: $status)';
  }
}
