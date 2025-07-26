//
//  InstaGoApp.swift
//  InstaGo
//
//  Created by 陈瀚翔 on 23/7/2025.
//

import SwiftUI

@main
struct InstaGoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var serverManager = ServerManager.shared
    
    var body: some Scene {
        MenuBarExtra("InstaGo", image: "instago-icon") {
            MenuBarContent()
                .environmentObject(appState)
                .environmentObject(serverManager)
        }
        .menuBarExtraStyle(.window)
    }
}

// 应用状态管理
class AppState: ObservableObject {
    @Published var isFloatingWindowVisible = true
    @Published var serverURL = "http://localhost:8080/upload" // 默认服务端地址
    @Published var imageLabel = "" // 图片标签文字
    @Published var isFloatingWindowExpanded = false // 悬浮窗是否展开
    @Published var isFloatingWindowSelected = false // 悬浮窗是否被选中
    @Published var isOnlineMode = true // 是否为在线模式，默认为在线模式
    
    // 用户认证相关
    @Published var isLoggedIn = false // 用户是否已登录
    @Published var userInfo: UserInfo? = nil // 用户信息
    @Published var authToken: String? = nil // 认证access token
    @Published var refreshToken: String? = nil // 刷新token
    
    // 回调处理状态
    private var lastCallbackURL: String? = nil // 最后处理的回调URL
    private var callbackProcessingTime: Date? = nil // 上次处理回调的时间
    private let callbackCooldownDuration: TimeInterval = 5.0 // 回调处理冷却时间（秒）
    
    // 在线 API 地址
          let onlineAPIURL = "https://instago-server-fbtibvhmga-uc.a.run.app/api/v1/screenshot"
    let loginWebURL = "https://instago-manage.vercel.app/login" // 登录页面地址
    
    init() {
        // 延迟发送初始化通知（减少延迟以加快启动）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: NSNotification.Name("InitializeFloatingPanel"), object: self)
            print("🚀 发送FloatingPanel初始化通知")
        }
        
        // 尝试从本地恢复登录状态
        loadSavedAuthState()
        
