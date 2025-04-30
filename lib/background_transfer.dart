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
