//
//  ZENDownloadManager.swift
//  ZENDownloadManager
//
//  Created by Muhammad Zeeshan on 19/04/2016.
//  Copyright © 2016 ideamakerz. All rights reserved.
//
//  Updated by Maksim Zaremba on 10/02/2018
//

import UIKit
fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}

fileprivate func > <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l > r
  default:
    return rhs < lhs
  }
}


@objc public protocol ZENDownloadManagerDelegate: class {
    /**A delegate method called each time whenever any download task's progress is updated
     */
    func downloadRequestDidUpdateProgress(_ downloadModel: ZENDownloadModel)
    /**A delegate method called when interrupted tasks are repopulated
     */
    func downloadRequestDidPopulatedInterruptedTasks(_ downloadModel: ZENDownloadModel)
    /**A delegate method called each time whenever new download task is start downloading
     */
    @objc optional func downloadRequestStarted(_ downloadModel: ZENDownloadModel, index: Int)
    /**A delegate method called each time whenever running download task is paused. If task is already paused the action will be ignored
     */
    @objc optional func downloadRequestDidPaused(_ downloadModel: ZENDownloadModel)
    /**A delegate method called each time whenever any download task is resumed. If task is already downloading the action will be ignored
     */
    @objc optional func downloadRequestDidResumed(_ downloadModel: ZENDownloadModel)
    /**A delegate method called each time whenever any download task is resumed. If task is already downloading the action will be ignored
     */
    @objc optional func downloadRequestDidRetry(_ downloadModel: ZENDownloadModel, index: Int)
    /**A delegate method called each time whenever any download task is cancelled by the user
     */
    @objc optional func downloadRequestCanceled(_ downloadModel: ZENDownloadModel)
    /**A delegate method called each time whenever any download task is finished successfully
     */
    @objc optional func downloadRequestFinished(_ downloadModel: ZENDownloadModel)
    /**A delegate method called each time whenever any download task is failed due to any reason
     */
    @objc optional func downloadRequestDidFailedWithError(_ error: NSError, downloadModel: ZENDownloadModel)
    /**A delegate method called each time whenever specified destination does not exists. It will be called on the session queue. It provides the opportunity to handle error appropriately
     */
    @objc optional func downloadRequestDestinationDoestNotExists(_ downloadModel: ZENDownloadModel, location: URL)
    
}

open class ZENDownloadManager: NSObject {
    
    fileprivate var sessionManager: URLSession!
    
    fileprivate var backgroundSessionCompletionHandler: (() -> Void)?
    
    fileprivate let TaskDescFileNameIndex = 0
    fileprivate let TaskDescFileURLIndex = 1
    fileprivate let TaskDescFileDestinationIndex = 2
    
    fileprivate weak var delegate: ZENDownloadManagerDelegate?
    
    open var downloads = [String:ZENDownloadModel]()
    
    public convenience init(session sessionIdentifer: String, delegate: ZENDownloadManagerDelegate) {
        self.init()
        
        self.delegate = delegate
        self.sessionManager = backgroundSession(identifier: sessionIdentifer)
        self.populateOtherDownloadTasks()
    }
    
    public convenience init(session sessionIdentifer: String, delegate: ZENDownloadManagerDelegate, completion: (() -> Void)?) {
        self.init(session: sessionIdentifer, delegate: delegate)
        self.backgroundSessionCompletionHandler = completion
    }
    
    fileprivate func backgroundSession(identifier: String) -> URLSession {
        let sessionConfiguration = URLSessionConfiguration.background(withIdentifier: identifier)
        let session = Foundation.URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
        return session
    }
}

// MARK: Private Helper functions

extension ZENDownloadManager {
    
    fileprivate func downloadTasks() -> [URLSessionDownloadTask] {
        var tasks: [URLSessionDownloadTask] = []
        let semaphore : DispatchSemaphore = DispatchSemaphore(value: 0)
        sessionManager.getTasksWithCompletionHandler { (dataTasks, uploadTasks, downloadTasks) -> Void in
            tasks = downloadTasks
            semaphore.signal()
        }
        
        let _ = semaphore.wait(timeout: DispatchTime.distantFuture)
        
        debugPrint("ZENDownloadManager: pending tasks \(tasks)")
        
        return tasks
    }
    
