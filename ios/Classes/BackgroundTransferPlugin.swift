import Flutter
import UIKit
import os.log
import UserNotifications

private let logger = OSLog(subsystem: "dev.sylvestre.background_transfer", category: "Plugin")

public class BackgroundTransferPlugin: NSObject, FlutterPlugin, URLSessionTaskDelegate, URLSessionDownloadDelegate, UNUserNotificationCenterDelegate {
    private var methodChannel: FlutterMethodChannel?
    private var progressChannels: [String: FlutterEventSink] = [:]
    private var eventChannels: [String: FlutterEventChannel] = [:]
    private var statusEventChannels: [String: FlutterEventChannel] = [:]
    private var streamHandlers: [String: ProgressStreamHandler] = [:]
    private var statusHandlers: [String: StatusStreamHandler] = [:]
    private var downloadTasks: [URLSessionDownloadTask] = []
    private var uploadTasks: [URLSessionUploadTask] = []
    private var binaryMessenger: FlutterBinaryMessenger?
    private let notificationCenter = UNUserNotificationCenter.current()
    private var isQueueEnabled: Bool = true
    private var maxConcurrentTransfers: Int = 1
    private var completionCounter: Int = 0
    private var completedTaskCleanupDelay: TimeInterval = 0 // Immediate cleanup by default

