//
//  WebCacheManager.swift
//  iOSJavascriptPlayground
//
//  Created by Jim Learning on 2025/2/5.
//

import Foundation
import WebKit
import CryptoKit

/// url scheme
let urlScheme = "cachedhttp"

// 缓存管理
class WebCacheManager: NSObject {
    
    static let shared = WebCacheManager()

    // 缓存目录
    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    // 活跃任务管理
    private var activeTasks = [ObjectIdentifier: WKURLSchemeTask]()
    private let taskQueue = DispatchQueue(label: "com.WebCacheManager.taskqueue")
    
    private override init() {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("WebCache")
        super.init()
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}

// MARK: - 缓存处理

extension WebCacheManager {
    
    // 计算数据哈希
    func calculateHash(for data: Data) -> String {
        return SHA256.hash(data: data).map { String(format: "%02hhx", $0) }.joined()
    }
    
    func getCachedData(for url: URL) -> Data? {
        let fileURL = cacheDirectory.appendingPathComponent(cacheKey(for: url))
        print("缓存路径：\(fileURL.path)") // 添加调试日志
        return try? Data(contentsOf: fileURL)
    }
    
    func updateCacheIfNeeded(for url: URL, data: Data) -> Bool {
        let newHash = calculateHash(for: data)
        let oldHash = getCachedData(for: url).flatMap { calculateHash(for: $0) }
        if oldHash == newHash {
            return false
        }
        updateCache(for: url, data: data)
        return true
    }
    
    func updateCache(for url: URL, data: Data) {
        let fileURL = cacheDirectory.appendingPathComponent(cacheKey(for: url))
        try? data.write(to: fileURL)
    }
    
    func cacheKey(for url: URL) -> String {
        return url.absoluteString.sha256() // 需要添加SHA256扩展
    }
}

// MARK: - 滚动位置缓存处理

extension WebCacheManager {
    
    func saveScrollPosition(_ position: CGPoint, for url: URL) {
        let data = try? NSKeyedArchiver.archivedData(
            withRootObject: position,
            requiringSecureCoding: false
        )
        UserDefaults.standard.set(data, forKey: scrollPositionKey(for: url))
    }
    
    func getScrollPosition(for url: URL) -> CGPoint {
        guard let data = UserDefaults.standard.data(forKey: scrollPositionKey(for: url)),
            let position = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSValue.self, from: data)
        else {
            return .zero
        }
        return position.cgPointValue
    }
    
    private func scrollPositionKey(for url: URL) -> String {
        return "scroll_\(cacheKey(for: url))"
    }
}

extension WebCacheManager: WKURLSchemeHandler {
    
    // 修改 start 方法
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let taskID = ObjectIdentifier(urlSchemeTask)
        taskQueue.sync {
            activeTasks[taskID] = urlSchemeTask
        }
        
        guard let url = urlSchemeTask.request.url else { return }
        let originalURL = url.withScheme(urlScheme)!
        
        if let cachedData = getCachedData(for: originalURL) {
            sendResponse(data: cachedData, to: urlSchemeTask, taskID: taskID)
            return
        }
        
        URLSession.shared.dataTask(with: originalURL) { [weak self, taskID] data, response, error in
            guard let self = self else { return }
            
            self.taskQueue.sync {
                guard self.activeTasks[taskID] != nil else { return }
            }
            
            guard let data = data else {
                self.sendError(to: urlSchemeTask, taskID: taskID)
                return
            }
            
            self.updateCache(for: originalURL, data: data)
            self.sendResponse(data: data, to: urlSchemeTask, taskID: taskID)
        }.resume()
    }

    // 修改 stop 方法
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        let taskID = ObjectIdentifier(urlSchemeTask)
        _ = taskQueue.sync {
            activeTasks.removeValue(forKey: taskID)
        }
    }
    
    private func sendResponse(data: Data, to task: WKURLSchemeTask, taskID: ObjectIdentifier) {
        taskQueue.sync {
            guard activeTasks[taskID] != nil else { return }
            
            let response = URLResponse(
                url: task.request.url!,
                mimeType: "text/html",
                expectedContentLength: data.count,
                textEncodingName: "utf-8"
            )
            
            DispatchQueue.main.async {
                self.taskQueue.sync {
                    guard self.activeTasks[taskID] != nil else { return }
                }
                
                task.didReceive(response)
                task.didReceive(data)
                task.didFinish()
                
                _ = self.taskQueue.sync {
                    self.activeTasks.removeValue(forKey: taskID)
                }
            }
        }
    }
    
    private func sendError(to task: WKURLSchemeTask,  taskID: ObjectIdentifier) {
        taskQueue.sync {
            guard activeTasks[taskID] != nil else { return }
            
            let error = NSError(domain: "WebCacheManagerError", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "Failed to load resource"
            ])
            
            DispatchQueue.main.async {
                guard self.activeTasks[taskID] != nil else { return }
                task.didFailWithError(error)
                self.activeTasks.removeValue(forKey: taskID)
            }
        }
    }
}
