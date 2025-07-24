//
//  ContentView.swift
//  InstaGo
//
//  Created by 陈瀚翔 on 23/7/2025.
//

import SwiftUI
import Vision
import UniformTypeIdentifiers
import Network
#if os(macOS)
import AppKit
#endif

// 菜单栏内容
struct MenuBarContent: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var serverManager: ServerManager
    @State private var tempLabel = ""
    @State private var hasInitialized = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("InstaGo")
                .font(.headline)
                .padding(.bottom, 4)
            
            // 文字标签输入区域
            VStack(alignment: .leading, spacing: 4) {
                Text("图片标签")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextField("最多16个字符", text: $tempLabel)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: tempLabel) { _, newValue in
                        appState.updateImageLabel(newValue)
                    }
                    .onAppear {
                        tempLabel = appState.imageLabel
                    }
                
                Text("\(appState.imageLabel.count)/16")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 4)
            
            Divider()
            
            // 服务器状态显示
            HStack {
                Image(systemName: serverManager.isServerRunning ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(serverManager.isServerRunning ? .green : .red)
                Text("服务器: \(serverManager.statusDescription)")
                    .font(.caption)
                Spacer()
            }
            .padding(.vertical, 2)
            
            Divider()
            
            Button(action: {
                toggleFloatingWindow()
            }) {
                HStack {
                    Image(systemName: appState.isFloatingWindowVisible ? "eye.slash" : "eye")
                    Text(appState.isFloatingWindowVisible ? "隐藏悬浮窗" : "显示悬浮窗")
                }
            }
            .buttonStyle(.plain)
            
            // 调试按钮
            Button(action: {
                createTestWindow()
            }) {
                HStack {
                    Image(systemName: "hammer.fill")
                    Text("创建测试窗口")
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.orange)
            
            Divider()
            
            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(width: 200)
        .onAppear {
            // 确保FloatingPanelManager被初始化
            if !hasInitialized {
                print("🔧 MenuBarContent手动初始化FloatingPanelManager")
                FloatingPanelManager.shared.initializeDirect(with: appState)
                hasInitialized = true
            }
        }
    }
    
    private func toggleFloatingWindow() {
        if appState.isFloatingWindowVisible {
            FloatingPanelManager.shared.hidePanel()
        } else {
            FloatingPanelManager.shared.showPanel()
        }
        appState.toggleFloatingWindow()
    }
    
    private func createTestWindow() {
        print("🔨 手动创建测试窗口")
        
        // 强制重新初始化FloatingPanelManager
        FloatingPanelManager.shared.initializeDirect(with: appState)
        
        // 也尝试直接创建一个简单的测试窗口
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.createSimpleTestWindow()
        }
    }
    
    private func createSimpleTestWindow() {
        print("🧪 创建简单测试窗口")
        
        let testWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        testWindow.level = .floating
        testWindow.backgroundColor = NSColor.green.withAlphaComponent(0.8)
        testWindow.isOpaque = false
        testWindow.hasShadow = true
        testWindow.canHide = false
        
        // 设置到屏幕左上角
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            testWindow.setFrameOrigin(CGPoint(x: screenFrame.minX + 50, y: screenFrame.maxY - 150))
        }
        
        let testView = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        testView.wantsLayer = true
        testView.layer?.backgroundColor = NSColor.yellow.cgColor
        
        let label = NSTextField(labelWithString: "SIMPLE\nTEST")
        label.frame = NSRect(x: 10, y: 30, width: 80, height: 40)
        label.textColor = .black
        label.alignment = .center
        label.font = NSFont.boldSystemFont(ofSize: 10)
        testView.addSubview(label)
        
        testWindow.contentView = testView
        
        testWindow.makeKeyAndOrderFront(nil)
        testWindow.orderFrontRegardless()
        
        print("🧪 简单测试窗口已创建")
        print("   - 位置: \(testWindow.frame)")
        print("   - 可见: \(testWindow.isVisible)")
        
        // 5秒后自动关闭
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            testWindow.close()
            print("🧪 简单测试窗口已关闭")
        }
    }
}

// 自定义窗口类，支持键盘输入
class FloatingWindow: NSWindow {
    override var canBecomeKey: Bool {
        return true  // 允许成为关键窗口以接受键盘输入
    }
    
