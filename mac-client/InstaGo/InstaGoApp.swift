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
    
    init() {
        // 延迟发送初始化通知
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(name: NSNotification.Name("InitializeFloatingPanel"), object: self)
            print("🚀 发送FloatingPanel初始化通知")
        }
    }
    
    func toggleFloatingWindow() {
        isFloatingWindowVisible.toggle()
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
}

// 应用委托
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🎯 应用启动完成")
        
        // 设置应用不在Dock中显示
        NSApp.setActivationPolicy(.accessory)
        
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
}
