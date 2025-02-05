//
//  WebViewController.swift
//  iOSJavascriptPlayground
//
//  Created by Jim Learning on 2025/2/5.
//

import UIKit
import WebKit

class WebViewController: UIViewController {
    
    let webView: WKWebView
    let url: URL
    let progressView = UIProgressView(progressViewStyle: .bar)
    
    init(url: URL) {
        self.url = url
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(CacheManager.shared, forURLScheme: "cachedhttp")
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init(nibName: nil, bundle: nil)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupWebView()
        loadContent()
    }

        private var scrollPosition: CGPoint = .zero
    private var positionObserver: NSKeyValueObservation?
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveScrollPosition()
    }
    
    private func saveScrollPosition() {
        webView.evaluateJavaScript("""
            [window.scrollX, window.scrollY]
        """) { [weak self] result, _ in
            guard let self = self,
                let position = result as? [CGFloat],
                position.count == 2 else { return }
            
            CacheManager.shared.saveScrollPosition(
                CGPoint(x: position[0], y: position[1]),
                for: self.url
            )
        }
    }
    
    private func restoreScrollPosition() {
        let position = CacheManager.shared.getScrollPosition(for: url)
        webView.evaluateJavaScript("""
            window.scrollTo(\(position.x), \(position.y));
        """)
    }
    
    private func setupScrollObserver() {
        positionObserver = webView.scrollView.observe(\.contentOffset) { [weak self] scrollView, _ in
            guard let self = self else { return }
            CacheManager.shared.saveScrollPosition(scrollView.contentOffset, for: self.url)
        }
    }
    
    private func setupWebView() {
        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        webView.navigationDelegate = self

        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)
    }
    
    private func loadContent() {
        guard let cachedURL = url.withScheme("cachedhttp") else {
            print("Invalid URL scheme conversion")
            return
        }
        
        let cachedRequest = URLRequest(url: cachedURL)
        webView.load(cachedRequest)

        // 后台更新缓存（保持不变）
        URLSession.shared.dataTask(with: url) { data, response, _ in
            guard let data = data else { return }
            CacheManager.shared.updateCache(for: self.url, data: data)
            DispatchQueue.main.async {
                self.webView.load(cachedRequest)
            }
        }.resume()
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "estimatedProgress" {
            progressView.progress = Float(webView.estimatedProgress)
        }
    }
    
    deinit {
        webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// CacheManager.swift - 缓存管理
class CacheManager: NSObject, WKURLSchemeHandler {
    
    static let shared = CacheManager()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    private override init() {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("WebCache")
        super.init()
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - 缓存处理
    func cacheKey(for url: URL) -> String {
        return url.absoluteString.sha256() // 需要添加SHA256扩展
    }
    
    func getCachedData(for url: URL) -> Data? {
        let fileURL = cacheDirectory.appendingPathComponent(cacheKey(for: url))
        print("缓存路径：\(fileURL.path)") // 添加调试日志
        return try? Data(contentsOf: fileURL)
    }
    
    func updateCache(for url: URL, data: Data) {
        let fileURL = cacheDirectory.appendingPathComponent(cacheKey(for: url))
        try? data.write(to: fileURL)
    }
    
    private var activeTasks = [ObjectIdentifier: WKURLSchemeTask]()
    private let taskQueue = DispatchQueue(label: "com.cachemanager.taskqueue")
    
    // 修改start方法
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let taskID = ObjectIdentifier(urlSchemeTask)
        taskQueue.sync {
            activeTasks[taskID] = urlSchemeTask
        }
        
        guard let url = urlSchemeTask.request.url else { return }
        let originalURL = url.withScheme("http")!
        
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
    
    // 修改sendResponse方法
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

    // 修改stop方法
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        let taskID = ObjectIdentifier(urlSchemeTask)
        _ = taskQueue.sync {
            activeTasks.removeValue(forKey: taskID)
        }
    }
    
    private func sendError(to task: WKURLSchemeTask,  taskID: ObjectIdentifier) {
        taskQueue.sync {
            guard activeTasks[taskID] != nil else { return }
            
            let error = NSError(domain: "CacheManagerError", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "Failed to load resource"
            ])
            
            DispatchQueue.main.async {
                guard self.activeTasks[taskID] != nil else { return }
                task.didFailWithError(error)
                self.activeTasks.removeValue(forKey: taskID)
            }
        }
    }

    // 添加滚动位置存储功能
    private func scrollPositionKey(for url: URL) -> String {
        return "scroll_\(cacheKey(for: url))"
    }
    
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
}

extension WebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        restoreScrollPosition()
        setupScrollObserver()
    }
}