    override var canBecomeMain: Bool {
        return false  // 不成为主窗口
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        setupWindow()
    }
    
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        setupWindow()
    }
    
    private func setupWindow() {
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.hidesOnDeactivate = false
        self.isExcludedFromWindowsMenu = true
        self.acceptsMouseMovedEvents = true
    }
}

// 悬浮窗管理器
class FloatingPanelManager: ObservableObject {
    static let shared = FloatingPanelManager()
    
    private var windowController: NSWindowController?
    private let compactSize = CGSize(width: 80, height: 80)
    private let expandedSize = CGSize(width: 308, height: 80)  // 增加8px容纳间距 (300 + 8)
    private var appState: AppState?
    
    private init() {
        print("🏗️ FloatingPanelManager 初始化")
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        print("📡 设置通知监听器")
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("InitializeFloatingPanel"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            print("📨 收到初始化通知")
            if let appState = notification.object as? AppState {
                self?.initialize(with: appState)
            } else {
                print("❌ 通知中的AppState为空")
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ExpandFloatingPanel"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("📨 收到展开通知")
            self?.expandPanel()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CollapseFloatingPanel"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("📨 收到收缩通知")
            self?.collapsePanel()
        }
    }
    
    func initialize(with appState: AppState) {
        print("🎯 开始初始化悬浮窗，AppState: \(appState)")
        self.appState = appState
        
        // 延迟创建，确保应用完全启动
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.createFloatingWindow()
            
            // 再次延迟显示，确保创建完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.forceShowPanel()
            }
        }
        