    fileprivate func populateOtherDownloadTasks() {
        
        let downloadTasks = self.downloadTasks()
        
        for downloadTask in downloadTasks {
            let taskDescComponents: [String] = downloadTask.taskDescription!.components(separatedBy: ",")
            let fileName = taskDescComponents[TaskDescFileNameIndex]
            let fileURL = taskDescComponents[TaskDescFileURLIndex]
            let destinationPath = taskDescComponents[TaskDescFileDestinationIndex]
            
            let downloadModel = ZENDownloadModel.init(fileName: fileName, fileURL: fileURL, destinationPath: destinationPath)
            downloadModel.task = downloadTask
            downloadModel.startTime = Date()
            
            if downloadTask.state == .running {
                downloadModel.status = TaskStatus.downloading.description()
                downloads[fileName] = downloadModel
            } else if(downloadTask.state == .suspended) {
                downloadModel.status = TaskStatus.paused.description()
                downloads[fileName] = downloadModel
            } else {
                downloadModel.status = TaskStatus.failed.description()
            }
        }
    }
    
    fileprivate func isValidResumeData(_ resumeData: Data?) -> Bool {
        
        guard resumeData != nil || resumeData?.count > 0 else {
            return false
        }
        
        do {
            var resumeDictionary : AnyObject!
            resumeDictionary = try PropertyListSerialization.propertyList(from: resumeData!, options: PropertyListSerialization.MutabilityOptions(), format: nil) as AnyObject!
            var localFilePath = (resumeDictionary?["NSURLSessionResumeInfoLocalPath"] as? String)
            
            if localFilePath == nil || localFilePath?.characters.count < 1 {
                localFilePath = (NSTemporaryDirectory() as String) + (resumeDictionary["NSURLSessionResumeInfoTempFileName"] as! String)
            }
            
            let fileManager : FileManager! = FileManager.default
            debugPrint("resume data file exists: \(fileManager.fileExists(atPath: localFilePath! as String))")
            return fileManager.fileExists(atPath: localFilePath! as String)
        } catch let error as NSError {
            debugPrint("resume data is nil: \(error)")
            return false
        }
    }
}

extension ZENDownloadManager: URLSessionDownloadDelegate {
    
    public func urlSession(_ session: Foundation.URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        for (_, downloadModel) in self.downloads {
            if downloadTask.isEqual(downloadModel.task) {
                DispatchQueue.main.async(execute: { () -> Void in
                    
                    let receivedBytesCount = Double(downloadTask.countOfBytesReceived)
                    let totalBytesCount = Double(downloadTask.countOfBytesExpectedToReceive)
                    let progress = Float(receivedBytesCount / totalBytesCount)
                    
                    let taskStartedDate = downloadModel.startTime == nil ? Date() : downloadModel.startTime
                    let timeInterval = taskStartedDate!.timeIntervalSinceNow
                    var downloadTime = TimeInterval(-1 * timeInterval)
                    
                    if downloadTime == 0 {
                        downloadTime = 1
                    }
                    
                    let speed = Float(totalBytesWritten) / Float(downloadTime)
                    
                    let remainingContentLength = totalBytesExpectedToWrite - totalBytesWritten
                    
                    let remainingTime = remainingContentLength / Int64(speed)
                    let hours = Int(remainingTime) / 3600
                    let minutes = (Int(remainingTime) - hours * 3600) / 60
                    let seconds = Int(remainingTime) - hours * 3600 - minutes * 60
                    
                    let totalFileSize = ZENUtility.calculateFileSizeInUnit(totalBytesExpectedToWrite)
                    let totalFileSizeUnit = ZENUtility.calculateUnit(totalBytesExpectedToWrite)
                    
                    let downloadedFileSize = ZENUtility.calculateFileSizeInUnit(totalBytesWritten)
                    let downloadedSizeUnit = ZENUtility.calculateUnit(totalBytesWritten)
                    
                    let speedSize = ZENUtility.calculateFileSizeInUnit(Int64(speed))
                    let speedUnit = ZENUtility.calculateUnit(Int64(speed))
                    
                    downloadModel.remainingTime = (hours, minutes, seconds)
                    downloadModel.file = (totalFileSize, totalFileSizeUnit as String)
                    downloadModel.downloadedFile = (downloadedFileSize, downloadedSizeUnit as String)
                    downloadModel.speed = (speedSize, speedUnit as String)
                    downloadModel.progress = progress
                    
                    //self.downloadingArray[index] = downloadModel
                    
                    self.delegate?.downloadRequestDidUpdateProgress(downloadModel)
                })
                break
            }
        }
    }
    