    // After a task completes and its status is verified, schedule cleanup
    private func scheduleTaskCleanup(taskId: String) {
        if completedTaskCleanupDelay <= 0 {
            // Remove immediately if delay is 0 or negative
            transferDetails.removeValue(forKey: taskId)
        } else {
            // Schedule removal after the configured delay
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + completedTaskCleanupDelay) { [weak self] in
                self?.transferDetails.removeValue(forKey: taskId)
            }
        }
    }
    
    // Queue management properties
    private var transferQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1 // Serial queue by default
        return queue
    }()
    
    // Custom Operation class for transfers
    private class TransferOperation: Operation {
        let taskId: String
        let executeBlock: (@escaping () -> Void) -> Void
        private var isTransferFinished = false
        private let finishLock = NSLock()
        
        init(taskId: String, executeBlock: @escaping (@escaping () -> Void) -> Void) {
            self.taskId = taskId
            self.executeBlock = executeBlock
            super.init()
        }
        
        override func main() {
            guard !isCancelled else { return }
            
            let semaphore = DispatchSemaphore(value: 0)
            executeBlock {
                self.finishLock.lock()
                self.isTransferFinished = true
                self.finishLock.unlock()
                semaphore.signal()
            }
            
            // Wait for transfer to complete
            _ = semaphore.wait(timeout: .now() + 3600) // 1 hour timeout
        }
        
        override var isFinished: Bool {
            finishLock.lock()
            let finished = isTransferFinished || isCancelled
            finishLock.unlock()
            return finished
        }
    }

    private func getNextCompletionId() -> Int {
        completionCounter += 1
        return completionCounter
    }

    // Queue configuration method
    private func configureTransferQueue(isEnabled: Bool, maxConcurrent: Int, cleanupDelay: TimeInterval = 0) {
        isQueueEnabled = isEnabled
        maxConcurrentTransfers = maxConcurrent
        completedTaskCleanupDelay = cleanupDelay
        transferQueue.maxConcurrentOperationCount = isEnabled ? maxConcurrent : OperationQueue.defaultMaxConcurrentOperationCount
    }
    
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "dev.sylvestre.background_transfer")
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false // Force immediate start
        config.shouldUseExtendedBackgroundIdleMode = true
        
        // iOS 13+ specific configurations
        if #available(iOS 13.0, *) {
            config.allowsConstrainedNetworkAccess = true
            config.allowsExpensiveNetworkAccess = true
        }
        
        return URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)  // Use main queue for callbacks
    }()
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        os_log("Registering BackgroundTransferPlugin", log: logger, type: .info)
        let channel = FlutterMethodChannel(name: "background_transfer/task", binaryMessenger: registrar.messenger())
        let instance = BackgroundTransferPlugin()
        instance.methodChannel = channel
        instance.binaryMessenger = registrar.messenger()
        registrar.addMethodCallDelegate(instance, channel: channel)
        
        // Set up notification delegate and request permissions
        UNUserNotificationCenter.current().delegate = instance
        instance.requestNotificationPermissions()
    }
    
    private func requestNotificationPermissions() {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                os_log("Error requesting notification permissions: %{public}@", log: logger, type: .error, error.localizedDescription)
                return
            }
            if granted {
                os_log("Notification permissions granted", log: logger, type: .info)
            } else {
                os_log("Notification permissions denied", log: logger, type: .info)
            }
        }
    }
    
    private func enqueueTransfer(taskId: String, operation: @escaping (@escaping () -> Void) -> Void) {
        if isQueueEnabled {
            let transferOp = TransferOperation(taskId: taskId, executeBlock: operation)
            transferQueue.addOperation(transferOp)
        } else {
            operation { }
        }
    }
    
    private func handleStartDownload(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let fileUrl = args["file_url"] as? String,
              let outputPath = args["output_path"] as? String else {
            result(FlutterError(code: "MISSING_ARGUMENTS", message: "file_url and output_path are required", details: nil))
            return
        }
        
        let headers = args["headers"] as? [String: String] ?? [:]
        startDownloadTask(fileUrl: fileUrl, outputPath: outputPath, headers: headers, result: result)
    }
    
    private struct TransferDetails {
        let type: String
        let url: String
        let path: String
        let createdAt: Date
        var progress: Float
        var status: String
        var code: Int?
        let fields: [String: String]
        
        func toDictionary() -> [String: Any] {
            var dict: [String: Any] = [
                "type": type,
                "url": url,
                "path": path,
                "createdAt": ISO8601DateFormatter().string(from: createdAt),
                "progress": progress,
                "status": status,
                "code": code
            ]
            // Add all custom fields
            fields.forEach { key, value in
                dict[key] = value
            }
            return dict
        }
    }
    
    private var transferDetails: [String: TransferDetails] = [:]
    
    private func startDownloadTask(fileUrl: String, outputPath: String, headers: [String: String], result: @escaping FlutterResult) {
        let taskId = UUID().uuidString
        
        // Record transfer details
        transferDetails[taskId] = TransferDetails(
            type: "download",
            url: fileUrl,
            path: outputPath,
            createdAt: Date(),
            progress: 0.0,
            status: "queued",
            fields: [:]  // Empty fields for downloads
        )
        
        enqueueTransfer(taskId: taskId) { [weak self] completion in
            guard let self = self,
                  let url = URL(string: fileUrl) else {
                completion()
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 3600 // 1 hour timeout
            
            // Add headers
            headers.forEach { key, value in
                request.setValue(value, forHTTPHeaderField: key)
            }
            
            // Create and configure download task
            let completionId = self.getNextCompletionId()
            let downloadTask = self.urlSession.downloadTask(with: request)
            downloadTask.taskDescription = "download|\(taskId)|\(outputPath)|\(completionId)"
            downloadTask.priority = URLSessionTask.highPriority
            
            os_log("Starting download task %{public}@ for URL: %{public}@", log: logger, type: .debug, taskId, fileUrl)
            
            // Store completion handler
            self.taskCompletions[downloadTask.taskDescription ?? ""] = completion
            
            // Update status before starting
            if var details = self.transferDetails[taskId] {
                details.status = "active"
                self.transferDetails[taskId] = details
            }
            
            // Add to active tasks and start
            self.downloadTasks.append(downloadTask)
            downloadTask.resume()
            
            self.showTransferStartNotification(type: "download", taskId: taskId)
        }
        
        result(taskId)
    }
    
    private func handleStartUpload(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let filePath = args["file_path"] as? String,
              let uploadUrl = args["upload_url"] as? String else {
            result(FlutterError(code: "MISSING_ARGUMENTS", message: "file_path and upload_url are required", details: nil))
            return
        }
        
        let headers = args["headers"] as? [String: String] ?? [:]
        let fields = args["fields"] as? [String: String] ?? [:]
        startUploadTask(filePath: filePath, uploadUrl: uploadUrl, headers: headers, fields: fields, result: result)
    }
    
    private func startUploadTask(filePath: String, uploadUrl: String, headers: [String: String], fields: [String: String], result: @escaping FlutterResult) {
        let taskId = UUID().uuidString
        
        transferDetails[taskId] = TransferDetails(
            type: "upload",
            url: uploadUrl,
            path: filePath,
            createdAt: Date(),
            progress: 0.0,
            status: "queued",
            fields: fields
        )
        
        enqueueTransfer(taskId: taskId) { [weak self] completion in
            guard let self = self,
                  let url = URL(string: uploadUrl),
                  url.scheme != nil else {
                self?.showTransferCompleteNotification(type: "upload", taskId: taskId, 
                    error: NSError(domain: "BackgroundTransferPlugin", code: -1002, 
                                 userInfo: [NSLocalizedDescriptionKey: "Invalid upload URL"]))
                completion()
                return
            }
            
            // Create file URL and validate
            let fileUrl: URL
            if filePath.hasPrefix("file://") {
                guard let url = URL(string: filePath) else {
                    self.showTransferCompleteNotification(type: "upload", taskId: taskId, 
                        error: NSError(domain: "BackgroundTransferPlugin", code: -1002, 
                                     userInfo: [NSLocalizedDescriptionKey: "Invalid file URL"]))
                    completion()
                    return
                }
                fileUrl = url
            } else {
                fileUrl = URL(fileURLWithPath: filePath)
            }
            
            guard FileManager.default.fileExists(atPath: fileUrl.path),
                  FileManager.default.isReadableFile(atPath: fileUrl.path) else {
                self.showTransferCompleteNotification(type: "upload", taskId: taskId,
                    error: NSError(domain: "BackgroundTransferPlugin", code: -1002,
                                 userInfo: [NSLocalizedDescriptionKey: "File not found or not readable"]))
                completion()
                return
            }
            
            do {
                // Create a temporary file for the multipart form data
                let temporaryDir = FileManager.default.temporaryDirectory
                let formDataFile = temporaryDir.appendingPathComponent("upload_\(taskId)_form")
                
                // Create multipart form data
                let boundary = "Boundary-\(UUID().uuidString)"
                var formData = Data()
                
                // Add form fields
                for (key, value) in fields {
                    formData.append("--\(boundary)\r\n".data(using: .utf8)!)
                    formData.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
                    formData.append("\(value)\r\n".data(using: .utf8)!)
                }
                
                // Add file part header
                formData.append("--\(boundary)\r\n".data(using: .utf8)!)
                formData.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileUrl.lastPathComponent)\"\r\n".data(using: .utf8)!)
                formData.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
                
                // Write initial form data
                try formData.write(to: formDataFile)
                
                // Append file data in chunks
                if let fileHandle = FileHandle(forWritingAtPath: formDataFile.path),
                   let inputFileHandle = FileHandle(forReadingAtPath: fileUrl.path) {
                    fileHandle.seekToEndOfFile()
                    
                    while true {
                        let data = inputFileHandle.readData(ofLength: 1024 * 1024)
                        if data.count == 0 { break }
                        fileHandle.write(data)
                    }
                    
                    // Write final boundary
                    if let finalBoundaryData = "\r\n--\(boundary)--\r\n".data(using: .utf8) {
                        fileHandle.write(finalBoundaryData)
                    }
                    
                    fileHandle.closeFile()
                    inputFileHandle.closeFile()
                }
                
                // Create and configure upload request
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 3600 // 1 hour timeout
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                
                // Add custom headers
                headers.forEach { key, value in
                    request.setValue(value, forHTTPHeaderField: key)
                }
                
                // Create and configure upload task
                let completionId = self.getNextCompletionId()
                let uploadTask = self.urlSession.uploadTask(with: request, fromFile: formDataFile)
                uploadTask.taskDescription = "upload|\(taskId)|\(filePath)|\(completionId)"
                uploadTask.priority = URLSessionTask.highPriority
                
                os_log("Starting upload task %{public}@ for URL: %{public}@", log: logger, type: .debug, taskId, uploadUrl)
                
                // Store completion handler
                self.taskCompletions[uploadTask.taskDescription ?? ""] = completion
                
                // Update status before starting
                if var details = self.transferDetails[taskId] {
                    details.status = "active"
                    self.transferDetails[taskId] = details
                }
                
                // Add to active tasks and start
                self.uploadTasks.append(uploadTask)
                uploadTask.resume()
                
                self.showTransferStartNotification(type: "upload", taskId: taskId)
                
                // Schedule cleanup of temporary file
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 300) {
                    try? FileManager.default.removeItem(at: formDataFile)
                }
            } catch {
                os_log("Error preparing upload: %{public}@", log: logger, type: .error, error.localizedDescription)
                self.showTransferCompleteNotification(type: "upload", taskId: taskId, error: error)
                completion()
            }
        }
        
        result(taskId)
    }
    
    private func handleGetProgress(_ call: FlutterMethodCall, result: @escaping FlutterResult, type: String) {
        guard let args = call.arguments as? [String: Any],
              let taskId = args["task_id"] as? String,
              let messenger = binaryMessenger else {
            result(FlutterError(code: "MISSING_ARGUMENTS", message: "task_id is required", details: nil))
            return
        }
        
        let channelName = "background_transfer/\(type)_progress_\(taskId)"
        os_log("Setting up progress channel: %{public}@", log: logger, type: .debug, channelName)
        
        let eventChannel = FlutterEventChannel(name: channelName, binaryMessenger: messenger)
        let streamHandler = ProgressStreamHandler(taskId: taskId)
        streamHandlers[taskId] = streamHandler
        eventChannel.setStreamHandler(streamHandler)
        eventChannels[taskId] = eventChannel
        
        os_log("Progress channel setup complete for task: %{public}@", log: logger, type: .debug, taskId)
        result(nil)
    }

    private func handleGetStatus(_ call: FlutterMethodCall, result: @escaping FlutterResult, type: String) {
        guard let args = call.arguments as? [String: Any],
              let taskId = args["task_id"] as? String,
              let messenger = binaryMessenger else {
            result(FlutterError(code: "MISSING_ARGUMENTS", message: "task_id is required", details: nil))
            return
        }

        let channelName = "background_transfer/\(type)_progress_\(taskId)"
        os_log("Setting up progress channel: %{public}@", log: logger, type: .debug, channelName)

        let eventChannel = FlutterEventChannel(name: channelName, binaryMessenger: messenger)
        let statusHandler = StatusStreamHandler(taskId: taskId)
        statusHandlers[taskId] = statusHandler
        eventChannel.setStreamHandler(statusHandler)
        statusEventChannels[taskId] = eventChannel

        os_log("Status channel setup complete for task: %{public}@", log: logger, type: .debug, taskId)
        result(nil)
    }
    
    private func handleIsComplete(_ call: FlutterMethodCall, result: @escaping FlutterResult, type: String) {
        guard let args = call.arguments as? [String: Any],
              let taskId = args["task_id"] as? String else {
            result(FlutterError(code: "MISSING_ARGUMENTS", message: "task_id is required", details: nil))
            return
        }
        
        if let details = transferDetails[taskId] {
            result(details.status == "completed")
        } else {
            result(false)
        }
    }
    
    private func handleCancelTask(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let taskId = args["task_id"] as? String else {
            result(FlutterError(code: "MISSING_ARGUMENTS", message: "task_id is required", details: nil))
            return
        }
        
        os_log("Cancelling task %{public}@", log: logger, type: .debug, taskId)
        
        // Cancel any queued operations first
        var operationFound = false
        if isQueueEnabled {
            transferQueue.operations.forEach { operation in
                if let transferOp = operation as? TransferOperation, transferOp.taskId == taskId {
                    operation.cancel()
                    operationFound = true
                }
            }
        }
        
        // Cancel active download task if exists
        var downloadTaskFound = false
        if let downloadTask = downloadTasks.first(where: { $0.taskDescription?.contains(taskId) ?? false }) {
            downloadTask.cancel()
            downloadTasks.removeAll { $0.taskDescription?.contains(taskId) ?? false }
            downloadTaskFound = true
        }
        
        // Cancel active upload task if exists
        var uploadTaskFound = false
        if let uploadTask = uploadTasks.first(where: { $0.taskDescription?.contains(taskId) ?? false }) {
            uploadTask.cancel()
            uploadTasks.removeAll { $0.taskDescription?.contains(taskId) ?? false }
            uploadTaskFound = true
        }
        
        // Update transfer details and mark as cancelled
        if var details = transferDetails[taskId] {
            let type = details.type
            details.status = "cancelled"
            details.progress = 0.0
            transferDetails[taskId] = details
            
            // Clean up any temporary files for uploads
            if type == "upload" {
                let temporaryDir = FileManager.default.temporaryDirectory
                let formDataFile = temporaryDir.appendingPathComponent("upload_\(taskId)_form")
                try? FileManager.default.removeItem(at: formDataFile)
            }
            
            // Schedule immediate cleanup for cancelled task
            scheduleTaskCleanup(taskId: taskId)
            
            // Show cancellation notification
            showCancelNotification(type: type, taskId: taskId)
        }
        
        // Clean up event handlers and progress tracking
        cleanupEventHandlers(forTaskId: taskId)
        
        // Clean up any completion handlers
        cleanupCompletionHandlers(forTaskId: taskId)
        
        // Log cancellation status
        os_log("Task %{public}@ cancelled: operation=%{public}@, download=%{public}@, upload=%{public}@", 
               log: logger, 
               type: .debug, 
               taskId, 
               String(describing: operationFound), 
               String(describing: downloadTaskFound), 
               String(describing: uploadTaskFound))
        
        result(true)
    }
    
    private func cleanupEventHandlers(forTaskId taskId: String) {
        streamHandlers.removeValue(forKey: taskId)
        statusHandlers.removeValue(forKey: taskId)
        eventChannels.removeValue(forKey: taskId)?.setStreamHandler(nil)
        statusEventChannels.removeValue(forKey: taskId)?.setStreamHandler(nil)
        progressChannels.removeValue(forKey: taskId)
    }

    private func cleanupCompletionHandlers(forTaskId taskId: String) {
        downloadTasks.forEach { task in
            if let description = task.taskDescription, description.contains(taskId) {
                taskCompletions.removeValue(forKey: description)
            }
        }
        uploadTasks.forEach { task in 
            if let description = task.taskDescription, description.contains(taskId) {
                taskCompletions.removeValue(forKey: description)
            }
        }
    }

    private func showCancelNotification(type: String, taskId: String) {
        let content = UNMutableNotificationContent()
        //content.title = type == "download" ? "Download Cancelled" : "Upload Cancelled"
        //content.body = type == "download" ? "Your download was cancelled" : "Your upload was cancelled"
        content.title = type == "download" ? "Stahování zrušeno" : "Nahrávání zrušeno"
        content.body = type == "download" ? "Vaše stahování bylo zrušeno" : "Vaše nahrávání bylo zrušeno"
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: "\(type)_cancel_\(taskId)", 
                                          content: content, 
                                          trigger: nil)
        
        notificationCenter.add(request) { error in
            if let error = error {
                os_log("Error showing cancel notification: %{public}@", log: logger, type: .error, error.localizedDescription)
            }
        }
    }
    
    // URLSession delegate methods for handling progress and completion
    // Dictionary to store completion handlers
    private var taskCompletions: [String: () -> Void] = [:]
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let taskDescription = downloadTask.taskDescription else { return }
        let components = taskDescription.split(separator: "|").map(String.init)
        guard components.count == 4 else { return }
        
        let taskId = components[1]
        let outputPath = components[2]
        let completionKey = taskDescription
        
        do {
            let destinationURL = URL(fileURLWithPath: outputPath)
            try FileManager.default.moveItem(at: location, to: destinationURL)
            // Update status to completed
            if var details = transferDetails[taskId] {
                details.status = "completed"
                transferDetails[taskId] = details
            }

             guard let httpResponse = downloadTask.response as? HTTPURLResponse else { return }

            DispatchQueue.main.async {
                self.statusHandlers[taskId]?.sendStatus(httpResponse.statusCode)
            }
            showTransferCompleteNotification(type: "download", taskId: taskId)
        } catch {
            os_log("Error moving downloaded file: %{public}@", log: logger, type: .error, error.localizedDescription)
            showTransferCompleteNotification(type: "download", taskId: taskId, error: error)
        }
        
        // Call completion handler
        taskCompletions[completionKey]?()
        taskCompletions.removeValue(forKey: completionKey)
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard let taskDescription = task.taskDescription else { return }
        let components = taskDescription.split(separator: "|").map(String.init)
        guard components.count >= 4 else { return }  // Updated from 3 to 4
        
        let taskId = components[1]
        let progress = Float(totalBytesSent) / Float(totalBytesExpectedToSend)
        
        os_log("Upload progress: %{public}f for task %{public}@", log: logger, type: .debug, progress, taskId)
        
        DispatchQueue.main.async {
            self.updateTransferProgress(taskId: taskId, progress: progress)
            self.streamHandlers[taskId]?.sendProgress(progress)
        }
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let taskDescription = downloadTask.taskDescription else { return }
        let components = taskDescription.split(separator: "|").map(String.init)
        guard components.count >= 4 else { return }  // Updated from 3 to 4
        
        let taskId = components[1]
        let progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
        
        os_log("Download progress: %{public}f for task %{public}@", log: logger, type: .debug, progress, taskId)
        
        DispatchQueue.main.async {
            self.updateTransferProgress(taskId: taskId, progress: progress)
            self.streamHandlers[taskId]?.sendProgress(progress)
        }
    }
    
    private func updateTransferProgress(taskId: String, progress: Float) {
        if var details = transferDetails[taskId] {
            details.progress = progress
            transferDetails[taskId] = details
            os_log("Updated progress for task %{public}@: %{public}f", log: logger, type: .debug, taskId, progress)
        }
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let taskDescription = task.taskDescription else { return }
        let components = taskDescription.split(separator: "|").map(String.init)
        guard components.count >= 2 else { return }

        guard let httpResponse = task.response as? HTTPURLResponse else { return }

        let type = components[0]
        let taskId = components[1]
        let completionKey = taskDescription
        
        if let error = error {
            os_log("Transfer failed: %{public}@", log: logger, type: .error, error.localizedDescription)
            if var details = transferDetails[taskId] {
                details.status = "failed"
                details.code = httpResponse.statusCode
                transferDetails[taskId] = details
            }
            DispatchQueue.main.async {
                self.statusHandlers[taskId]?.sendStatus(httpResponse.statusCode)
            }
            showTransferCompleteNotification(type: type, taskId: taskId, error: error)
        } else {
            os_log("Transfer completed successfully: %{public}@", log: logger, type: .debug, taskId)
            // For uploads, we mark completion here. Downloads are marked in didFinishDownloadingTo
            if type == "upload" {
                if var details = transferDetails[taskId] {
                    details.status = "completed"
                    details.code = httpResponse.statusCode
                    transferDetails[taskId] = details
                }
                DispatchQueue.main.async {
                    self.statusHandlers[taskId]?.sendStatus(httpResponse.statusCode)
                }
                showTransferCompleteNotification(type: type, taskId: taskId)
            }
        }
        
        // Schedule cleanup for both success and failure cases
        // For downloads, this will be called again in didFinishDownloadingTo, but that's okay
        // because scheduleTaskCleanup is idempotent
        scheduleTaskCleanup(taskId: taskId)
        
        // Call completion handler
        taskCompletions[completionKey]?()
        taskCompletions.removeValue(forKey: completionKey)
    }
    


    private func showTransferStartNotification(type: String, taskId: String) {
        let content = UNMutableNotificationContent()
        //content.title = type == "download" ? "Download Started" : "Upload Started"
        //content.body = type == "download" ? "Your download has begun" : "Your upload has begun"
        content.title = type == "download" ? "Stahování zahájeno" : "Nahrávání zahájeno"
        content.body = type == "download" ? "Stahování začalo" : "Nahrávání začalo"
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: "\(type)_start_\(taskId)", 
                                          content: content, 
                                          trigger: nil)
        
        notificationCenter.add(request) { error in
            if let error = error {
                os_log("Error showing start notification: %{public}@", log: logger, type: .error, error.localizedDescription)
            }
        }
    }
    
    private func showTransferCompleteNotification(type: String, taskId: String, error: Error? = nil) {
        let content = UNMutableNotificationContent()
        
        if let error = error {
            //content.title = type == "download" ? "Download Failed" : "Upload Failed"
            content.title = type == "download" ? "Stahování se nezdařilo" : "Nahrávání se nezdařilo"
            content.body = error.localizedDescription
        } else {
            //content.title = type == "download" ? "Download Complete" : "Upload Complete"
            //content.body = type == "download" ? "Your download has finished" : "Your upload has finished"
            content.title = type == "download" ? "Stahování dokončeno" : "Nahrávání dokončeno"
            content.body = type == "download" ? "Stahování bylo dokončeno" : "Nahrávání bylo dokončeno"
        }
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: "\(type)_complete_\(taskId)", 
                                          content: content, 
                                          trigger: nil)
        
        notificationCenter.add(request) { error in
            if let error = error {
                os_log("Error showing complete notification: %{public}@", log: logger, type: .error, error.localizedDescription)
            }
        }
    }
    
    // UNUserNotificationCenterDelegate methods
    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // This delegate method is called when a notification is about to be presented while the app is in foreground
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle notification response when user taps on it
        completionHandler()
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startDownload":
            handleStartDownload(call, result: result)
        case "startUpload":
            handleStartUpload(call, result: result)
        case "getDownloadProgress":
            handleGetProgress(call, result: result, type: "download")
        case "getUploadProgress":
            handleGetProgress(call, result: result, type: "upload")
        case "getResultStatus":
            handleGetStatus(call, result: result, type: "status")
        case "isDownloadComplete":
            handleIsComplete(call, result: result, type: "download")
        case "isUploadComplete":
            handleIsComplete(call, result: result, type: "upload")
        case "cancelTask":
            handleCancelTask(call, result: result)
        case "deleteTask":
            handleDeleteTask(call, result: result)
        case "configureQueue":
            handleConfigureQueue(call, result: result)
        case "getQueueStatus":
            handleGetQueueStatus(result)
        case "getQueuedTransfers":
            handleGetQueuedTransfers(result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    private func handleConfigureQueue(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let isEnabled = args["isEnabled"] as? Bool else {
            result(FlutterError(code: "MISSING_ARGUMENTS", message: "isEnabled is required", details: nil))
            return
        }
        let maxConcurrent = args["maxConcurrent"] as? Int ?? 1
        let cleanupDelay = args["cleanupDelay"] as? Double ?? 0
        configureTransferQueue(isEnabled: isEnabled, maxConcurrent: maxConcurrent, cleanupDelay: cleanupDelay)
        result(nil)
    }
    
    private func handleGetQueueStatus(_ result: @escaping FlutterResult) {
        let status: [String: Any] = [
            "isEnabled": isQueueEnabled,
            "maxConcurrent": maxConcurrentTransfers,
            "activeCount": transferQueue.operationCount,
            "queuedCount": transferQueue.operations.count - transferQueue.operationCount
        ]
        result(status)
    }
    
    private func handleGetQueuedTransfers(_ result: @escaping FlutterResult) {
        let transfers = transferDetails.map { (taskId, details) -> [String: Any] in
            var transfer = details.toDictionary()
            transfer["taskId"] = taskId
            return transfer
        }
        result(transfers)
    }

    private func handleDeleteTask(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let taskId = args["task_id"] as? String else {
            result(FlutterError(code: "MISSING_ARGUMENTS", message: "task_id is required", details: nil))
            return
        }
        // remove the task from transferDetails if it exists and is not active
        if let details = transferDetails[taskId] {
            if details.status != "active" {
                transferDetails.removeValue(forKey: taskId)
                result(true)
            } else {
                result(FlutterError(code: "INVALID_STATE", 
                                  message: "Cannot delete an active task", 
                                  details: nil))
            }
        } else {
            result(true)
        }
    }
}

