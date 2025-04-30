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