    public func urlSession(_ session: Foundation.URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        for (_, downloadModel) in downloads {
            if downloadTask.isEqual(downloadModel.task) {
                let fileName = downloadModel.fileName as NSString
                let basePath = downloadModel.destinationPath == "" ? ZENUtility.baseFilePath : downloadModel.destinationPath
                let destinationPath = (basePath as NSString).appendingPathComponent(fileName as String)
                
                let fileManager : FileManager = FileManager.default
                
                //If all set just move downloaded file to the destination
                if fileManager.fileExists(atPath: basePath) {
                    let fileURL = URL(fileURLWithPath: destinationPath as String)
                    debugPrint("directory path = \(destinationPath)")
                    
                    do {
                        try fileManager.moveItem(at: location, to: fileURL)
                    } catch let error as NSError {
                        debugPrint("Error while moving downloaded file to destination path:\(error)")
                        DispatchQueue.main.async(execute: { () -> Void in
                            self.delegate?.downloadRequestDidFailedWithError?(error, downloadModel: downloadModel)
                        })
                    }
                } else {
                    //Opportunity to handle the folder doesnot exists error appropriately.
                    //Move downloaded file to destination
                    //Delegate will be called on the session queue
                    //Otherwise blindly give error Destination folder does not exists
                    
                    if let _ = self.delegate?.downloadRequestDestinationDoestNotExists {
                        self.delegate?.downloadRequestDestinationDoestNotExists?(downloadModel, location: location)
                    } else {
                        let error = NSError(domain: "FolderDoesNotExist", code: 404, userInfo: [NSLocalizedDescriptionKey : "Destination folder does not exists"])
                        self.delegate?.downloadRequestDidFailedWithError?(error, downloadModel: downloadModel)
                    }
                }
                
                break
            }
        }
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        debugPrint("task id: \(task.taskIdentifier)")
        /***** Any interrupted tasks due to any reason will be populated in failed state after init *****/
        
        DispatchQueue.main.async {
            let error = error as NSError?
            if (error?.userInfo[NSURLErrorBackgroundTaskCancelledReasonKey] as? NSNumber)?.intValue == NSURLErrorCancelledReasonUserForceQuitApplication || (error?.userInfo[NSURLErrorBackgroundTaskCancelledReasonKey] as? NSNumber)?.intValue == NSURLErrorCancelledReasonBackgroundUpdatesDisabled {
                
                let downloadTask = task as! URLSessionDownloadTask
                let taskDescComponents: [String] = downloadTask.taskDescription!.components(separatedBy: ",")
                let fileName = taskDescComponents[self.TaskDescFileNameIndex]
                let fileURL = taskDescComponents[self.TaskDescFileURLIndex]
                let destinationPath = taskDescComponents[self.TaskDescFileDestinationIndex]
                
                let downloadModel = ZENDownloadModel.init(fileName: fileName, fileURL: fileURL, destinationPath: destinationPath)
                downloadModel.status = TaskStatus.failed.description()
                downloadModel.task = downloadTask
                
                let resumeData = error?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
                
                var newTask = downloadTask
                if self.isValidResumeData(resumeData) == true {
                    newTask = self.sessionManager.downloadTask(withResumeData: resumeData!)
                } else {
                    newTask = self.sessionManager.downloadTask(with: URL(string: fileURL as String)!)
                }
                
                newTask.taskDescription = downloadTask.taskDescription
                downloadModel.task = newTask
                
                self.downloads[fileName] = downloadModel
                
                self.delegate?.downloadRequestDidPopulatedInterruptedTasks(downloadModel)
                
            } else {
                for(key, object) in self.downloads {
                    let downloadModel = object
                    if task.isEqual(downloadModel.task) {
                        if error?.code == NSURLErrorCancelled || error == nil {
                            self.downloads.removeValue(forKey: key)
                            
                            if error == nil {
                                self.delegate?.downloadRequestFinished?(downloadModel)
                            } else {
                                self.delegate?.downloadRequestCanceled?(downloadModel)
                            }
                            
                        } else {
                            let resumeData = error?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
                            var newTask = task
                            if self.isValidResumeData(resumeData) == true {
                                newTask = self.sessionManager.downloadTask(withResumeData: resumeData!)
                            } else {
                                newTask = self.sessionManager.downloadTask(with: URL(string: downloadModel.fileURL)!)
                            }
                            
                            newTask.taskDescription = task.taskDescription
                            downloadModel.status = TaskStatus.failed.description()
                            downloadModel.task = newTask as? URLSessionDownloadTask
                            
                            if let error = error {
                                self.delegate?.downloadRequestDidFailedWithError?(error, downloadModel: downloadModel)
                            } else {
                                let error: NSError = NSError(domain: "ZENDownloadManagerDomain", code: 1000, userInfo: [NSLocalizedDescriptionKey : "Unknown error occurred"])
                                
                                self.delegate?.downloadRequestDidFailedWithError?(error, downloadModel: downloadModel)
                            }
                        }
                        break;
                    }
                }
            }
        }
    }
    
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        
        if let backgroundCompletion = self.backgroundSessionCompletionHandler {
            DispatchQueue.main.async(execute: {
                backgroundCompletion()
            })
        }
        debugPrint("All tasks are finished")
        
    }
}