class ProgressStreamHandler: NSObject, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    private let taskId: String
    
    init(taskId: String) {
        self.taskId = taskId
        super.init()
    }
    
    func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
        os_log("Progress stream listener added for task: %{public}@", log: logger, type: .debug, taskId)
        self.eventSink = eventSink
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        os_log("Progress stream cancelled for task: %{public}@", log: logger, type: .debug, taskId)
        eventSink = nil
        return nil
    }
    
    func sendProgress(_ progress: Float) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let sink = self.eventSink {
                os_log("Sending progress %{public}f for task: %{public}@", log: logger, type: .debug, progress, self.taskId)
                sink(progress)
            } else {
                os_log("No event sink available for task: %{public}@", log: logger, type: .debug, self.taskId)
            }
        }
    }
}

class StatusStreamHandler: NSObject, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    private let taskId: String

    init(taskId: String) {
        self.taskId = taskId
        super.init()
    }

    func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
        os_log("Status stream listener added for task: %{public}@", log: logger, type: .debug, taskId)
        self.eventSink = eventSink
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        os_log("Status stream cancelled for task: %{public}@", log: logger, type: .debug, taskId)
        eventSink = nil
        return nil
    }

    func sendStatus(_ status: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let sink = self.eventSink {
                os_log("Sending status %{public}f for task: %{public}@", log: logger, type: .debug, status, self.taskId)
                sink(status)
            } else {
                os_log("No event sink available for task: %{public}@", log: logger, type: .debug, self.taskId)
            }
        }
    }
}