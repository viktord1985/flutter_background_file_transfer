import 'dart:io';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:background_transfer/background_transfer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late FileTransferHandler transfer;
  late Directory tempDir;
  final mockDownloadUrl = 'http://example.com/test.txt';
  final mockUploadUrl = 'http://example.com/upload';
  
  setUpAll(() async {
    tempDir = await getTemporaryDirectory();
  });

  setUp(() async {
    transfer = getBackgroundTransfer();
    debugPrint('Using temp directory: ${tempDir.path}');
  });

  tearDown(() async {
    // Clean up any files created during the test
    final dir = Directory(tempDir.path);
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.txt')) {
          await entity.delete();
        }
      }
    }
  });

  // Test Download
  testWidgets('Download file and track progress', (WidgetTester tester) async {
    final savePath = '${tempDir.path}/test_download.txt';
    String? taskId;
    StreamSubscription? progressSubscription;

    try {
      debugPrint('Starting download test...');
      debugPrint('Save path: $savePath');

      // Ensure the file doesn't exist before starting
      final file = File(savePath);
      if (await file.exists()) {
        await file.delete();
      }

      taskId = await transfer.startDownload(
        fileUrl: mockDownloadUrl,
        savePath: savePath,
        headers: {'Accept': 'text/plain'},
      );

      debugPrint('Got taskId: $taskId');
      expect(taskId, isNotEmpty);

      // Track progress with timeout
      final progressCompleter = Completer<void>();
      double lastProgress = 0;
      Timer? timeoutTimer;

      timeoutTimer = Timer(const Duration(seconds: 60), () {
        if (!progressCompleter.isCompleted) {
          progressCompleter.completeError(TimeoutException('Download timed out'));
        }
        progressSubscription?.cancel();
      });

      progressSubscription = transfer.getDownloadProgress(taskId).listen(
        (progress) {
          expect(progress, greaterThanOrEqualTo(lastProgress));
          expect(progress, inInclusiveRange(0.0, 1.0));
          lastProgress = progress;
          if (progress >= 1.0 && !progressCompleter.isCompleted) {
            progressCompleter.complete();
          }
        },
        onDone: () {
          if (!progressCompleter.isCompleted) {
            progressCompleter.complete();
          }
        },
        onError: (error) {
          if (!progressCompleter.isCompleted) {
            progressCompleter.completeError(error);
          }
        },
      );

      // Wait for download to complete
      try {
        await progressCompleter.future;
        await Future.delayed(const Duration(seconds: 2));
        expect(await file.exists(), isTrue);
        expect(await file.readAsString(), isNotEmpty);
      } finally {
        timeoutTimer.cancel();
        await progressSubscription.cancel();
      }

    } catch (e) {
      debugPrint('Test failed with error: $e');
      if (taskId != null) {
        await transfer.cancelTask(taskId);
      }
      rethrow;
    }
  });

  testWidgets('Download with invalid URL fails', (WidgetTester tester) async {
    final savePath = '${tempDir.path}/test_download_fail.txt';
    String? taskId;
    
    try {
      taskId = await transfer.startDownload(
        fileUrl: 'http://invalid.example.com/test.txt',
        savePath: savePath,
      );
      
      expect(taskId, isNotEmpty);
      
      // Expect the download progress to throw an error
      expect(
        transfer.getDownloadProgress(taskId),
        emitsError(isA<Exception>()),
      );
    } finally {
      if (taskId != null) {
        await transfer.cancelTask(taskId);
      }
    }
  });

  // Test Upload
  testWidgets('Upload file and track progress', (WidgetTester tester) async {
    final uploadFilePath = '${tempDir.path}/test_upload.txt';
    String? taskId;
    StreamSubscription? progressSubscription;

    try {
      // Create a test file
      final file = File(uploadFilePath);
      await file.writeAsString('Test content for upload');

      taskId = await transfer.startUpload(
        filePath: uploadFilePath,
        uploadUrl: mockUploadUrl,
        headers: {'Content-Type': 'multipart/form-data'},
        fields: {'type': 'test'},
      );

      expect(taskId, isNotEmpty);

      // Track progress
      final progressCompleter = Completer<void>();
      double lastProgress = 0;
      Timer? timeoutTimer;

      timeoutTimer = Timer(const Duration(seconds: 60), () {
        if (!progressCompleter.isCompleted) {
          progressCompleter.completeError(TimeoutException('Upload timed out'));
        }
        progressSubscription?.cancel();
      });

      progressSubscription = transfer.getUploadProgress(taskId).listen(
        (progress) {
          expect(progress, greaterThanOrEqualTo(lastProgress));
          expect(progress, inInclusiveRange(0.0, 1.0));
          lastProgress = progress;
          if (progress >= 1.0 && !progressCompleter.isCompleted) {
            progressCompleter.complete();
          }
        },
        onDone: () {
          if (!progressCompleter.isCompleted) {
            progressCompleter.complete();
          }
        },
        onError: (error) {
          if (!progressCompleter.isCompleted) {
            progressCompleter.completeError(error);
          }
        },
      );

      try {
        await progressCompleter.future;
        expect(await transfer.isUploadComplete(taskId), isTrue);
      } finally {
        timeoutTimer.cancel();
        await progressSubscription.cancel();
      }

    } catch (e) {
      debugPrint('Test failed with error: $e');
      if (taskId != null) {
        await transfer.cancelTask(taskId);
      }
      rethrow;
    }
  });

  // Test Cancel Tasks
  testWidgets('Cancel tasks', (WidgetTester tester) async {
    final uploadFilePath = '${tempDir.path}/test_upload_cancel.txt';
    final downloadFilePath = '${tempDir.path}/test_download_cancel.txt';
    String? uploadTaskId;
    String? downloadTaskId;

    try {
      // Test upload cancellation
      final uploadFile = File(uploadFilePath);
      await uploadFile.writeAsString('Test content for cancelled upload');
      
      uploadTaskId = await transfer.startUpload(
        filePath: uploadFilePath,
        uploadUrl: mockUploadUrl,
        headers: {'Content-Type': 'multipart/form-data'},
      );

      await Future.delayed(const Duration(milliseconds: 500));
      expect(await transfer.cancelTask(uploadTaskId), isTrue);

      // Test download cancellation
      downloadTaskId = await transfer.startDownload(
        fileUrl: mockDownloadUrl,
        savePath: downloadFilePath,
      );

      await Future.delayed(const Duration(milliseconds: 500));
      expect(await transfer.cancelTask(downloadTaskId), isTrue);

      // Test cancelling non-existent task
      expect(await transfer.cancelTask('non-existent-task'), isFalse);
    } finally {
      // Cleanup
      for (final path in [uploadFilePath, downloadFilePath]) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
    }
  });
}