        // 检查是否需要登录，如果是在线模式且未登录，自动启动登录流程
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if self.requiresLogin {
                print("🔐 检测到在线模式且未登录，自动启动登录流程")
                self.startLoginFlow()
            } else if self.isOnlineMode && self.isLoggedIn {
                print("✅ 在线模式，用户已登录: \(self.userInfo?.name ?? "未知用户")")
            } else {
                print("ℹ️ 本地模式，无需登录")
            }
        }
        
        // 监听登录回调通知
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("LoginCallback"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            print("📬 AppState收到LoginCallback通知")
            if let url = notification.userInfo?["url"] as? URL {
                print("📬 从通知中提取URL: \(url)")
                self?.handleLoginCallback(url: url)
            } else {
                print("❌ 通知中没有找到URL")
            }
        }
        
        // 监听token刷新请求通知
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("RequestTokenRefresh"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            print("📬 AppState收到RequestTokenRefresh通知")
            if let completionBlock = notification.userInfo?["completion"] as? (Bool, String?) -> Void {
                self?.refreshAccessToken { success in
                    let newToken = success ? self?.authToken : nil
                    completionBlock(success, newToken)
                }
            }
        }
        
        print("🎯 AppState初始化完成，已注册登录回调监听器")
    }
    
    func toggleFloatingWindow() {
        isFloatingWindowVisible.toggle()
    }
    
    // 悬浮窗选中状态管理
    func selectFloatingWindow() {
        isFloatingWindowSelected = true
        print("🎯 悬浮窗已选中")
    }
    
    func deselectFloatingWindow() {
        isFloatingWindowSelected = false
        print("🎯 悬浮窗已取消选中")
    }
    
    func toggleFloatingWindowSelection() {
        isFloatingWindowSelected.toggle()
        print("🎯 悬浮窗选中状态切换: \(isFloatingWindowSelected ? "选中" : "取消选中")")
    }
    
    func expandFloatingWindow() {
        isFloatingWindowExpanded = true
        NotificationCenter.default.post(name: NSNotification.Name("ExpandFloatingPanel"), object: nil)
    }
    
    func collapseFloatingWindow() {
        isFloatingWindowExpanded = false
        NotificationCenter.default.post(name: NSNotification.Name("CollapseFloatingPanel"), object: nil)
    }
    
    func updateImageLabel(_ text: String) {
        // 限制最多16个字符
        let trimmed = String(text.prefix(16))
        imageLabel = trimmed
    }
    
    // 切换本地/在线模式
    func toggleMode() {
        isOnlineMode.toggle()
        print("🔄 切换模式: \(isOnlineMode ? "在线" : "本地")")
        
        // 发送模式切换通知
        NotificationCenter.default.post(
            name: NSNotification.Name("ModeChanged"),
            object: nil,
            userInfo: ["isOnlineMode": isOnlineMode]
        )
    }
    
    // 获取当前模式描述
    var modeDescription: String {
        return isOnlineMode ? "在线模式" : "本地模式"
    }
    
    // 获取当前应该使用的上传 URL
    var currentUploadURL: String {
        return isOnlineMode ? onlineAPIURL : serverURL
    }
    
    // MARK: - 用户认证相关方法
    
    // 开始登录流程
    func startLoginFlow() {
        print("🔐 开始登录流程")
        
        // 构建登录URL，包含回调scheme
        let callbackURL = "instago://auth"
        let encodedCallback = callbackURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let loginURL = "\(loginWebURL)?callback=\(encodedCallback)"
        
        // 打开默认浏览器
        if let url = URL(string: loginURL) {
            NSWorkspace.shared.open(url)
            print("🌐 打开登录页面: \(loginURL)")
        } else {
            print("❌ 无效的登录URL: \(loginURL)")
        }
    }
    
    // 处理登录回调
    func handleLoginCallback(url: URL) {
        print("🔔 AppState收到登录回调: \(url)")
        print("🔍 完整URL: \(url.absoluteString)")
        
        // 检查是否是重复的回调请求
        let currentURLString = url.absoluteString
        let currentTime = Date()
        
        // 如果是相同的URL且在冷却时间内，忽略此请求
        if let lastURL = lastCallbackURL,
           let lastTime = callbackProcessingTime,
           lastURL == currentURLString,
           currentTime.timeIntervalSince(lastTime) < callbackCooldownDuration {
            print("⏰ 检测到重复回调请求，忽略处理（冷却时间: \(callbackCooldownDuration)秒）")
            print("   上次处理时间: \(lastTime)")
            print("   当前时间: \(currentTime)")
            print("   时间间隔: \(currentTime.timeIntervalSince(lastTime))秒")
            return
        }
        
        // 如果用户已经登录，询问是否要重新登录
        if isLoggedIn {
            print("⚠️ 用户已登录，收到新的登录回调")
            print("   当前用户: \(userInfo?.name ?? "未知")")
            
            // 显示用户选择对话框
            DispatchQueue.main.async {
                self.showReloginDialog(for: url)
            }
            return
        }
        
        // 记录此次回调处理
        lastCallbackURL = currentURLString
        callbackProcessingTime = currentTime
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            print("❌ 无法解析回调URL")
            print("🔍 URL Components: \(URLComponents(url: url, resolvingAgainstBaseURL: false)?.debugDescription ?? "nil")")
            return
        }
        
        // 处理登录回调
        processLoginCallback(url: url)
    }
    
    // 显示重新登录对话框
    private func showReloginDialog(for url: URL) {
        let alert = NSAlert()
        alert.messageText = "用户已登录"
        alert.informativeText = "检测到新的登录回调，但您已经登录。是否要重新登录？"
        alert.addButton(withTitle: "重新登录")
        alert.addButton(withTitle: "保持当前登录")
        alert.alertStyle = .warning
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            print("🔄 用户选择重新登录")
            // 先登出，然后处理新的回调
            logout()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.processLoginCallback(url: url)
            }
        } else {
            print("🚫 用户选择保持当前登录，忽略回调")
        }
    }
    
    // 处理登录回调的核心逻辑
    private func processLoginCallback(url: URL) {
        // 记录此次回调处理
        lastCallbackURL = url.absoluteString
        callbackProcessingTime = Date()
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            print("❌ 无法解析回调URL")
            return
        }
        
        print("📝 解析到的查询参数:")
        for item in queryItems {
            print("   \(item.name) = \(item.value ?? "nil")")
        }
        
        var token: String?
        var refreshTokenValue: String?
        var userName: String?
        var userEmail: String?
        var userId: String?
        
        // 解析查询参数
        for item in queryItems {
            switch item.name {
            case "token", "access_token":
                token = item.value
                print("🔐 找到access token: \(token?.prefix(20) ?? "nil")...")
            case "refresh_token":
                refreshTokenValue = item.value
                print("🔄 找到refresh token: \(refreshTokenValue?.prefix(20) ?? "nil")...")
            case "user_name":
                userName = item.value
                print("👤 找到用户名: \(userName ?? "nil")")
            case "user_email":
                userEmail = item.value
                print("📧 找到邮箱: \(userEmail ?? "nil")")
            case "user_id":
                userId = item.value
                print("🆔 找到用户ID: \(userId ?? "nil")")
            default:
                print("❓ 未知参数: \(item.name) = \(item.value ?? "nil")")
                break
            }
        }
        
        guard let authToken = token, !authToken.isEmpty else {
            print("❌ 登录回调中缺少token")
            return
        }
        
        // 创建用户信息
        let user = UserInfo(
            id: userId ?? "",
            name: userName ?? "未知用户",
            email: userEmail ?? ""
        )
        
        print("👥 创建用户信息: \(user)")
        
        // 更新登录状态
        DispatchQueue.main.async {
            self.authToken = authToken
            self.refreshToken = refreshTokenValue
            self.userInfo = user
            self.isLoggedIn = true
            
            print("✅ 登录成功: \(user.name)")
            if refreshTokenValue != nil {
                print("🔄 已保存refresh token")
            } else {
                print("⚠️ 未收到refresh token，将无法自动刷新")
            }
            print("🔄 更新UI状态...")
            
            // 保存登录状态到本地
            self.saveAuthState()
        }
    }
    
    // 登出
    func logout() {
        print("👋 用户登出")
        
        DispatchQueue.main.async {
            self.isLoggedIn = false
            self.authToken = nil
            self.refreshToken = nil
            self.userInfo = nil
            
            // 清除本地保存的登录状态
            self.clearSavedAuthState()
            
            // 清除回调记录，允许新的登录
            self.lastCallbackURL = nil
            self.callbackProcessingTime = nil
            
            print("🧹 已清除登录状态和回调记录")
        }
    }
    
    // 检查是否需要登录（仅在线模式需要）
    var requiresLogin: Bool {
        return isOnlineMode && !isLoggedIn
    }
    
    // 检查是否有可用的refresh token
    var hasRefreshToken: Bool {
        return refreshToken != nil && !refreshToken!.isEmpty
    }
    
    // 刷新访问令牌
    func refreshAccessToken(completion: @escaping (Bool) -> Void) {
        guard let refreshToken = refreshToken, !refreshToken.isEmpty else {
            print("❌ 没有refresh token，无法刷新")
            completion(false)
            return
        }
        
        print("🔄 尝试使用refresh token刷新access token")
        
        // 调用ServerManager的刷新方法
        ServerManager.shared.refreshToken(refreshToken: refreshToken) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let tokens):
                    print("✅ Token刷新成功")
                    self?.authToken = tokens["access_token"] as? String
                    if let newRefreshToken = tokens["refresh_token"] as? String {
                        self?.refreshToken = newRefreshToken
                        print("🔄 同时更新了refresh token")
                    }
                    self?.saveAuthState()
                    completion(true)
                    
                case .failure(let error):
                    print("❌ Token刷新失败: \(error.localizedDescription)")
                    // 刷新失败，可能refresh token也过期了，需要重新登录
                    self?.logout()
                    completion(false)
                }
            }
        }
    }
    
    // MARK: - 本地存储
    
    private func saveAuthState() {
        guard let token = authToken, let user = userInfo else { return }
        
        UserDefaults.standard.set(token, forKey: "InstaGo.AuthToken")
        if let refreshToken = refreshToken {
            UserDefaults.standard.set(refreshToken, forKey: "InstaGo.RefreshToken")
        }
        UserDefaults.standard.set(user.id, forKey: "InstaGo.UserID")
        UserDefaults.standard.set(user.name, forKey: "InstaGo.UserName")
        UserDefaults.standard.set(user.email, forKey: "InstaGo.UserEmail")
        
        print("💾 登录状态已保存 (含\(refreshToken != nil ? "" : "不含")refresh token)")
    }
    
    private func loadSavedAuthState() {
        guard let token = UserDefaults.standard.string(forKey: "InstaGo.AuthToken"),
              let userId = UserDefaults.standard.string(forKey: "InstaGo.UserID"),
              let userName = UserDefaults.standard.string(forKey: "InstaGo.UserName"),
              let userEmail = UserDefaults.standard.string(forKey: "InstaGo.UserEmail") else {
            print("📱 未找到保存的登录状态")
            return
        }
        
        authToken = token
        refreshToken = UserDefaults.standard.string(forKey: "InstaGo.RefreshToken") // 可能为nil
        userInfo = UserInfo(id: userId, name: userName, email: userEmail)
        isLoggedIn = true
        
        print("📱 已恢复登录状态: \(userName) (含\(refreshToken != nil ? "" : "不含")refresh token)")
    }
    
    private func clearSavedAuthState() {
        UserDefaults.standard.removeObject(forKey: "InstaGo.AuthToken")
        UserDefaults.standard.removeObject(forKey: "InstaGo.RefreshToken")
        UserDefaults.standard.removeObject(forKey: "InstaGo.UserID")
        UserDefaults.standard.removeObject(forKey: "InstaGo.UserName")
        UserDefaults.standard.removeObject(forKey: "InstaGo.UserEmail")
        
        print("🗑️ 已清除保存的登录状态")
    }
}

