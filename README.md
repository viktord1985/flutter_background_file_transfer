# Background Transfer Plugin

A Flutter plugin for handling background file transfers (uploads and downloads) with progress tracking and notifications support. Works on both iOS and Android platforms.

## Features

- Background file downloads with progress tracking
- Background file uploads with progress tracking
- Support for any file type (images, videos, documents, etc.)
- Progress notifications on both platforms
- Multipart form data upload support
- Custom headers support
- Automatic MIME type detection
- Built-in native queue management system (can be disabled)
  - Configurable concurrent transfer limits
  - Automatic cleanup of completed transfers
  - Task status monitoring and reporting
  - Progress tracking during app session
- Native platform implementations
  - iOS: NSURLSession for background transfer capability
  - Android: WorkManager for background processing
- Lifecycle-aware progress tracking
- Transfer cancellation support
- Clean cancellation and resume functionality (within app session)

## Getting Started

Add this to your package's pubspec.yaml file:

```yaml
dependencies:
  background_transfer: ^1.0.0
```

## Usage

### Initialize the plugin

```dart
final transfer = getBackgroundTransfer();
```

### Download a file

```dart
try {
  final taskId = await transfer.startDownload(
    fileUrl: 'https://example.com/file.pdf',
    savePath: '/path/to/save/file.pdf',
    headers: {
      'Authorization': 'Bearer token',
    },
  );

  // Listen to download progress
  transfer.getDownloadProgress(taskId).listen(
    (progress) {
      print('Download progress: ${(progress * 100).toStringAsFixed(1)}%');
    },
    onDone: () {
      print('Download completed!');
    },
    onError: (error) {
      print('Download failed: $error');
    },
  );
} catch (e) {
  print('Failed to start download: $e');
}
```

### Upload a file

```dart
try {
  final taskId = await transfer.startUpload(
    filePath: '/path/to/file.pdf',
    uploadUrl: 'https://example.com/upload',
    headers: {
      'Authorization': 'Bearer token',
    },
    fields: {
      'title': 'My Document',
      'type': 'pdf',
    },
  );

  // Listen to upload progress
  transfer.getUploadProgress(taskId).listen(
    (progress) {
      print('Upload progress: ${(progress * 100).toStringAsFixed(1)}%');
    },
    onDone: () {
      print('Upload completed!');
    },
    onError: (error) {
      print('Upload failed: $error');
    },
  );
} catch (e) {
  print('Failed to start upload: $e');
}
```

### Cancel a transfer

```dart
final success = await transfer.cancelTask(taskId);
```

### Check transfer completion

```dart
final isComplete = await transfer.isUploadComplete(taskId);
// or
final isComplete = await transfer.isDownloadComplete(taskId);
```

### Queue Management

The plugin provides two approaches to queue management:

1. Native Queue Management (built-in):
```dart
// Configure the native platform queue
await transfer.configureQueue(
  enabled: true,          // Enable/disable native queue management
  maxConcurrent: 3,       // Maximum concurrent transfers when enabled
  cleanupDelay: 5000,    // Delay before removing completed transfers (ms)
);

// If you prefer to handle queuing in Dart (e.g., using BLoC pattern),
// you can disable the native queue:
await transfer.configureQueue(enabled: false);

// Get queue status
final status = await transfer.getQueueStatus();
print('Active transfers: ${status.activeCount}');
print('Queued transfers: ${status.queuedCount}');

// Get all transfers in queue
final transfers = await transfer.getQueuedTransfers();
for (final task in transfers) {
  print('Task ${task.taskId}: ${task.status} (${task.progress * 100}%)');
}
```

## Platform Support

| Android | iOS |
|---------|-----|
| ✅      | ✅  |

## Android Setup

Add the following permissions to your AndroidManifest.xml:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

For Android 13 (API level 33) and above, you'll also need to request runtime permissions:

```dart
// Request notification permission for Android 13+
if (Platform.isAndroid) {
  final status = await Permission.notification.request();
  print('Notification permission status: $status');
}
```