//MARK: Public Helper Functions

extension ZENDownloadManager {
    
    public func addDownloadTask(_ fileName: String, fileURL: String, destinationPath: String) {
        
        let url = URL(string: fileURL as String)!
        let request = URLRequest(url: url)
        
        let downloadTask = sessionManager.downloadTask(with: request)
        downloadTask.taskDescription = [fileName, fileURL, destinationPath].joined(separator: ",")
        downloadTask.resume()
        
        debugPrint("session manager:\(sessionManager) url:\(url) request:\(request)")
        
        let downloadModel = ZENDownloadModel.init(fileName: fileName, fileURL: fileURL, destinationPath: destinationPath)
        downloadModel.startTime = Date()
        downloadModel.status = TaskStatus.downloading.description()
        downloadModel.task = downloadTask
        
        downloads[fileName] = downloadModel
        delegate?.downloadRequestStarted?(downloadModel, index: downloads.count - 1)
    }
    
    public func addDownloadTask(_ fileName: String, fileURL: String) {
        addDownloadTask(fileName, fileURL: fileURL, destinationPath: "")
    }
    
    public func pauseDownloadTaskForKey(_ key: String) {
        
        let downloadModel = downloads[key]
        
        guard downloadModel?.status != TaskStatus.paused.description() else {
            return
        }
        
        let downloadTask = downloadModel?.task
        downloadTask!.suspend()
        downloadModel?.status = TaskStatus.paused.description()
        downloadModel?.startTime = Date()
        
        delegate?.downloadRequestDidPaused?(downloadModel!)
    }
    
    public func resumeDownloadTaskForKey(_ key: String) {
        
        let downloadModel = downloads[key]
        
        guard downloadModel?.status != TaskStatus.downloading.description() else {
            return
        }
        
        let downloadTask = downloadModel?.task
        downloadTask!.resume()
        downloadModel?.status = TaskStatus.downloading.description()
        
        delegate?.downloadRequestDidResumed?(downloadModel!)
    }
    
    public func retryDownloadTaskForKey(_ key: String) {
        let downloadModel = downloads[key]
        
        guard downloadModel?.status != TaskStatus.downloading.description() else {
            return
        }
        
        let downloadTask = downloadModel?.task
        
        downloadTask!.resume()
        downloadModel?.status = TaskStatus.downloading.description()
        downloadModel?.startTime = Date()
        downloadModel?.task = downloadTask
    }
    
    public func cancelTaskForKey(_ key: String) {
        if let downloadInfo = downloads[key], let downloadTask = downloadInfo.task {
            downloadTask.cancel()
        }
    }
    
    public func removeDownloadForKey(_ key: String) {
        self.downloads.removeValue(forKey: key)
    }
    
    public func presentNotificationForDownload(_ notifAction: String, notifBody: String) {
        let application = UIApplication.shared
        let applicationState = application.applicationState
        
        if applicationState == UIApplicationState.background {
            let localNotification = UILocalNotification()
            localNotification.alertBody = notifBody
            localNotification.alertAction = notifAction
            localNotification.soundName = UILocalNotificationDefaultSoundName
            localNotification.applicationIconBadgeNumber += 1
            application.presentLocalNotificationNow(localNotification)
        }
    }
}