// 用户信息模型
struct UserInfo {
    let id: String
    let name: String
    let email: String
}

// 应用委托
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🎯 应用启动完成")
        
        // 设置应用不在Dock中显示（由于Info.plist中设置了LSUIElement，这行可以注释掉）
        // NSApp.setActivationPolicy(.accessory)
        
        // 注册URL事件处理
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        
        // 确保 FloatingPanelManager 单例被创建，这样通知监听器就会被设置
        _ = FloatingPanelManager.shared
        print("🏗️ FloatingPanelManager 单例已创建")
        
        // 启动服务器
        ServerManager.shared.applicationDidFinishLaunching()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        print("👋 应用即将退出")
        
        // 停止服务器
        ServerManager.shared.applicationWillTerminate()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // 即使关闭所有窗口也不退出应用
    }
    
    // 当应用已经运行并接收到URL scheme时调用
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        print("🔄 应用重新打开请求，有可见窗口: \(flag)")
        
        // 如果没有可见窗口，显示悬浮窗
        if !flag {
            DispatchQueue.main.async {
                FloatingPanelManager.shared.showPanel()
            }
        }
        
        return true
    }
    
    // 处理URL Scheme回调
    @objc func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else {
            print("❌ 无法解析URL事件")
            return
        }
        
        print("🔗 收到URL事件: \(urlString)")
        print("🔍 URL Components - scheme: \(url.scheme ?? "nil"), host: \(url.host ?? "nil")")
        print("🔍 Query: \(url.query ?? "nil")")
        
        // 检查当前运行的InstaGo实例数量
        let runningInstances = getRunningInstanceCount()
        print("📊 当前运行的InstaGo实例数: \(runningInstances)")
        
        if runningInstances > 1 {
            print("⚠️ 检测到多个InstaGo实例，尝试关闭额外的实例")
            terminateExtraInstances()
        }
        
        // 激活应用到前台（确保应用获得焦点）
        NSApp.activate(ignoringOtherApps: true)
        
        // 检查是否为登录回调
        if url.scheme == "instago" && url.host == "auth" {
            print("✅ 确认为登录回调，激活应用并发送通知")
            
            // 确保悬浮窗可见（如果需要的话）
            DispatchQueue.main.async {
                FloatingPanelManager.shared.showPanel()
            }
            
            // 通过通知发送登录回调
            notifyLoginCallback(url: url)
        } else {
            print("⚠️ 不是预期的登录回调格式")
        }
    }
    
    // 获取当前运行的InstaGo实例数量
    private func getRunningInstanceCount() -> Int {
        let runningApps = NSWorkspace.shared.runningApplications
        let instagoInstances = runningApps.filter { app in
            return app.bundleIdentifier == "adxinstago.InstaGo" ||
                   app.localizedName?.contains("InstaGo") == true
        }
        return instagoInstances.count
    }
    
    // 终止额外的实例，保留当前实例
    private func terminateExtraInstances() {
        let runningApps = NSWorkspace.shared.runningApplications
        let instagoInstances = runningApps.filter { app in
            return app.bundleIdentifier == "adxinstago.InstaGo" ||
                   app.localizedName?.contains("InstaGo") == true
        }
        
        let currentPID = ProcessInfo.processInfo.processIdentifier
        
        for app in instagoInstances {
            if app.processIdentifier != currentPID {
                print("🔚 尝试终止额外的InstaGo实例 (PID: \(app.processIdentifier))")
                app.terminate()
            }
        }
    }
    
    // 通过通知处理登录回调
    private func notifyLoginCallback(url: URL) {
        print("📨 发送登录回调通知: \(url)")
        NotificationCenter.default.post(
            name: NSNotification.Name("LoginCallback"),
            object: nil,
            userInfo: ["url": url]
        )
        print("📨 通知已发送")
    }
}