## iOS Setup

1. Add the following keys to your Info.plist file:

```xml
<!-- Background download/upload support -->
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>processing</string>
    <string>remote-notification</string>
</array>

<!-- Notification support -->
<key>UNUserNotificationCenter</key>
<string>YES</string>
<key>NSUserNotificationAlertStyle</key>
<string>banner</string>

<!-- Privacy descriptions -->
<key>NSPhotoLibraryUsageDescription</key>
<string>Access to photo library is required for uploading images</string>
<key>NSDocumentsFolderUsageDescription</key>
<string>Access to documents is required for file transfers</string>
```

2. For iOS 15 and above, to enable background download/upload capabilities, add this to your AppDelegate:

```swift
if #available(iOS 15.0, *) {
    BGTaskScheduler.shared.register(
        forTaskWithIdentifier: "com.yourapp.transfer",
        using: nil
    ) { task in
        // Handle background task
        task.setTaskCompleted(success: true)
    }
}
```

## Advanced Usage: Implementing Queue Management

The plugin provides basic transfer capabilities with a built-in native queue management system. However, you might want to implement your own queue management at the Dart level for more control. Here's a suggested implementation using BLoC pattern that provides:

- Custom queuing logic with full control over the transfer order
- Persistence of the queue state using HydratedBloc (survives app restarts, but see note below about file persistence)
- UI state management for transfer progress and status
- Custom error handling and retry logic

Note: When implementing your own queue management, it's recommended to disable the native queue using `configureQueue(enabled: false)` to avoid conflicts.

