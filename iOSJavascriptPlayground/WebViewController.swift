//
//  WebViewController.swift
//  iOSJavascriptPlayground
//
//  Created by Jim Learning on 2025/2/5.
//

import UIKit
import WebKit

/** 缓存处理逻辑
 * 1. 初次加载 → 立即设置目标位置 → 内容加载后校准 → 正确恢复 ✅
 * 2. 用户滚动 → 实时保存新位置 ✅
 * 3. 内容更新 → 保持用户当前滚动位置 ✅
 * 4. 重新打开 → 恢复上次退出时的位置 ✅
 */

class WebViewController: UIViewController {
    
    // MARK: - 属性声明
    
    let webView: WKWebView
    let url: URL
    let progressView = UIProgressView(progressViewStyle: .bar)
    
    /// 滚动位置锁定状态
    private var positionLock = false
    /// 初始加载标识
    private var isInitialLoad = true
    /// 滚动位置观察者
    private var positionObserver: NSKeyValueObservation?
    /// 当前滚动位置
    private var scrollPosition: CGPoint = .zero
    /// url scheme
    private let urlScheme = "cachedhttp"
    
    // MARK: - 初始化方法
    
    init(url: URL) {
        self.url = url
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(WebCacheManager.shared, forURLScheme: urlScheme)
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        removeObservers()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupWebView()
        addObservers()
        loadContent()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveScrollPosition()
    }
    
    // MARK: - 配置方法
    
    /// 配置WebView基础属性
    
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
        webView.scrollView.delegate = self
        
        view.addSubview(progressView)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 1),
        ])
    }
}

extension WebViewController {
    
    // MARK: - 核心业务逻辑
    
    /// 加载内容主方法
    private func loadContent() {
        guard let cachedURL = url.withScheme(urlScheme) else { return }
        
        handleInitialLoad(cachedURL: cachedURL)
        fetchAndUpdateContent(cachedURL: cachedURL)
        isInitialLoad = false
    }
    
    /// 处理初始加载逻辑
    private func handleInitialLoad(cachedURL: URL) {
        guard isInitialLoad else { return }
        
        let targetPosition = WebCacheManager.shared.getScrollPosition(for: url)
        positionLock = true
        webView.scrollView.setContentOffset(targetPosition, animated: false)
        
        loadCachedContent(cachedURL: cachedURL)
    }
    
    /// 加载缓存内容
    private func loadCachedContent(cachedURL: URL) {
        guard let cachedData = WebCacheManager.shared.getCachedData(for: url) else { return }
        webView.load(cachedData, mimeType: "text/html", characterEncodingName: "utf-8", baseURL: cachedURL)
    }
    
    /// 获取并更新内容
    private func fetchAndUpdateContent(cachedURL: URL) {
        URLSession.shared.dataTask(with: url) { [weak self] data, response, _ in
            guard let self = self, let data = data else { return }
            WebCacheManager.shared.updateCache(for: self.url, data: data)
            
            DispatchQueue.main.async {
                self.handleContentUpdate(cachedURL: cachedURL)
            }
        }.resume()
    }
    
    /// 处理内容更新
    private func handleContentUpdate(cachedURL: URL) {
        guard let cachedData = WebCacheManager.shared.getCachedData(for: url) else {
            return
        }
        UIView.performWithoutAnimation {
            let currentOffset = webView.scrollView.contentOffset
            webView.load(cachedData, mimeType: "text/html", characterEncodingName: "utf-8", baseURL: cachedURL)
            webView.scrollView.setContentOffset(currentOffset, animated: false)
        }
    }
    
    /// 保存滚动位置
    private func saveScrollPosition() {
        let javaScriptString = "[window.scrollX, window.scrollY]"
        webView.evaluateJavaScript(javaScriptString) { [weak self] result, _ in
            guard let self = self,
                  let position = result as? [CGFloat],
                  position.count == 2 else { return }
            
            WebCacheManager.shared.saveScrollPosition(
                CGPoint(x: position[0], y: position[1]),
                for: self.url
            )
        }
    }
}

// MARK: - KVO观察者方法

extension WebViewController {
    
    func addObservers() {
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)
    }
    
    func removeObservers() {
        webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress))
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath == "estimatedProgress" else { return }
        let progress =  Float(webView.estimatedProgress)
        progressView.progress = progress
        progressView.isHidden = progress >= 1.0
    }
}

// MARK: - WKNavigationDelegate 导航代理

extension WebViewController: WKNavigationDelegate {
    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        positionLock = true
    }
    
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        // 阶段3：内容提交时锁定
        let targetPosition = WebCacheManager.shared.getScrollPosition(for: url)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            webView.scrollView.setContentOffset(targetPosition, animated: false)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard isInitialLoad else { return }
        
        // 缩短校准延迟并确保释放锁定
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.positionLock = false
            self.isInitialLoad = false
            // 最终校准改为异步JavaScript执行
            let targetPosition = WebCacheManager.shared.getScrollPosition(for: self.url)
            self.webView.evaluateJavaScript("window.scrollTo(\(targetPosition.x), \(targetPosition.y))")
        }
    }
}

// MARK: - UIScrollViewDelegate 滚动代理

extension WebViewController: UIScrollViewDelegate {
    
    // 处理滚动事件
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if positionLock {
            // 仅在加载阶段强制保持位置
            scrollView.setContentOffset(
                WebCacheManager.shared.getScrollPosition(for: url),
                animated: false
            )
        } else {
            // 实时保存用户滚动的位置
            WebCacheManager.shared.saveScrollPosition(scrollView.contentOffset, for: url)
        }
    }
    
    // 新增方法：处理滚动开始事件
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // 用户开始手动滚动时立即释放锁定
        positionLock = false
    }
}
