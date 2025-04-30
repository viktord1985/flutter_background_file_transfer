import 'dart:io';

import 'package:background_transfer/background_transfer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: FileTransferDemo());
  }
}

class FileTransferDemo extends StatefulWidget {
  const FileTransferDemo({super.key});

  @override
  State<FileTransferDemo> createState() => _FileTransferDemoState();
}

class _FileTransferDemoState extends State<FileTransferDemo>
    with WidgetsBindingObserver {
  final taskHandler = getBackgroundTransfer();
  final Set<String> activeTasks = {};
  final Map<String, String> activeDownloadUrls =
      {}; // Track URLs being downloaded
  final Map<String, String> activeUploadPaths =
      {}; // Track files being uploaded
  double downloadProgress = 0;
  double uploadProgress = 0;
  String? downloadStatus;
  String? uploadStatus;
  File? selectedFile;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.detached) {
      // Only cancel tasks when app is being terminated
      cancelAllTasks();
    } else if (state == AppLifecycleState.resumed) {
      // Restore progress tracking for active tasks
      for (final taskId in activeTasks) {
        if (activeUploadPaths.containsKey(taskId)) {
          // Resubscribe to upload progress
          taskHandler
              .getUploadProgress(taskId)
              .listen(
                (progress) {
                  setState(() {
                    uploadProgress = progress;
                    uploadStatus =
                        'Background upload: ${(progress * 100).toStringAsFixed(1)}%';
                  });
                },
                onError: (error) {
                  activeTasks.remove(taskId);
                  activeUploadPaths.remove(taskId);
                  setState(() {
                    uploadStatus = 'Background upload failed: $error';
                  });
                },
                onDone: () {
                  activeTasks.remove(taskId);
                  activeUploadPaths.remove(taskId);
                  setState(() {
                    uploadStatus = 'Background upload completed!';
                  });
                },
              );
        } else if (activeDownloadUrls.containsKey(taskId)) {
          // Resubscribe to download progress
          taskHandler
              .getDownloadProgress(taskId)
              .listen(
                (progress) {
                  setState(() {
                    downloadProgress = progress;
                    downloadStatus =
                        'Background download: ${(progress * 100).toStringAsFixed(1)}%';
                  });
                },
                onError: (_) {
                  activeTasks.remove(taskId);
                  activeDownloadUrls.remove(taskId);
                },
                onDone: () {
                  activeTasks.remove(taskId);
                  activeDownloadUrls.remove(taskId);
                  setState(() {
                    downloadStatus = 'Background download completed!';
                  });
                },
              );
        }
      }
    }
  }

  Future<void> pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );

    if (result != null) {
      setState(() {
        selectedFile = File(result.files.single.path!);
      });
    }
  }

  Future<void> cancelAllTasks() async {
    for (final taskId in activeTasks) {
      await taskHandler.cancelTask(taskId);
    }
    activeTasks.clear();
    activeDownloadUrls.clear();
    activeUploadPaths.clear();
  }

  bool isDownloadingUrl(String url) {
    return activeDownloadUrls.containsValue(url);
  }

  String getUniqueFilename(String basePath) {
    final file = File(basePath);
    final dir = file.parent;
    final basename = file.uri.pathSegments.last;
    final nameWithoutExt = basename.substring(0, basename.lastIndexOf('.'));
    final extension = basename.substring(basename.lastIndexOf('.'));

    var index = 1;
    var newPath = basePath;
    while (File(newPath).existsSync()) {
      newPath = '${dir.path}/$nameWithoutExt($index)$extension';
      index++;
    }
    return newPath;
  }

  Future<void> downloadInBackground() async {
    final controller = TextEditingController();
    // Default URL for testing
    final fileUrl = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Enter Download URL'),
            content: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'https://example.com/file.pdf',
              ),
              onSubmitted: (value) => Navigator.of(context).pop(value),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(controller.text),
                child: Text('Download'),
              ),
            ],
          ),
    );

    if (fileUrl == null || fileUrl.isEmpty) return;

    if (isDownloadingUrl(fileUrl)) {
      setState(() {
        downloadStatus = 'This file is already being downloaded';
      });
      return;
    }

    setState(() {
      downloadStatus = 'Starting background download...';
      downloadProgress = 0;
    });

    try {
      final dir = await getApplicationDocumentsDirectory();
      final filename = fileUrl.split('/').last;
      final basePath = '${dir.path}/$filename';
      final uniquePath = getUniqueFilename(basePath);

      final taskId = await taskHandler.startDownload(
        fileUrl: fileUrl,
        savePath: uniquePath,
        headers: {'Accept': '*/*'},
      );

      activeTasks.add(taskId);
      activeDownloadUrls[taskId] = fileUrl;

      taskHandler
          .getDownloadProgress(taskId)
          .listen(
            (progress) {
              setState(() {
                downloadProgress = progress;
                downloadStatus =
                    'Background download: ${(progress * 100).toStringAsFixed(1)}%';
              });
            },
            onError: (error) {
              activeTasks.remove(taskId);
              activeDownloadUrls.remove(taskId);
              setState(() {
                downloadStatus = 'Background download failed: $error';
              });
            },
            onDone: () {
              activeTasks.remove(taskId);
              activeDownloadUrls.remove(taskId);
              setState(() {
                downloadStatus = 'Background download completed!';
              });
            },
          );

      while (!(await taskHandler.isDownloadComplete(taskId))) {
        await Future.delayed(const Duration(seconds: 1));
      }

      activeTasks.remove(taskId);
      activeDownloadUrls.remove(taskId);
      setState(() {
        downloadStatus = 'Background download completed!';
      });
    } catch (e) {
      setState(() {
        downloadStatus = 'Background download failed: $e';
      });
    }
  }

  Future<void> uploadInBackground() async {
    if (selectedFile == null) return;

    // Ensure we have a valid file path
    final file = File(selectedFile!.path);
    if (!await file.exists()) {
      setState(() {
        uploadStatus = 'Error: File does not exist';
      });
      return;
    }

    // Check if file is already being uploaded
    if (activeUploadPaths.containsValue(file.path)) {
      setState(() {
        uploadStatus = 'This file is already being uploaded';
      });
      return;
    }

    final controller = TextEditingController();
    final uploadUrl = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Enter Upload URL'),
            content: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'https://example.com/upload',
              ),
              onSubmitted: (value) => Navigator.of(context).pop(value),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(controller.text),
                child: Text('Upload'),
              ),
            ],
          ),
    );

    if (uploadUrl == null ||
        uploadUrl.isEmpty ||
        !uploadUrl.startsWith('http')) {
      setState(() {
        uploadStatus =
            'Error: Invalid URL (must start with http:// or https://)';
      });
      return;
    }

    setState(() {
      uploadStatus = 'Starting background upload...';
      uploadProgress = 0;
    });

    String? taskId;
    StreamSubscription? subscription;

    try {
      taskId = await taskHandler.startUpload(
        filePath: file.absolute.path,
        uploadUrl: uploadUrl,
        headers: {
          'Accept': '*/*',    },
      );

      activeTasks.add(taskId);
      activeUploadPaths[taskId] = file.path;

      // Create a completer to handle upload completion
      final completer = Completer<void>();

      // Listen to upload progress
      subscription = taskHandler
          .getUploadProgress(taskId)
          .listen(
            (progress) {
              setState(() {
                uploadProgress = progress;
                uploadStatus =
                    'Background upload: ${(progress * 100).toStringAsFixed(1)}%';

                // If we reach 100%, consider the upload complete
                if (progress >= 1.0) {
                  uploadStatus = 'Background upload completed!';
                  completer.complete();
                }
              });
            },
            onError: (error) {
              activeTasks.remove(taskId);
              activeUploadPaths.remove(taskId);
              setState(() {
                uploadStatus = 'Background upload failed: $error';
                uploadProgress = 0;
              });
              if (!completer.isCompleted) {
                completer.completeError(error);
              }
            },
            onDone: () {
              activeTasks.remove(taskId);
              activeUploadPaths.remove(taskId);
              if (!completer.isCompleted) {
                completer.complete();
              }
            },
          );

      // Wait for upload completion
      try {
        await completer.future;
      } finally {
        await subscription.cancel();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Upload exception: $e');
      }
      activeTasks.remove(taskId);
      activeUploadPaths.remove(taskId);
      setState(() {
        uploadStatus = 'Background upload failed: $e';
        uploadProgress = 0;
      });
      await subscription?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('File Transfer Plugin Demo')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Download Section
            const Text(
              'Download',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: downloadProgress),
            const SizedBox(height: 8),
            Text(downloadStatus ?? 'Not started'),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: downloadInBackground,
              child: const Text('Download in Background'),
            ),

            const Divider(height: 32),

            // Upload Section
            const Text(
              'Upload',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    selectedFile?.path ?? 'No file selected',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: pickFile,
                  child: const Text('Select File'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: uploadProgress),
            const SizedBox(height: 8),
            Text(uploadStatus ?? 'Not started'),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: selectedFile != null ? uploadInBackground : null,
              child: const Text('Upload in Background'),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