```dart
// transfer_bloc.dart
class TransferBloc extends HydratedBloc<TransferEvent, TransferState> {
  final FileTransferHandler transfer;
  StreamSubscription<double>? _progressSub;

  TransferBloc(this.transfer) : super(const TransferState()) {
    on<AddTransferTask>(_onAddTransferTask);
    on<StartNextTransfer>(_onStartNextTransfer);
    on<TransferProgressUpdated>(_onTransferProgressUpdated);
    on<TransferCompleted>(_onTransferCompleted);
    on<CancelTransfer>(_onCancelTransfer);
    on<ResumeTransfer>(_onResumeTransfer);
  }

  void _onResumeTransfer(ResumeTransfer event, Emitter<TransferState> emit) {
    final task = state.activeTask;
    if (task != null && task.taskId == null) {
      final newQueue = state.queue;
      emit(TransferState(
        queue: newQueue,
        activeTask: null,
      ));
      add(StartNextTransfer());
      return;
    }
    if (task == null) return;

    _progressSub = (task.isUpload 
      ? transfer.getUploadProgress(task.taskId!)
      : transfer.getDownloadProgress(task.taskId!)).listen(
        (progress){},
        onDone: () => add(TransferCompleted()),
        onError: (_) => add(TransferCompleted()),
        cancelOnError: true,
      );
  }

  void _onAddTransferTask(AddTransferTask event, Emitter<TransferState> emit) {
    List<TransferTask> updatedQueue = List<TransferTask>.from(state.queue)
      ..add(event.task);
    final shouldStartTransfer = state.activeTask == null;
    final newState = TransferState(
      queue: updatedQueue,
      activeTask: state.activeTask,
    );
    emit(newState);

    if (shouldStartTransfer) {
      add(StartNextTransfer());
    }
  }

  void _onStartNextTransfer(StartNextTransfer event, Emitter<TransferState> emit) async {
    if (state.activeTask != null || state.queue.isEmpty) return;

    final nextTask = state.queue.first;
    final newQueue = state.queue.sublist(1);

    emit(TransferState(
      queue: newQueue,
      activeTask: nextTask,
    ));

    try {
      String? taskId = nextTask.isUpload
          ? await transfer.startUpload(
              filePath: nextTask.path,
              uploadUrl: nextTask.url,
              headers: nextTask.headers,
              fields: nextTask.fields,
            )
          : await transfer.startDownload(
              fileUrl: nextTask.url,
              savePath: nextTask.path,
              headers: nextTask.headers,
            );

      final updatedTask = nextTask.copyWith(taskId: taskId);

      emit(TransferState(
        queue: newQueue,
        activeTask: updatedTask,
      ));

      _progressSub = (nextTask.isUpload 
        ? transfer.getUploadProgress(taskId!)
        : transfer.getDownloadProgress(taskId!)).listen(
          (progress){},
          onDone: () => add(TransferCompleted()),
          onError: (_) => add(TransferCompleted()),
          cancelOnError: true,
        );
    } catch (_) {
      emit(TransferState(
        queue: newQueue,
        activeTask: null,
      ));
      add(StartNextTransfer());
    }
  }

  void _onTransferProgressUpdated(
      TransferProgressUpdated event, Emitter<TransferState> emit) {
    if (state.activeTask == null) return;
    emit(state.copyWith(
      activeTask: state.activeTask!.copyWith(progress: event.progress),
    ));
  }

  void _onTransferCompleted(TransferCompleted event, Emitter<TransferState> emit) {
    _progressSub?.cancel();
    emit(state.copyWith(activeTask: null));
    add(StartNextTransfer());
  }

  void _onCancelTransfer(CancelTransfer event, Emitter<TransferState> emit) {
    if (state.activeTask?.taskId == event.taskId) {
      transfer.cancelTask(event.taskId);
      _progressSub?.cancel();
      emit(state.copyWith(activeTask: null));
      add(StartNextTransfer());
    }
  }

  @override
  Future<void> close() {
    _progressSub?.cancel();
    return super.close();
  }

  @override
  TransferState? fromJson(Map<String, dynamic> json) {
    try {
      final state = TransferState.fromJson(json);
      if (state.activeTask != null) {
        add(ResumeTransfer());
      }
      return state;
    } catch (e) {
      return null;
    }
  }

  @override
  Map<String, dynamic>? toJson(TransferState state) {
    try {
      return state.toJson();
    } catch (e) {
      return null;
    }
  }
}





// transfer_event.dart
abstract class TransferEvent {}

class AddTransferTask extends TransferEvent {
  final TransferTask task;
  AddTransferTask(this.task);
}

class StartNextTransfer extends TransferEvent {}

class TransferProgressUpdated extends TransferEvent {
  final double progress;
  TransferProgressUpdated(this.progress);
}

class TransferCompleted extends TransferEvent {}

class ResumeTransfer extends TransferEvent {}

class CancelTransfer extends TransferEvent {
  final String taskId;
  CancelTransfer(this.taskId);
}

// transfer_state.dart
class TransferState {
  final List<TransferTask> queue;
  final TransferTask? activeTask;

  const TransferState({
    this.queue = const [],
    this.activeTask,
  });

  TransferState copyWith({
    List<TransferTask>? queue,
    TransferTask? activeTask,
  }) {
    return TransferState(
      queue: queue ?? this.queue,
      activeTask: activeTask ?? this.activeTask,
    );
  }

  factory TransferState.fromJson(Map<String, dynamic> json) {
    return TransferState(
      queue: (json['queue'] as List<dynamic>)
          .map((e) => TransferTask.fromJson(e))
          .toList(),
      activeTask: json['activeTask'] != null
          ? TransferTask.fromJson(json['activeTask'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'queue': queue.map((e) => e.toJson()).toList(),
      'activeTask': activeTask?.toJson(),
    };
  }
}

// Enhanced TransferTask with progress
class TransferTask {
  final String id;
  final String path;     // filePath for upload, savePath for download
  final String url;      // uploadUrl for upload, fileUrl for download
  final Map<String, String> headers;
  final Map<String, String> fields;
  final String? taskId;
  final bool isUpload;

  TransferTask({
    required this.id,
    required this.path,
    required this.url,
    required this.headers,
    required this.isUpload,
    this.fields = const {},
    this.taskId,
  });

  TransferTask copyWith({
    String? id,
    String? path,
    String? url,
    Map<String, String>? headers,
    Map<String, String>? fields,
    String? taskId,
    bool? isUpload,
  }) {
    return TransferTask(
      id: id ?? this.id,
      path: path ?? this.path,
      url: url ?? this.url,
      headers: headers ?? this.headers,
      fields: fields ?? this.fields,
      taskId: taskId ?? this.taskId,
      isUpload: isUpload ?? this.isUpload,
    );
  }

  factory TransferTask.fromJson(Map<String, dynamic> json) {
    return TransferTask(
      id: json['id'],
      path: json['path'],
      url: json['url'],
      headers: Map<String, String>.from(json['headers']),
      fields: Map<String, String>.from(json['fields'] ?? {}),
      taskId: json['taskId'],
      isUpload: json['isUpload'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'path': path,
      'url': url,
      'headers': headers,
      'fields': fields,
      'taskId': taskId,
      'isUpload': isUpload,
    };
  }
}
```

