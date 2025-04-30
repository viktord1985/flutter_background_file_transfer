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
- Concurrent transfer support
- Transfer cancellation support
- Lifecycle-aware progress tracking

## Getting Started

Add this to your package's pubspec.yaml file:

```yaml
dependencies:
  background_transfer: ^0.0.1
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

## Notes

- Files are downloaded and uploaded in the background, allowing transfers to continue even when the app is in the background
- Progress notifications are shown on both platforms
- The plugin automatically handles lifecycle changes and restores progress tracking when the app is resumed
- Concurrent transfers are supported and tracked independently
- MIME types are automatically detected based on file extensions