        print("🎈 悬浮窗初始化流程启动")
    }
    
    // 添加一个直接初始化的方法作为备用
    func initializeDirect(with appState: AppState) {
        print("🎯 直接初始化悬浮窗")
        self.appState = appState
        createFloatingWindow()
        forceShowPanel()
        print("🎈 悬浮窗直接初始化完成")
    }
    
    private func createFloatingWindow() {
        guard let appState = appState else { 
            print("❌ createFloatingWindow: AppState为空")
            return 
        }
        
        print("🏗️ 创建悬浮窗窗口")
        
        // 使用自定义窗口类
        let window = FloatingWindow(
            contentRect: NSRect(x: 100, y: 100, width: compactSize.width, height: compactSize.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        // 基本窗口设置
        window.level = .floating
        window.backgroundColor = NSColor.red.withAlphaComponent(0.8)  // 临时设置红色背景以便调试
        window.isOpaque = false
        window.hasShadow = true  // 临时开启阴影以便看到
        window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = true
        window.canHide = false
        window.alphaValue = 1.0
        
        print("🔧 基本窗口属性设置完成")
        
        // 设置集合行为
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]
        
        // 创建一个简单的测试内容
        let testView = NSView(frame: NSRect(x: 0, y: 0, width: compactSize.width, height: compactSize.height))
        testView.wantsLayer = true
        testView.layer?.backgroundColor = NSColor.blue.withAlphaComponent(0.8).cgColor
        testView.layer?.cornerRadius = 32
        
        // 添加文本标签用于测试
        let textField = NSTextField(labelWithString: "TEST")
        textField.frame = NSRect(x: 20, y: 30, width: 40, height: 20)
        textField.textColor = .white
        textField.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        testView.addSubview(textField)
        
        window.contentView = testView
        
        print("🎨 测试内容创建完成")
        
        // 创建窗口控制器
        windowController = NSWindowController(window: window)
        
        // 设置到屏幕中心进行测试
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let centerX = screenFrame.midX - compactSize.width / 2
            let centerY = screenFrame.midY - compactSize.height / 2
            window.setFrameOrigin(CGPoint(x: centerX, y: centerY))
            print("🎯 设置到屏幕中心: (\(centerX), \(centerY))")
        }
        
        // 立即显示窗口
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        
        print("✅ 测试窗口创建完成")
        print("   - 创建后可见状态: \(window.isVisible)")
        print("   - 创建后位置: \(window.frame)")
        print("   - 窗口背景色: \(window.backgroundColor?.description ?? "无")")
        print("   - 窗口透明度: \(window.alphaValue)")
        
        // 延迟检查窗口状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("🔍 延迟检查窗口状态:")
            print("   - 0.5秒后可见状态: \(window.isVisible)")
            print("   - 窗口在屏幕坐标: \(window.frame)")
            
            if window.isVisible {
                print("✅ 测试窗口显示成功！")
                
                // 如果测试窗口显示成功，替换为真正的SwiftUI内容
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    print("🔄 切换到真正的SwiftUI内容")
                    self.replaceWithRealContent(window: window, appState: appState)
                }
            } else {
                print("❌ 测试窗口显示失败")
                
                // 列出所有窗口进行调试
                print("🪟 当前所有应用窗口:")
                for (index, appWindow) in NSApplication.shared.windows.enumerated() {
                    print("   [\(index)] 级别=\(appWindow.level.rawValue), 可见=\(appWindow.isVisible), 框架=\(appWindow.frame)")
                }
            }
        }
    }
    
    // 替换为真正的SwiftUI内容
    private func replaceWithRealContent(window: NSWindow, appState: AppState) {
        let contentView = FloatingButtonView()
            .environmentObject(appState)
        let hostingView = NSHostingView(rootView: contentView)
        
        // 恢复正常的窗口设置
        window.backgroundColor = .clear
        window.hasShadow = false
        
        window.contentView = hostingView
        
        // 设置到正确位置
        setInitialPosition(window)
        
        print("🎨 已切换到真正的SwiftUI内容")
    }
    
    private func setInitialPosition(_ window: NSWindow) {
        guard let screen = NSScreen.main else {
            print("❌ 无法获取主屏幕信息")
            return
        }
        
        let screenFrame = screen.visibleFrame
        let windowSize = compactSize
        let safeMargin: CGFloat = 20  // 安全边距
        
        // 计算右上角位置
        // 注意：macOS坐标系统Y轴向上，visibleFrame.maxY是屏幕顶部
        let x = screenFrame.maxX - windowSize.width - safeMargin
        let y = screenFrame.maxY - windowSize.height - safeMargin
        
        // 边界检测，确保不会超出屏幕
        let finalX = max(screenFrame.minX + safeMargin, min(x, screenFrame.maxX - windowSize.width - safeMargin))
        let finalY = max(screenFrame.minY + safeMargin, min(y, screenFrame.maxY - windowSize.height - safeMargin))
        
        let finalPosition = CGPoint(x: finalX, y: finalY)
        
        // 详细调试信息
        print("🖥️ 屏幕信息:")
        print("   - 完整屏幕: \(screen.frame)")
        print("   - 可见区域: \(screenFrame)")
        print("   - 屏幕尺寸: \(screenFrame.width) × \(screenFrame.height)")
        print("🎯 悬浮窗定位:")
        print("   - 窗口尺寸: \(windowSize)")
        print("   - 计算位置: (\(x), \(y))")
        print("   - 最终位置: \(finalPosition)")
        print("   - 是否在屏幕内: \(screenFrame.contains(CGRect(origin: finalPosition, size: windowSize)))")
        
        window.setFrameOrigin(finalPosition)
        
        // 验证最终位置
        let actualFrame = window.frame
        print("✅ 窗口实际位置: \(actualFrame)")
        
        // 检查是否可见
        if screenFrame.intersects(actualFrame) {
            print("✅ 悬浮窗在可见区域内")
        } else {
            print("❌ 悬浮窗可能在屏幕外！")
            // 强制设置到屏幕右上角
            let fallbackX = screenFrame.maxX - windowSize.width - 10
            let fallbackY = screenFrame.maxY - windowSize.height - 10
            window.setFrameOrigin(CGPoint(x: fallbackX, y: fallbackY))
            print("🔧 已强制设置到备用位置: (\(fallbackX), \(fallbackY))")
        }
    }
    
    func expandPanel() {
        guard let window = windowController?.window else { return }
        
        // 计算展开后的位置
        let currentFrame = window.frame
        let newWidth = expandedSize.width
        let widthDifference = newWidth - currentFrame.width
        
        // 根据屏幕空间决定向左还是向右展开
        var newX = currentFrame.origin.x
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            // 如果右侧空间不够，向左展开
            if currentFrame.maxX + widthDifference > screenFrame.maxX {
                newX = currentFrame.origin.x - widthDifference
            }
        }
        
        let newFrame = CGRect(
            x: newX,
            y: currentFrame.origin.y,
            width: newWidth,
            height: expandedSize.height
        )
        
        // 动画展开
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        } completionHandler: {
            // 展开完成后，让窗口成为关键窗口以接受键盘输入
            DispatchQueue.main.async {
                window.makeKey()
                print("🔑 展开完成，窗口已成为关键窗口")
            }
        }
        
        print("🔄 悬浮窗展开")
    }
    
    func collapsePanel() {
        guard let window = windowController?.window else { return }
        
        // 计算收缩后的位置（保持右边缘位置）
        let currentFrame = window.frame
        let newWidth = compactSize.width
        let widthDifference = currentFrame.width - newWidth
        
        let newFrame = CGRect(
            x: currentFrame.origin.x + widthDifference,
            y: currentFrame.origin.y,
            width: newWidth,
            height: compactSize.height
        )
        
        // 动画收缩
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }
        
        print("🔄 悬浮窗收缩")
    }
    
    func showPanel() {
        print("👀 尝试显示悬浮窗")
        
        // 如果窗口不存在但AppState存在，尝试创建窗口
        if windowController?.window == nil {
            if appState != nil {
                print("🔧 窗口不存在，尝试创建")
                createFloatingWindow()
            } else {
                print("❌ 窗口未创建且AppState未设置")
                return
            }
        }
        
        guard let window = windowController?.window else {
            print("❌ 无法获取窗口实例")
            return
        }
        
        // 显示窗口前的状态检查
        print("🔍 显示前窗口状态:")
        print("   - 窗口级别: \(window.level.rawValue)")
        print("   - 窗口框架: \(window.frame)")
        print("   - 是否可见: \(window.isVisible)")
        print("   - 是否关键窗口: \(window.isKeyWindow)")
        
        // 确保窗口在正确位置
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = window.frame
            if !screenFrame.intersects(windowFrame) {
                print("⚠️ 窗口不在可见区域，重新定位")
                setInitialPosition(window)
            }
        }
        
        window.orderFront(nil)
        
        // 显示后的状态检查
        print("📊 显示后窗口状态:")
        print("   - 是否可见: \(window.isVisible)")
        print("   - 窗口框架: \(window.frame)")
        
        // 如果窗口仍然不可见，尝试强制显示
        if !window.isVisible {
            print("🔄 窗口不可见，尝试强制显示")
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            
            // 再次检查
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                print("🔍 强制显示后状态: 可见=\(window.isVisible), 框架=\(window.frame)")
                
                if !window.isVisible {
                    print("❌ 强制显示失败，可能存在其他问题")
                    // 列出所有窗口用于调试
                    print("🪟 当前所有应用窗口:")
                    for (index, appWindow) in NSApplication.shared.windows.enumerated() {
                        print("   [\(index)] 级别=\(appWindow.level.rawValue), 可见=\(appWindow.isVisible), 框架=\(appWindow.frame)")
                    }
                }
            }
        }
        
        print("👁️ showPanel完成 - 最终可见状态: \(window.isVisible)")
    }
    
    func hidePanel() {
        windowController?.window?.orderOut(nil)
        print("🙈 悬浮窗隐藏")
    }
    
    // 强制显示方法
    private func forceShowPanel() {
        guard let window = windowController?.window else {
            print("❌ forceShowPanel: 无法获取窗口")
            return
        }
        
        print("💪 强制显示悬浮窗开始")
        
        // 多种显示方法
        window.orderOut(nil)  // 先隐藏
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.orderFront(nil)
        
        // 设置窗口属性
        window.level = .floating
        window.alphaValue = 1.0
        window.isOpaque = false
        
        print("💪 强制显示命令已执行")
        print("   - 窗口可见: \(window.isVisible)")
        print("   - 窗口级别: \(window.level.rawValue)")
        print("   - 窗口透明度: \(window.alphaValue)")
        print("   - 窗口位置: \(window.frame)")
        
        // 验证窗口是否在应用窗口列表中
        let allWindows = NSApplication.shared.windows
        let isInWindowList = allWindows.contains(window)
        print("   - 窗口在应用列表中: \(isInWindowList)")
        
        if !window.isVisible {
            print("⚠️ 窗口仍然不可见，尝试其他方法")
            
            // 尝试重新设置位置到屏幕中心进行测试
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let centerX = screenFrame.midX - window.frame.width / 2
                let centerY = screenFrame.midY - window.frame.height / 2
                window.setFrameOrigin(CGPoint(x: centerX, y: centerY))
                print("   - 已设置到屏幕中心: (\(centerX), \(centerY))")
                
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// 悬浮按钮视图
struct FloatingButtonView: View {
    @EnvironmentObject var appState: AppState
    @State private var isHovered = false
    @State private var isDragOver = false
    @State private var isUploading = false
    @State private var uploadStatus: String = ""
    @State private var showUploadIndicator = false
    @State private var pulseAnimation = false
    @State private var localLabel = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 8) {  // 添加8px间距
                // 左侧圆形按钮
                circleButton
                
                // 右侧标签输入区域（仅在展开时显示）
                if appState.isFloatingWindowExpanded {
                    expandedInputArea
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)  // 确保内容居中对齐
        }
        .onAppear {
            localLabel = appState.imageLabel
        }
        .onChange(of: appState.imageLabel) { _, newValue in
            localLabel = newValue
        }
    }
    
    private var circleButton: some View {
        ZStack {
            // 外圈脉冲效果
            if isDragOver {
                Circle()
                    .stroke(Color.blue.opacity(0.4), lineWidth: 3)
                    .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                    .opacity(pulseAnimation ? 0.0 : 1.0)
                    .animation(
                        .easeInOut(duration: 1.0).repeatForever(autoreverses: false),
                        value: pulseAnimation
                    )
            }
            
            // 主按钮背景（白色圆形）
            Circle()
                .fill(Color.white)
                .overlay(
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .scaleEffect(isDragOver ? 1.1 : 1.0)
            
            // 图标和状态
            VStack(spacing: 0) {
                if isUploading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        .scaleEffect(0.8)
                } else if showUploadIndicator {
                    ZStack {
                        Circle()
                            .fill(uploadStatus.contains("成功") ? Color.green : Color.red)
                            .frame(width: 20, height: 20)
                        
                        Image(systemName: uploadStatus.contains("成功") ? "checkmark" : "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                } else {
                    Image("instago-icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .foregroundColor(.gray)
                        .scaleEffect(isDragOver ? 1.1 : 1.0)
                        .opacity(isDragOver ? 0.7 : 1.0)
                }
            }
        }
        .frame(width: 64, height: 64)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            toggleExpansion()
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
            return true
        }
        .onChange(of: isDragOver) { _, isDragging in
            if isDragging {
                pulseAnimation = true
            } else {
                pulseAnimation = false
            }
        }
        .help("点击展开输入框，拖拽图片上传")
    }
    
    private var expandedInputArea: some View {
        HStack(spacing: 12) {
            // 蓝色标签图标
            Image(systemName: "tag.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.blue)
                .frame(width: 16, height: 16)  // 固定图标尺寸
            
            // 文字输入框
            TextField("Situation Tag", text: $localLabel)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .focused($isTextFieldFocused)
                .onChange(of: localLabel) { _, newValue in
                    appState.updateImageLabel(newValue)
                }
                .onSubmit {
                    collapseWithDelay()
                }
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .frame(width: 220, height: 64)  // 确保高度与圆形按钮一致
        .background(
            RoundedRectangle(cornerRadius: 32)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
        .onAppear {
            // 延迟聚焦到文本框，确保窗口完全展开后再聚焦
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                isTextFieldFocused = true
                print("🎯 尝试聚焦到输入框")
            }
        }
    }
    
    private func toggleExpansion() {
        withAnimation(.easeInOut(duration: 0.3)) {
            if appState.isFloatingWindowExpanded {
                appState.collapseFloatingWindow()
            } else {
                appState.expandFloatingWindow()
            }
        }
    }
    
    private func collapseWithDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.3)) {
                appState.collapseFloatingWindow()
            }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, _) in
            if let data = item as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil),
               let _ = NSImage(contentsOf: url) {
                DispatchQueue.main.async {
                    uploadImageToServer(imageURL: url)
                }
            }
        }
    }
    
    private func uploadImageToServer(imageURL: URL) {
        guard let imageData = NSImage(contentsOf: imageURL)?.tiffRepresentation,
              let bitmapImageRep = NSBitmapImageRep(data: imageData),
              let jpegData = bitmapImageRep.representation(using: .jpeg, properties: [:]) else {
            print("❌ 图片处理失败")
            showUploadResult("处理失败")
            return
        }
        
        // 转换为base64编码
        let base64Image = jpegData.base64EncodedString()
        print("📸 图片已转换为base64，大小: \(base64Image.count) 字符")
        
        isUploading = true
        showUploadIndicator = false
        
        let serverURL = "http://localhost:8080/upload"
        guard let url = URL(string: serverURL) else {
            print("❌ 服务器地址无效: \(serverURL)")
            showUploadResult("服务器地址无效")
            return
        }
        
        print("🚀 开始上传图片到: \(serverURL)")
        print("🏷️ 图片标签: \"\(appState.imageLabel)\"")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 创建JSON请求体，匹配Go服务器期望的格式
        let requestBody: [String: Any] = [
            "image": base64Image,
            "folder_id": 0  // 默认使用根文件夹
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            request.httpBody = jsonData
            print("📦 请求体已创建，大小: \(jsonData.count) 字节")
        } catch {
            print("❌ JSON序列化失败: \(error.localizedDescription)")
            showUploadResult("数据格式错误")
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isUploading = false
                
                // 详细的响应日志
                print("📡 收到服务器响应")
                
                if let error = error {
                    print("❌ 网络错误: \(error.localizedDescription)")
                    showUploadResult("网络错误")
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("🌐 HTTP状态码: \(httpResponse.statusCode)")
                    print("📋 响应头: \(httpResponse.allHeaderFields)")
                    
                    if let data = data {
                        print("📄 响应数据大小: \(data.count) 字节")
                        
                        // 尝试解析并输出响应内容
                        if let responseString = String(data: data, encoding: .utf8) {
                            print("📝 服务器响应内容:")
                            print(responseString)
                        }
                        
                        // 尝试解析JSON响应
                        if let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            print("📊 解析后的JSON响应:")
                            for (key, value) in jsonResponse {
                                print("   \(key): \(value)")
                            }
                        }
                    } else {
                        print("⚠️ 响应数据为空")
                    }
                    
                    if httpResponse.statusCode == 200 {
                        showUploadResult("上传成功")
                        print("✅ 图片上传成功，标签: \"\(appState.imageLabel)\"")
                    } else {
                        showUploadResult("服务器错误(\(httpResponse.statusCode))")
                        print("❌ 服务器返回错误状态码: \(httpResponse.statusCode)")
                    }
                } else {
                    print("❌ 无效的HTTP响应")
                    showUploadResult("响应错误")
                }
            }
        }.resume()
    }
    
    private func showUploadResult(_ status: String) {
        uploadStatus = status
        withAnimation(.easeInOut(duration: 0.3)) {
            showUploadIndicator = true
        }
        
        // 2秒后恢复正常状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showUploadIndicator = false
                uploadStatus = ""
            }
        }
    }
}

// 原来的ContentView保持不变，作为备用
struct ContentView: View {
    @State private var image: NSImage?
    @State private var recognizedText: String = ""

    var body: some View {
        VStack {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
            } else {
                Text("拖拽图片到此处进行 OCR")
                    .frame(maxWidth: .infinity, maxHeight: 200)
                    .border(Color.gray)
            }
            ScrollView {
                Text(recognizedText)
                    .padding()
            }
            .frame(maxHeight: .infinity)
        }
        .padding()
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, _) in
            if let data = item as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil),
               let nsImage = NSImage(contentsOf: url) {
                DispatchQueue.main.async {
                    image = nsImage
                    performOCR(on: url)
                }
            }
        }
    }

    private func performOCR(on url: URL) {
        let request = VNRecognizeTextRequest { (request, _) in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            DispatchQueue.main.async {
                recognizedText = text
            }
        }
        request.recognitionLevel = .accurate
        let handler = VNImageRequestHandler(url: url, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("OCR error: \(error)")
        }
    }
}

#Preview {
    ContentView()
}

