import Flutter
import UIKit
import os.log
import UserNotifications

private let logger = OSLog(subsystem: "dev.sylvestre.background_transfer", category: "Plugin")

public class BackgroundTransferPlugin: NSObject, FlutterPlugin, URLSessionTaskDelegate, URLSessionDownloadDelegate, UNUserNotificationCenterDelegate {
    private var methodChannel: FlutterMethodChannel?
    private var progressChannels: [String: FlutterEventSink] = [:]
    private var eventChannels: [String: FlutterEventChannel] = [:]
    private var streamHandlers: [String: ProgressStreamHandler] = [:]
    private var downloadTasks: [URLSessionDownloadTask] = []
    private var uploadTasks: [URLSessionUploadTask] = []
    private var completedTasks: Set<String> = []
    private var binaryMessenger: FlutterBinaryMessenger?
    private let notificationCenter = UNUserNotificationCenter.current()
    
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "dev.sylvestre.background_transfer")
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
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
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        os_log("Handling method call: %{public}@", log: logger, type: .info, call.method)
        switch call.method {
        case "startDownload":
            handleStartDownload(call, result: result)
        case "startUpload":
            handleStartUpload(call, result: result)
        case "getDownloadProgress":
            handleGetProgress(call, result: result, type: "download")
        case "getUploadProgress":
            handleGetProgress(call, result: result, type: "upload")
        case "isDownloadComplete":
            handleIsComplete(call, result: result, type: "download")
        case "isUploadComplete":
            handleIsComplete(call, result: result, type: "upload")
        case "cancelTask":
            handleCancelTask(call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func handleStartDownload(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        os_log("Starting download", log: logger, type: .info)
        guard let args = call.arguments as? [String: Any],
              let fileUrl = args["file_url"] as? String,
              let outputPath = args["output_path"] as? String else {
            os_log("Missing arguments for download", log: logger, type: .error)
            result(FlutterError(code: "MISSING_ARGUMENTS", message: "file_url and output_path are required", details: nil))
            return
        }
        
        var headers = [String: String]()
        if let headersAny = args["headers"] {
            if let headersDict = headersAny as? [String: String] {
                headers = headersDict
            } else {
                result(FlutterError(code: "INVALID_HEADERS", message: "headers must be a dictionary of String:String", details: nil))
                return
            }
        }
        
        let taskId = startDownload(fileUrl: fileUrl, outputPath: outputPath, headers: headers)
        os_log("Download started with taskId: %{public}@", log: logger, type: .info, taskId)
        result(taskId)
    }
    
    private func handleStartUpload(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let filePath = args["file_path"] as? String,
              let uploadUrl = args["upload_url"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
            return
        }
        
        let headers = args["headers"] as? [String: String] ?? [:]
        let fields = args["fields"] as? [String: String] ?? [:]
        
        let taskId = startUpload(filePath: filePath, uploadUrl: uploadUrl, headers: headers, fields: fields)
        result(taskId)
    }
    
    private func handleGetProgress(_ call: FlutterMethodCall, result: @escaping FlutterResult, type: String) {
        os_log("Setting up progress tracking for %{public}@", log: logger, type: .info, type)
        guard let args = call.arguments as? [String: Any],
              let taskId = args["task_id"] as? String,
              let messenger = binaryMessenger else {
            os_log("Invalid arguments or messenger not available for progress tracking", log: logger, type: .error)
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Task ID is required", details: nil))
            return
        }

        let channelName = "background_transfer/\(type)_progress_\(taskId)"
        let eventChannel = FlutterEventChannel(name: channelName, binaryMessenger: messenger)
        let streamHandler = ProgressStreamHandler()
        streamHandlers[taskId] = streamHandler
        eventChannel.setStreamHandler(streamHandler)
        eventChannels[taskId] = eventChannel
        
        result(nil)
    }
    
    private func handleIsComplete(_ call: FlutterMethodCall, result: @escaping FlutterResult, type: String) {
        guard let args = call.arguments as? [String: Any],
              let taskId = args["task_id"] as? String else {
            result(false)
            return
        }
        result(completedTasks.contains(taskId))
    }
    
    private func handleCancelTask(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let taskId = args["task_id"] as? String else {
            result(false)
            return
        }
        
        if let downloadTask = downloadTasks.first(where: { $0.taskDescription?.contains(taskId) ?? false }) {
            downloadTask.cancel()
            downloadTasks.removeAll { $0.taskDescription?.contains(taskId) ?? false }
        }
        
        if let uploadTask = uploadTasks.first(where: { $0.taskDescription?.contains(taskId) ?? false }) {
            uploadTask.cancel()
            uploadTasks.removeAll { $0.taskDescription?.contains(taskId) ?? false }
        }
        
        result(true)
    }
    
    private func startDownload(fileUrl: String, outputPath: String, headers: [String: String]) -> String {
        guard let url = URL(string: fileUrl) else { return "" }
        
        var request = URLRequest(url: url)
        headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let taskId = UUID().uuidString
        let downloadTask = urlSession.downloadTask(with: request)
        downloadTask.taskDescription = "download|\(taskId)|\(outputPath)"
        downloadTask.resume()
        downloadTasks.append(downloadTask)
        
        showTransferStartNotification(type: "download", taskId: taskId)
        
        return taskId
    }
    
    private func startUpload(filePath: String, uploadUrl: String, headers: [String: String], fields: [String: String]) -> String {
        // Validate URLs and create proper file URL
        guard let url = URL(string: uploadUrl),
              url.scheme != nil else {
            os_log("Invalid upload URL (missing scheme): %{public}@", log: logger, type: .error, uploadUrl)
            let taskId = UUID().uuidString
            showTransferCompleteNotification(type: "upload", taskId: taskId, error: NSError(domain: "BackgroundTransferPlugin", code: -1002, userInfo: [NSLocalizedDescriptionKey: "Invalid upload URL - must include http:// or https://"]))
            return taskId
        }
        
        // Convert file path to proper URL, handling both absolute paths and file:// URLs
        let fileUrl: URL
        if filePath.hasPrefix("file://") {
            guard let url = URL(string: filePath) else {
                let taskId = UUID().uuidString
                showTransferCompleteNotification(type: "upload", taskId: taskId, error: NSError(domain: "BackgroundTransferPlugin", code: -1002, userInfo: [NSLocalizedDescriptionKey: "Invalid file URL"]))
                return taskId
            }
            fileUrl = url
        } else {
            fileUrl = URL(fileURLWithPath: filePath)
        }
        
        // Verify file exists and is readable
        guard FileManager.default.fileExists(atPath: fileUrl.path),
              FileManager.default.isReadableFile(atPath: fileUrl.path) else {
            os_log("File does not exist or is not readable: %{public}@", log: logger, type: .error, fileUrl.path)
            let taskId = UUID().uuidString
            showTransferCompleteNotification(type: "upload", taskId: taskId, error: NSError(domain: "BackgroundTransferPlugin", code: -1002, userInfo: [NSLocalizedDescriptionKey: "File not found or not readable"]))
            return taskId
        }

        let taskId = UUID().uuidString
        
        do {
            // Create a temporary file for the multipart form data
            let temporaryDir = FileManager.default.temporaryDirectory
            let formDataFile = temporaryDir.appendingPathComponent("upload_\(taskId)_form")
            var formData = Data()
            
            let boundary = "Boundary-\(UUID().uuidString)"
            
            // Add form fields to the temporary file
            for (key, value) in fields {
                formData.append("--\(boundary)\r\n".data(using: .utf8)!)
                formData.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
                formData.append("\(value)\r\n".data(using: .utf8)!)
            }
            
            // Add file part header
            formData.append("--\(boundary)\r\n".data(using: .utf8)!)
            formData.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileUrl.lastPathComponent)\"\r\n".data(using: .utf8)!)
            formData.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
            
            // Write the initial form data to the temporary file
            try formData.write(to: formDataFile)
            
            // Append file data using older FileHandle APIs with proper optional handling
            if let fileHandle = FileHandle(forWritingAtPath: formDataFile.path) {
                fileHandle.seekToEndOfFile()
                
                if let inputFileHandle = FileHandle(forReadingAtPath: fileUrl.path) {
                    // Read and write in chunks using older APIs with proper optional handling
                    while true {
                        let data = inputFileHandle.readData(ofLength: 1024 * 1024)
                        if data.count == 0 {
                            break
                        }
                        fileHandle.write(data)
                    }
                    
                    inputFileHandle.closeFile()
                }
                
                // Write final boundary
                if let finalBoundaryData = "\r\n--\(boundary)--\r\n".data(using: .utf8) {
                    fileHandle.write(finalBoundaryData)
                }
                fileHandle.closeFile()
            }
            
            // Create and configure the upload request
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            
            // Add custom headers
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
            
            // Create the upload task using the temporary file
            let uploadTask = urlSession.uploadTask(with: request, fromFile: formDataFile)
            uploadTask.taskDescription = "upload|\(taskId)|\(filePath)"
            uploadTask.resume()
            uploadTasks.append(uploadTask)
            
            showTransferStartNotification(type: "upload", taskId: taskId)
            
            // Schedule cleanup of temporary file
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 300) { // Clean up after 5 minutes
                try? FileManager.default.removeItem(at: formDataFile)
            }
            
        } catch {
            os_log("Error preparing upload: %{public}@", log: logger, type: .error, error.localizedDescription)
            showTransferCompleteNotification(type: "upload", taskId: taskId, error: error)
        }
        
        return taskId
    }
    
    // URLSession delegate methods for handling progress and completion
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let taskDescription = downloadTask.taskDescription else { return }
        let components = taskDescription.split(separator: "|").map(String.init)
        guard components.count == 3 else { return }
        
        let taskId = components[1]
        let outputPath = components[2]
        
        do {
            let destinationURL = URL(fileURLWithPath: outputPath)
            try FileManager.default.moveItem(at: location, to: destinationURL)
            completedTasks.insert(taskId)
            showTransferCompleteNotification(type: "download", taskId: taskId)
        } catch {
            os_log("Error moving downloaded file: %{public}@", log: logger, type: .error, error.localizedDescription)
            showTransferCompleteNotification(type: "download", taskId: taskId, error: error)
        }
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard let taskDescription = task.taskDescription else { return }
        let components = taskDescription.split(separator: "|").map(String.init)
        guard components.count == 3 else { return }
        
        let taskId = components[1]
        let progress = Float(totalBytesSent) / Float(totalBytesExpectedToSend)
        streamHandlers[taskId]?.sendProgress(progress)
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let taskDescription = downloadTask.taskDescription else { return }
        let components = taskDescription.split(separator: "|").map(String.init)
        guard components.count == 3 else { return }
        
        let taskId = components[1]
        let progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
        streamHandlers[taskId]?.sendProgress(progress)
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let taskDescription = task.taskDescription else { return }
        let components = taskDescription.split(separator: "|").map(String.init)
        guard components.count == 3 else { return }
        
        let type = components[0]
        let taskId = components[1]
        
        if let error = error {
            os_log("Transfer failed: %{public}@", log: logger, type: .error, error.localizedDescription)
            showTransferCompleteNotification(type: type, taskId: taskId, error: error)
        } else if type == "upload" {
            completedTasks.insert(taskId)
            showTransferCompleteNotification(type: type, taskId: taskId)
        }
    }
    
    private func showTransferStartNotification(type: String, taskId: String) {
        let content = UNMutableNotificationContent()
        content.title = type == "download" ? "Download Started" : "Upload Started"
        content.body = type == "download" ? "Your download has begun" : "Your upload has begun"
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
            content.title = type == "download" ? "Download Failed" : "Upload Failed"
            content.body = error.localizedDescription
        } else {
            content.title = type == "download" ? "Download Complete" : "Upload Complete"
            content.body = type == "download" ? "Your download has finished" : "Your upload has finished"
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
}

class ProgressStreamHandler: NSObject, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    
    func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = eventSink
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
    
    func sendProgress(_ progress: Float) {
        DispatchQueue.main.async {
            self.eventSink?(progress)
        }
    }
}
