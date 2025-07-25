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
        MenuBarExtra("InstaGo", systemImage: "photo.circle") {
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
    @Published var isOnlineMode = false // 是否为在线模式，默认为本地模式
    
    // 用户认证相关
    @Published var isLoggedIn = false // 用户是否已登录
    @Published var userInfo: UserInfo? = nil // 用户信息
    @Published var authToken: String? = nil // 认证token
    
    // 在线 API 地址
    let onlineAPIURL = "https://82540c0ac675.ngrok-free.app/api/v1/screenshot"
    let loginWebURL = "http://localhost:3000/login" // 登录页面地址
    
    init() {
        // 延迟发送初始化通知
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(name: NSNotification.Name("InitializeFloatingPanel"), object: self)
            print("🚀 发送FloatingPanel初始化通知")
        }
        
        // 尝试从本地恢复登录状态
        loadSavedAuthState()
        
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
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            print("❌ 无法解析回调URL")
            print("🔍 URL Components: \(URLComponents(url: url, resolvingAgainstBaseURL: false)?.debugDescription ?? "nil")")
            return
        }
        
        print("📝 解析到的查询参数:")
        for item in queryItems {
            print("   \(item.name) = \(item.value ?? "nil")")
        }
        
        var token: String?
        var userName: String?
        var userEmail: String?
        var userId: String?
        
        // 解析查询参数
        for item in queryItems {
            switch item.name {
            case "token":
                token = item.value
                print("🔐 找到token: \(token?.prefix(20) ?? "nil")...")
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
            self.userInfo = user
            self.isLoggedIn = true
            
            print("✅ 登录成功: \(user.name)")
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
            self.userInfo = nil
            
            // 清除本地保存的登录状态
            self.clearSavedAuthState()
        }
    }
    
    // 检查是否需要登录（仅在线模式需要）
    var requiresLogin: Bool {
        return isOnlineMode && !isLoggedIn
    }
    
    // MARK: - 本地存储
    
    private func saveAuthState() {
        guard let token = authToken, let user = userInfo else { return }
        
        UserDefaults.standard.set(token, forKey: "InstaGo.AuthToken")
        UserDefaults.standard.set(user.id, forKey: "InstaGo.UserID")
        UserDefaults.standard.set(user.name, forKey: "InstaGo.UserName")
        UserDefaults.standard.set(user.email, forKey: "InstaGo.UserEmail")
        
        print("💾 登录状态已保存")
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
        userInfo = UserInfo(id: userId, name: userName, email: userEmail)
        isLoggedIn = true
        
        print("📱 已恢复登录状态: \(userName)")
    }
    
    private func clearSavedAuthState() {
        UserDefaults.standard.removeObject(forKey: "InstaGo.AuthToken")
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
        
        // 设置应用不在Dock中显示
        NSApp.setActivationPolicy(.accessory)
        
        // 注册URL事件处理
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        
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
        
        // 检查是否为登录回调
        if url.scheme == "instago" && url.host == "auth" {
            print("✅ 确认为登录回调，发送通知")
            // 通过通知发送登录回调
            notifyLoginCallback(url: url)
        } else {
            print("⚠️ 不是预期的登录回调格式")
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