### Using the Transfer Queue

First, wrap your app with BlocProvider to make the TransferBloc available throughout your widget tree:

```dart
void main() {
  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider<TransferBloc>(
          create: (context) => TransferBloc(getBackgroundTransfer()),
        ),
      ],
      child: MyApp(),
    ),
  );
}
```

Then you can access the bloc from any widget:

```dart
// Get the bloc instance
final transferBloc = context.read<TransferBloc>();

// Add a download task
transferBloc.add(AddTransferTask(
  TransferTask(
    id: 'unique_id',
    path: '/path/to/save/file.pdf',
    url: 'https://example.com/file.pdf',
    headers: {'Authorization': 'Bearer token'},
    isUpload: false,
  ),
));

// Add an upload task
transferBloc.add(AddTransferTask(
  TransferTask(
    id: 'unique_id',
    path: '/path/to/file.pdf',
    url: 'https://example.com/upload',
    headers: {'Authorization': 'Bearer token'},
    fields: {'title': 'My Document'},
    isUpload: true,
  ),
));

// Listen to state changes
StreamBuilder<TransferState>(
  stream: transferBloc.stream,
  builder: (context, snapshot) {
    // Build your UI based on the state
    return // Your widget tree...
  },
);
```

This queue implementation example provides:
- One transfer at a time to prevent bandwidth competition
- Persistent task queue across app restarts (using HydratedBloc)
- Proper error handling and retry mechanisms
- Clean cancellation and resume functionality
- Progress tracking for the active transfer

Note: This is just one way to implement queuing. You can adapt this example or create your own implementation based on your specific needs.

## Notes

Note about file persistence: When uploading files, be aware that if the files are stored in temporary locations (like cache directories or temporary folders), these files might be deleted by the system when the app is completely terminated. Therefore, persisting transfer tasks across complete app restarts is not recommended as the source files might no longer be available when the app restarts. It's better to handle file persistence separately from transfer queue management.

- Files are downloaded and uploaded in the background, allowing transfers to continue even when the app is in the background
- Progress notifications are shown on both platforms
- The plugin automatically handles lifecycle changes and restores progress tracking when the app is resumed
- Concurrent transfers are supported and tracked independently
- MIME types are automatically detected based on file extensions

## Upcoming Features

Future versions will include:
- Advanced retry strategies with exponential backoff
  - Configurable retry attempts with customizable delays
  - Intelligent retry based on error type (network, server, etc.)
  - Exponential backoff with jitter for distributed systems
  - Per-task retry configuration
  - Resume capability for interrupted transfers
- Bandwidth throttling options
- Transfer prioritization
- Network type restrictions (WiFi only, etc.)
- More granular progress reporting

Note: While the plugin uses NSURLSession (iOS) and WorkManager (Android) for background transfers, it does not include queue management. The upcoming feature will provide native example implementations to help developers implement queue management in their preferred way, either at the Dart level (as shown in the Advanced Usage section) or directly in native code.

