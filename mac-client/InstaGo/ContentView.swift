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
import CoreGraphics
import Quartz
import Carbon
import ScreenCaptureKit
#if os(macOS)
import AppKit
#endif

// 自定义的 NSHostingView，支持立即响应鼠标点击
class AcceptFirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true  // 允许第一次鼠标点击立即响应，不需要先获得焦点
    }
}

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
            
            // 用户登录状态（仅在线模式显示）
            if appState.isOnlineMode {
                HStack {
                    Image(systemName: appState.isLoggedIn ? "person.fill.checkmark" : "person.fill.xmark")
                        .foregroundColor(appState.isLoggedIn ? .green : .red)
                    
                    if appState.isLoggedIn, let user = appState.userInfo {
                        Text("已登录: \(user.name)")
                            .font(.caption)
                    } else {
                        Text("未登录")
                            .font(.caption)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        if appState.isLoggedIn {
                            appState.logout()
                        } else {
                            appState.startLoginFlow()
                        }
                    }) {
                        Text(appState.isLoggedIn ? "登出" : "登录")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(appState.isLoggedIn ? Color.red.opacity(0.2) : Color.green.opacity(0.2))
                            .foregroundColor(appState.isLoggedIn ? .red : .green)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
            
            // 模式切换
            HStack {
                Image(systemName: appState.isOnlineMode ? "cloud.fill" : "server.rack")
                    .foregroundColor(appState.isOnlineMode ? .blue : .orange)
                Text("模式: \(appState.modeDescription)")
                    .font(.caption)
                Spacer()
                Button(action: {
                    appState.toggleMode()
                }) {
                    Text(appState.isOnlineMode ? "切换本地" : "切换在线")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(appState.isOnlineMode ? Color.orange.opacity(0.2) : Color.blue.opacity(0.2))
                        .foregroundColor(appState.isOnlineMode ? .orange : .blue)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)
            
            // 服务器状态显示（仅在本地模式时显示）
            if !appState.isOnlineMode {
                HStack {
                    Image(systemName: serverManager.isServerRunning ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(serverManager.isServerRunning ? .green : .red)
                    Text("服务器: \(serverManager.statusDescription)")
                        .font(.caption)
                    Spacer()
                }
                .padding(.vertical, 2)
            }
            
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
            
            // 截图功能按钮
            Button(action: {
                ScreenshotManager.shared.startScreenshot()
            }) {
                HStack {
                    Image(systemName: "camera.viewfinder")
                    Text("截图上传")
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.purple)
            .help("或按 Cmd+Shift+X")
            
            // 调试按钮 - 发布版本中隐藏
            /*
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
            
            // URL Scheme 测试按钮 - 发布版本中隐藏
            Button(action: {
                testURLScheme()
            }) {
                HStack {
                    Image(systemName: "link.circle")
                    Text("测试URL回调")
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.blue)
            */
            
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
                
                // 初始化截图管理器
                print("🔧 MenuBarContent初始化ScreenshotManager")
                ScreenshotManager.shared.initialize(with: appState)
                
                hasInitialized = true
            } else {
                // 即使已经初始化，也检查悬浮窗是否应该显示但实际没显示
                if appState.isFloatingWindowVisible {
                    print("🔍 检查悬浮窗显示状态")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        FloatingPanelManager.shared.showPanel()
                    }
                }
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
    
    // 发布版本中隐藏的调试方法
    /*
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
    
    private func testURLScheme() {
        print("🧪 测试URL Scheme回调")
        
        // 创建一个测试用的登录回调URL
        let testURL = "instago://auth?token=test_token_12345&user_id=test_123&user_name=测试用户&user_email=test@example.com"
        
        print("🔗 测试URL: \(testURL)")
        
        if let url = URL(string: testURL) {
            // 直接调用AppState的处理方法
            appState.handleLoginCallback(url: url)
        } else {
            print("❌ 无法创建测试URL")
        }
    }
    */
}

// 自定义窗口类，支持键盘输入
class FloatingWindow: NSWindow {
    override var canBecomeKey: Bool {
        return true  // 允许成为关键窗口以接受键盘输入
    }
    
    override var canBecomeMain: Bool {
        return false  // 不成为主窗口
    }
    
    override var acceptsFirstResponder: Bool {
        return true  // 接受第一响应者状态
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
        
        // 设置窗口行为，允许接受键盘事件
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]
        
        print("🪟 FloatingWindow 配置完成，可接受键盘输入: \(self.canBecomeKey)")
    }
    
    // 重写键盘事件处理以确保能够接受Cmd+V
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            print("🎹 FloatingWindow接收到键盘事件: \(event.charactersIgnoringModifiers ?? ""), 修饰键: \(event.modifierFlags)")
        }
        super.sendEvent(event)
    }
}

// 截图选择窗口
class ScreenshotSelectionWindow: NSWindow {
    private var startPoint: CGPoint = .zero
    private var currentPoint: CGPoint = .zero
    private var isDragging = false
    private var onScreenshotTaken: ((CGRect) -> Void)?
    
    init(onScreenshotTaken: @escaping (CGRect) -> Void) {
        self.onScreenshotTaken = onScreenshotTaken
        
        // 获取所有屏幕的联合区域
        let combinedFrame = NSScreen.screens.reduce(CGRect.zero) { result, screen in
            return result.union(screen.frame)
        }
        
        super.init(
            contentRect: combinedFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        setupWindow()
    }
    
    private func setupWindow() {
        self.level = .screenSaver  // 最高级别，覆盖所有其他窗口
        self.backgroundColor = NSColor.black.withAlphaComponent(0.3)  // 半透明遮罩
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        
        // 设置内容视图
        let contentView = ScreenshotSelectionView()
        contentView.screenshotWindow = self
        self.contentView = contentView
        
        // 添加键盘监听（ESC取消）
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { // ESC key
                self?.cancelScreenshot()
                return nil
            }
            return event
        }
        
        print("📸 截图选择窗口已创建，覆盖区域: \(self.frame)")
    }
    
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
    
    private func cancelScreenshot() {
        print("❌ 用户取消截图")
        self.close()
    }
    
    func takeScreenshot(in rect: CGRect) {
        print("📸 执行截图，区域: \(rect)")
        onScreenshotTaken?(rect)
        self.close()
    }
}

// 截图选择视图
class ScreenshotSelectionView: NSView {
    weak var screenshotWindow: ScreenshotSelectionWindow?
    private var startPoint: CGPoint = .zero
    private var endPoint: CGPoint = .zero
    private var isDragging = false
    private var selectionRect: CGRect = .zero
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        self.wantsLayer = true
        
        // 添加指导文字
        let instructionLabel = NSTextField(labelWithString: "拖动鼠标选择截图区域，按 ESC 取消")
        instructionLabel.textColor = .white
        instructionLabel.font = NSFont.systemFont(ofSize: 18, weight: .medium)
        instructionLabel.backgroundColor = NSColor.black.withAlphaComponent(0.7)
        instructionLabel.drawsBackground = true
        instructionLabel.alignment = .center
        instructionLabel.layer?.cornerRadius = 8
        
        // 居中显示
        let labelSize = instructionLabel.intrinsicContentSize
        let screenCenter = self.bounds.center
        instructionLabel.frame = CGRect(
            x: screenCenter.x - labelSize.width / 2,
            y: screenCenter.y + 50,
            width: labelSize.width + 20,
            height: labelSize.height + 10
        )
        
        self.addSubview(instructionLabel)
        
        // 2秒后隐藏提示
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            instructionLabel.removeFromSuperview()
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        endPoint = startPoint
        isDragging = true
        needsDisplay = true
        print("🖱️ 开始选择截图区域: \(startPoint)")
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        endPoint = convert(event.locationInWindow, from: nil)
        selectionRect = CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )
        needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        
        if selectionRect.width > 10 && selectionRect.height > 10 {
            // 转换为屏幕坐标
            let windowRect = screenshotWindow?.convertToScreen(selectionRect) ?? selectionRect
            let flippedRect = CGRect(
                x: windowRect.origin.x,
                y: NSScreen.main?.frame.height ?? 0 - windowRect.origin.y - windowRect.height,
                width: windowRect.width,
                height: windowRect.height
            )
            
            print("📸 截图区域选择完成: \(flippedRect)")
            screenshotWindow?.takeScreenshot(in: flippedRect)
        } else {
            print("⚠️ 选择区域太小，取消截图")
            screenshotWindow?.close()
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // 绘制选择区域
        if isDragging && selectionRect.width > 0 && selectionRect.height > 0 {
            // 绘制选择框
            NSColor.blue.withAlphaComponent(0.3).setFill()
            selectionRect.fill()
            
            // 绘制边框
            NSColor.blue.setStroke()
            let borderPath = NSBezierPath(rect: selectionRect)
            borderPath.lineWidth = 2
            borderPath.stroke()
            
            // 绘制尺寸信息
            let sizeText = "\(Int(selectionRect.width)) × \(Int(selectionRect.height))"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white,
                .backgroundColor: NSColor.black.withAlphaComponent(0.7)
            ]
            
            let attributedString = NSAttributedString(string: sizeText, attributes: attributes)
            let textRect = CGRect(
                x: selectionRect.maxX - 80,
                y: selectionRect.minY - 20,
                width: 80,
                height: 20
            )
            attributedString.draw(in: textRect)
        }
    }
}

// 截图管理器
class ScreenshotManager: ObservableObject {
    static let shared = ScreenshotManager()
    private var screenshotWindow: ScreenshotSelectionWindow?
    private var globalHotKeyRef: EventHotKeyRef?
    private weak var appState: AppState?
    
    private init() {
        print("📸 截图管理器初始化")
    }
    
    func initialize(with appState: AppState) {
        self.appState = appState
        setupGlobalHotKey()
        print("📸 截图管理器已初始化")
    }
    
    private func setupGlobalHotKey() {
        // 移除之前的热键
        if let hotKeyRef = globalHotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        
        // 注册 Cmd+Shift+X 热键
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = fourCharCodeFrom("SSHT")  // Screenshot的缩写
        hotKeyID.id = UInt32(1)
        
        // Cmd+Shift+X 的组合键
        let modifiers = UInt32(cmdKey | shiftKey)
        let keyCode = UInt32(7)  // X 键的键码
        
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        
        // 安装事件处理器
        InstallEventHandler(GetApplicationEventTarget(), { (nextHandler, theEvent, userData) -> OSStatus in
            // 检查是否是我们的热键
            var hotKeyID = EventHotKeyID()
            GetEventParameter(theEvent, OSType(kEventParamDirectObject), OSType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            
            if hotKeyID.signature == fourCharCodeFrom("SSHT") && hotKeyID.id == 1 {
                DispatchQueue.main.async {
                    ScreenshotManager.shared.startScreenshot()
                }
                return noErr
            }
            
            return CallNextEventHandler(nextHandler, theEvent)
        }, 1, &eventSpec, nil, nil)
        
        // 注册热键
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &globalHotKeyRef)
        
        if status == noErr {
            print("✅ 全局热键 Cmd+Shift+X 注册成功")
        } else {
            print("❌ 热键注册失败，状态码: \(status)")
        }
    }
    
    func startScreenshot() {
        print("📸 启动截图模式")
        
        guard appState != nil else {
            print("❌ AppState 未初始化")
            return
        }
        
        // 检查屏幕录制权限
        if !checkScreenRecordingPermission() {
            print("❌ 没有屏幕录制权限")
            showPermissionAlert()
            return
        }
        
        // 创建截图选择窗口
        screenshotWindow = ScreenshotSelectionWindow { [weak self] rect in
            self?.captureScreenshot(in: rect)
        }
        
        // 显示窗口
        screenshotWindow?.makeKeyAndOrderFront(nil)
        screenshotWindow?.orderFrontRegardless()
        
        print("📸 截图选择窗口已显示")
    }
    
    private func checkScreenRecordingPermission() -> Bool {
        if #available(macOS 12.3, *) {
            // 使用 ScreenCaptureKit 检查权限
            // 权限检查会在第一次尝试捕获时进行
            return true
        } else {
            // macOS 12.3 以下版本不支持 ScreenCaptureKit
            return false
        }
    }
    
    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "需要屏幕录制权限"
        alert.informativeText = "InstaGo 需要屏幕录制权限来执行截图功能。请在系统设置中授予权限。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // 打开系统设置
            if #available(macOS 13.0, *) {
                // macOS 13+ 使用新的设置URL
                if let url = URL(string: "x-apple.systempreferences:com.apple.ScreenTime-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            } else {
                // macOS 12.x 使用旧的偏好设置URL
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
    
    private func captureScreenshot(in rect: CGRect) {
        print("📸 开始截图，区域: \(rect)")
        
        if #available(macOS 12.3, *) {
            // 使用 ScreenCaptureKit 进行截图
            captureWithScreenCaptureKit(in: rect)
        } else {
            print("❌ 系统版本过低，需要 macOS 12.3+")
            showToastMessage("需要 macOS 12.3 或更高版本")
        }
    }
    
    @available(macOS 12.3, *)
    private func captureWithScreenCaptureKit(in rect: CGRect) {
        Task {
            do {
                // 获取可用的屏幕内容
                let availableContent = try await SCShareableContent.current
                
                // 找到包含截图区域的显示器
                guard let display = findDisplayForRect(rect, in: availableContent.displays) else {
                    await MainActor.run {
                        print("❌ 找不到对应的显示器")
                        showToastMessage("找不到对应的显示器")
                    }
                    return
                }
                
                // 配置截图参数
                let config = SCStreamConfiguration()
                config.width = Int(rect.width)
                config.height = Int(rect.height)
                config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = false
                
                // 设置截图区域 (相对于显示器坐标)
                let displayBounds = display.frame
                let relativeRect = CGRect(
                    x: rect.origin.x - displayBounds.origin.x,
                    y: rect.origin.y - displayBounds.origin.y,
                    width: rect.width,
                    height: rect.height
                )
                config.sourceRect = relativeRect
                
                print("📸 显示器边界: \(displayBounds)")
                print("📸 相对截图区域: \(relativeRect)")
                
                // 创建截图过滤器
                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                
                // 执行截图
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: config
                )
                
                await MainActor.run {
                    self.processScreenshotImage(image)
                }
                
            } catch {
                await MainActor.run {
                    print("❌ ScreenCaptureKit 截图失败: \(error.localizedDescription)")
                    if let scError = error as? SCStreamError {
                        self.handleScreenCaptureError(scError)
                    } else {
                        self.showToastMessage("截图失败: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    @available(macOS 12.3, *)
    private func findDisplayForRect(_ rect: CGRect, in displays: [SCDisplay]) -> SCDisplay? {
        // 找到与指定矩形区域重叠最多的显示器
        var bestDisplay: SCDisplay?
        var maxIntersectionArea: CGFloat = 0
        
        for display in displays {
            let displayFrame = display.frame
            let intersection = rect.intersection(displayFrame)
            let intersectionArea = intersection.width * intersection.height
            
            if intersectionArea > maxIntersectionArea {
                maxIntersectionArea = intersectionArea
                bestDisplay = display
            }
        }
        
        return bestDisplay
    }
    
    @available(macOS 12.3, *)
    private func handleScreenCaptureError(_ error: SCStreamError) {
        switch error.code {
        case .userDeclined:
            showToastMessage("用户拒绝了屏幕录制权限")
            showPermissionAlert()
        case .userStopped:
            showToastMessage("用户停止了屏幕录制")
        case .failedToStart:
            showToastMessage("无法启动屏幕捕获")
        case .missingEntitlements:
            showToastMessage("应用缺少必要的权限")
        default:
            showToastMessage("截图失败: \(error.localizedDescription)")
        }
    }
    
    private func processScreenshotImage(_ cgImage: CGImage) {
        print("✅ ScreenCaptureKit 截图成功")
        
        // 转换为NSImage
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        
        // 转换为JPEG数据
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapRep.representation(using: NSBitmapImageRep.FileType.jpeg, properties: [:]) else {
            print("❌ 图片转换失败")
            showToastMessage("图片处理失败")
            return
        }
        
        print("✅ 截图处理完成，大小: \(jpegData.count) 字节")
        
        // 上传截图
        uploadScreenshot(jpegData)
    }
    

    
    private func uploadScreenshot(_ imageData: Data) {
        guard let appState = appState else {
            print("❌ AppState 未初始化")
            return
        }
        
        print("📤 开始上传截图")
        
        // 检查在线模式是否需要登录
        if appState.requiresLogin {
            showToastMessage("请先登录")
            return
        }
        
        // 使用现有的智能上传方法
        ServerManager.shared.smartUploadImage(
            imageData: imageData,
            label: appState.imageLabel.isEmpty ? "截图" : appState.imageLabel,  // 如果没有标签就用"截图"
            isOnlineMode: appState.isOnlineMode,
            authToken: appState.authToken
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    print("✅ 截图上传成功: \(response)")
                    self.showToastMessage(appState.isOnlineMode ? "截图在线上传成功" : "截图本地上传成功")
                    
                case .failure(let error):
                    print("❌ 截图上传失败: \(error.localizedDescription)")
                    let errorMessage = appState.isOnlineMode ? "截图在线上传失败" : "截图本地上传失败"
                    self.showToastMessage("\(errorMessage): \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func showToastMessage(_ message: String) {
        // 发送通知给悬浮窗显示Toast
        NotificationCenter.default.post(
            name: NSNotification.Name("ShowToastMessage"),
            object: message
        )
    }
    
    deinit {
        if let hotKeyRef = globalHotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
    }
}

// 扩展CGRect以支持center属性
extension CGRect {
    var center: CGPoint {
        return CGPoint(x: midX, y: midY)
    }
}

// 扩展用于四字符代码转换
func fourCharCodeFrom(_ string: String) -> FourCharCode {
    assert(string.count == 4, "String length must be 4")
    var result: FourCharCode = 0
    for char in string.utf8 {
        result = result << 8 + FourCharCode(char)
    }
    return result
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
        print("🔍 悬浮窗可见状态: \(appState.isFloatingWindowVisible)")
        
        // 检查是否已经初始化
        if self.appState != nil {
            print("⚠️ 悬浮窗已经初始化，跳过重复初始化")
            return
        }
        
        self.appState = appState
        
        // 延迟创建，确保应用完全启动（减少延迟以加快显示）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.createFloatingWindow()
            
            // 再次延迟显示，确保创建完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                // 根据 AppState 的状态决定是否显示悬浮窗
                if appState.isFloatingWindowVisible {
                    print("✅ AppState 显示悬浮窗，开始显示")
                    self.forceShowPanel()
                } else {
                    print("⏸️ AppState 隐藏悬浮窗，跳过显示")
                }
            }
        }
        
        print("🎈 悬浮窗初始化流程启动")
    }
    
    // 添加一个直接初始化的方法作为备用
    func initializeDirect(with appState: AppState) {
        print("🎯 直接初始化悬浮窗")
        
        // 检查是否已经初始化
        if self.appState != nil && windowController?.window != nil {
            print("⚠️ 悬浮窗已经初始化，跳过重复初始化")
            return
        }
        
        self.appState = appState
        createFloatingWindow()
        forceShowPanel()
        print("🎈 悬浮窗直接初始化完成")
    }
    
    private func createFloatingWindow() {
        // 检查是否已经存在窗口，避免重复创建
        if windowController?.window != nil {
            print("⚠️ 悬浮窗已存在，跳过创建")
            return
        }
        
        guard let appState = appState else { 
            print("❌ createFloatingWindow: AppState为空")
            return 
        }
        
        print("🏗️ 直接创建悬浮窗窗口")
        
        // 使用自定义窗口类
        let window = FloatingWindow(
            contentRect: NSRect(x: 100, y: 100, width: compactSize.width, height: compactSize.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        // 基本窗口设置
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
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
        
        // 直接创建真正的SwiftUI内容
        let contentView = FloatingButtonView()
            .environmentObject(appState)
        let hostingView = AcceptFirstMouseHostingView(rootView: contentView)
        
        window.contentView = hostingView
        
        print("🎨 SwiftUI内容创建完成")
        
        // 创建窗口控制器
        windowController = NSWindowController(window: window)
        
        // 设置到右上角位置
        setInitialPosition(window)
        
        // 立即显示窗口
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        
        print("✅ 悬浮窗创建完成")
        print("   - 创建后可见状态: \(window.isVisible)")
        print("   - 创建后位置: \(window.frame)")
        print("   - 窗口透明度: \(window.alphaValue)")
        
        // 验证窗口是否在应用窗口列表中
        let allWindows = NSApplication.shared.windows
        let isInWindowList = allWindows.contains(window)
        print("   - 窗口在应用列表中: \(isInWindowList)")
        
        // 简短延迟检查最终状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            print("🔍 最终检查窗口状态:")
            print("   - 可见状态: \(window.isVisible)")
            print("   - 窗口位置: \(window.frame)")
            
            if window.isVisible {
                print("✅ 悬浮窗显示成功！")
            } else {
                print("❌ 悬浮窗显示失败")
            }
        }
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
    @State private var rippleAnimation = false
    @State private var localLabel = ""
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var singleTapWorkItem: DispatchWorkItem?
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
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
                
                // Toast 提示
                if showToast {
                    toastView
                }
            }
        }
        .onAppear {
            localLabel = appState.imageLabel
            setupKeyboardMonitoring()
            setupNotificationListeners()
        }
        .onChange(of: appState.imageLabel) { _, newValue in
            localLabel = newValue
        }
        .onChange(of: appState.isFloatingWindowSelected) { _, isSelected in
            if isSelected {
                // 当悬浮窗被选中时，激活键盘监听
                activateKeyboardListening()
            } else {
                // 取消选中时，停止键盘监听
                deactivateKeyboardListening()
            }
        }
        .onDisappear {
            // 清理延迟任务
            singleTapWorkItem?.cancel()
            singleTapWorkItem = nil
        }
    }
    
    // Toast 视图
    private var toastView: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Text(toastMessage)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                Spacer()
            }
            .padding(.bottom, 10)
        }
    }
    
    // 设置键盘监听
    private func setupKeyboardMonitoring() {
        print("⌨️ 设置键盘监听")
        
        // 添加全局键盘监听器
        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { event in
            if appState.isFloatingWindowSelected {
                _ = handleKeyEvent(event)
            }
        }
        
        // 添加本地键盘监听器（用于捕获应用内的键盘事件）
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if appState.isFloatingWindowSelected {
                if handleKeyEvent(event) {
                    return nil // 消费事件
                }
            }
            return event // 继续传递事件
        }
        
        print("⌨️ 全局和本地键盘监听已设置")
    }
    
    // 处理键盘事件
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // 检查是否是 Cmd+V (粘贴)
        if event.modifierFlags.contains(.command) && event.keyCode == 9 { // keyCode 9 是 'V' 键
            print("🎹 检测到粘贴快捷键 (Cmd+V)")
            handlePasteEvent()
            return true // 消费事件
        }
        
        // 检查是否是 Escape 键（取消选中）
        if event.keyCode == 53 { // keyCode 53 是 ESC 键
            print("🎹 检测到ESC键，取消选中")
            DispatchQueue.main.async {
                self.appState.deselectFloatingWindow()
            }
            return true // 消费事件
        }
        
        return false // 不消费事件
    }
    
    // 激活键盘监听
    private func activateKeyboardListening() {
        print("🎧 激活键盘监听")
        
        // 确保悬浮窗窗口成为焦点以接收键盘事件
        DispatchQueue.main.async {
            // 寻找包含 FloatingButtonView 的窗口
            for window in NSApp.windows {
                if window.contentView is AcceptFirstMouseHostingView<FloatingButtonView> {
                    window.makeKey()
                    print("🔑 悬浮窗已成为关键窗口")
                    break
                } else if let contentView = window.contentView,
                          contentView.subviews.first(where: { $0 is AcceptFirstMouseHostingView<FloatingButtonView> }) != nil {
                    window.makeKey()
                    print("🔑 找到悬浮窗并设为关键窗口")
                    break
                }
            }
        }
    }
    
    // 停止键盘监听
    private func deactivateKeyboardListening() {
        print("🎧 停止键盘监听")
        // 这里暂时不需要移除监听器，因为我们需要保持全局监听
        // 只是改变状态检查 appState.isFloatingWindowSelected
    }
    
    // 处理粘贴事件
    private func handlePasteEvent() {
        print("📋 处理粘贴事件")
        
        let pasteboard = NSPasteboard.general
        
        // 检查粘贴板中是否有图片
        if let imageData = getImageFromPasteboard(pasteboard) {
            print("✅ 粘贴板中发现图片，大小: \(imageData.count) 字节")
            uploadImageData(imageData)
        } else {
            print("❌ 粘贴板中没有找到图片")
            showToastMessage("粘贴板中没有图片")
        }
    }
    
    // 增强的图片文件检查
    private func isImageFile(_ url: URL) -> Bool {
        let supportedExtensions = [
            // 常见图片格式
            "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif",
            // 现代图片格式
            "webp", "heic", "heif",
            // RAW格式（部分支持）
            "raw", "cr2", "nef", "arw"
        ]
        
        let fileExtension = url.pathExtension.lowercased()
        let isSupported = supportedExtensions.contains(fileExtension)
        
        print("🔍 文件类型检查: \(fileExtension) -> \(isSupported ? "支持" : "不支持")")
        
        return isSupported
    }
    
    // 更新的上传图片到服务器方法
    private func uploadImageToServer(imageData: Data) {
        print("📸 开始上传图片，大小: \(imageData.count) 字节")
        print("🏷️ 图片标签: \"\(appState.imageLabel)\"")
        print("🔄 当前模式: \(appState.modeDescription)")
        
        isUploading = true
        showUploadIndicator = false
        
        // 检查在线模式是否需要登录
        if appState.requiresLogin {
            showToastMessage("请先登录")
            isUploading = false
            return
        }
        
        // 使用智能上传方法
        ServerManager.shared.smartUploadImage(
            imageData: imageData,
            label: appState.imageLabel,
            isOnlineMode: appState.isOnlineMode,
            authToken: appState.authToken
        ) { result in
            DispatchQueue.main.async {
                self.isUploading = false
                
                switch result {
                case .success(let response):
                    print("✅ 拖拽图片上传成功: \(response)")
                    self.showUploadResult(appState.isOnlineMode ? "在线上传成功" : "本地上传成功")
                    
                case .failure(let error):
                    print("❌ 拖拽图片上传失败: \(error.localizedDescription)")
                    let errorMessage = appState.isOnlineMode ? "在线上传失败" : "本地上传失败"
                    self.showUploadResult("\(errorMessage)")
                    self.showToastMessage(error.localizedDescription)
                }
            }
        }
    }
    
    // 改进粘贴板图片获取，添加更多格式支持
    private func getImageFromPasteboard(_ pasteboard: NSPasteboard) -> Data? {
        print("📋 分析粘贴板内容...")
        
        // 1. 尝试获取 TIFF 格式的图片（最常见）
        if let tiffData = pasteboard.data(forType: .tiff) {
            print("📋 找到TIFF格式图片")
            if let image = NSImage(data: tiffData),
               let bitmapRep = NSBitmapImageRep(data: image.tiffRepresentation!),
               let jpegData = bitmapRep.representation(using: .jpeg, properties: [:]) {
                return jpegData
            }
        }
        
        // 2. 尝试获取 PNG 格式的图片
        if let pngData = pasteboard.data(forType: .png) {
            print("📋 找到PNG格式图片")
            if let image = NSImage(data: pngData),
               let bitmapRep = NSBitmapImageRep(data: image.tiffRepresentation!),
               let jpegData = bitmapRep.representation(using: .jpeg, properties: [:]) {
                return jpegData
            }
        }
        
        // 3. 尝试获取文件 URL（可能是图片文件）
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            print("📋 找到文件URL: \(urls.count)个")
            for url in urls {
                print("📋 检查文件: \(url.lastPathComponent)")
                if isImageFile(url) {
                    if let image = NSImage(contentsOf: url),
                       let bitmapRep = NSBitmapImageRep(data: image.tiffRepresentation!),
                       let jpegData = bitmapRep.representation(using: .jpeg, properties: [:]) {
                        print("✅ 成功从文件URL获取图片")
                        return jpegData
                    }
                } else {
                    print("❌ 文件不是支持的图片格式: \(url.pathExtension)")
                }
            }
        }
        
        // 4. 检查其他可能的图片类型，使用字符串标识符
        let imageTypeIdentifiers = ["public.jpeg", "com.compuserve.gif", "com.microsoft.bmp"]
        for identifier in imageTypeIdentifiers {
            let pasteboardType = NSPasteboard.PasteboardType(identifier)
            if let imageData = pasteboard.data(forType: pasteboardType) {
                print("📋 找到\(identifier)格式图片")
                if let image = NSImage(data: imageData),
                   let bitmapRep = NSBitmapImageRep(data: image.tiffRepresentation!),
                   let jpegData = bitmapRep.representation(using: .jpeg, properties: [:]) {
                    return jpegData
                }
            }
        }
        
        // 调试信息：显示粘贴板中的所有类型
        let availableTypes = pasteboard.types?.map { $0.rawValue } ?? []
        print("📋 粘贴板包含的类型: \(availableTypes)")
        
        // 检查是否有文本（提供更具体的错误信息）
        if pasteboard.string(forType: .string) != nil {
            print("📋 粘贴板包含文本，不是图片")
        }
        
        return nil
    }
    
    // 处理文件拖拽的方法
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        print("📁 处理文件拖拽")
        
        guard let provider = providers.first else {
            showToastMessage("无法获取拖拽文件")
            return false
        }
        
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ 加载拖拽文件失败: \(error.localizedDescription)")
                    self.showToastMessage("文件加载失败")
                    return
                }
                
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    print("❌ 无法解析拖拽的文件URL")
                    self.showToastMessage("无法识别文件")
                    return
                }
                
                print("📎 拖拽文件URL: \(url.absoluteString)")
                print("📎 文件扩展名: \(url.pathExtension)")
                
                // 验证文件类型
                if !self.isImageFile(url) {
                    let fileType = url.pathExtension.isEmpty ? "未知文件" : "\(url.pathExtension.uppercased())文件"
                    print("❌ 不支持的文件类型: \(fileType)")
                    self.showToastMessage("不支持\(fileType)，请上传图片文件")
                    return
                }
                
                // 尝试加载图片
                guard let nsImage = NSImage(contentsOf: url) else {
                    print("❌ 无法加载图片文件")
                    self.showToastMessage("图片文件损坏或格式不支持")
                    return
                }
                
                // 转换为JPEG格式
                guard let tiffData = nsImage.tiffRepresentation,
                      let bitmapRep = NSBitmapImageRep(data: tiffData),
                      let jpegData = bitmapRep.representation(using: .jpeg, properties: [:]) else {
                    print("❌ 图片格式转换失败")
                    self.showToastMessage("图片处理失败")
                    return
                }
                
                print("✅ 图片验证通过，开始上传")
                self.uploadImageToServer(imageData: jpegData)
            }
        }
        
        return true
    }
    
    // 上传图片数据（粘贴板用）
    private func uploadImageData(_ imageData: Data) {
        print("📤 开始上传粘贴的图片")
        
        isUploading = true
        showUploadIndicator = false
        
        // 检查在线模式是否需要登录
        if appState.requiresLogin {
            showToastMessage("请先登录")
            isUploading = false
            return
        }
        
        // 使用智能上传方法
        ServerManager.shared.smartUploadImage(
            imageData: imageData,
            label: appState.imageLabel,
            isOnlineMode: appState.isOnlineMode,
            authToken: appState.authToken
        ) { result in
            DispatchQueue.main.async {
                self.isUploading = false
                
                switch result {
                case .success(let response):
                    print("✅ 粘贴图片上传成功: \(response)")
                    self.showUploadResult(appState.isOnlineMode ? "在线上传成功" : "本地上传成功")
                    
                case .failure(let error):
                    print("❌ 粘贴图片上传失败: \(error.localizedDescription)")
                    let errorMessage = appState.isOnlineMode ? "在线上传失败" : "本地上传失败"
                    self.showUploadResult("\(errorMessage)")
                    self.showToastMessage(error.localizedDescription)
                }
            }
        }
    }
    
    // 显示 Toast 消息
    private func showToastMessage(_ message: String) {
        toastMessage = message
        withAnimation(.easeInOut(duration: 0.3)) {
            showToast = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showToast = false
            }
        }
    }
    
    // 设置通知监听器
    private func setupNotificationListeners() {
        // 监听截图Toast消息
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ShowToastMessage"),
            object: nil,
            queue: .main
        ) { notification in
            if let message = notification.object as? String {
                self.showToastMessage(message)
            }
        }
        
        print("📡 悬浮窗通知监听器已设置")
    }
    
    private var circleButton: some View {
        ZStack {
            // 外圈脉冲效果（拖拽时显示）
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
            
            // 选中状态的波纹效果
            if appState.isFloatingWindowSelected {
                ZStack {
                    // 第一层波纹
                    Circle()
                        .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                        .scaleEffect(rippleAnimation ? 1.8 : 1.0)
                        .opacity(rippleAnimation ? 0.0 : 0.6)
                    
                    // 第二层波纹
                    Circle()
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1.5)
                        .scaleEffect(rippleAnimation ? 2.2 : 1.0)
                        .opacity(rippleAnimation ? 0.0 : 0.4)
                        .animation(
                            .easeOut(duration: 2.0).repeatForever(autoreverses: false),
                            value: rippleAnimation
                        )
                    
                    // 第三层波纹
                    Circle()
                        .stroke(Color.blue.opacity(0.15), lineWidth: 1)
                        .scaleEffect(rippleAnimation ? 2.6 : 1.0)
                        .opacity(rippleAnimation ? 0.0 : 0.3)
                        .animation(
                            .easeOut(duration: 2.5).repeatForever(autoreverses: false).delay(0.3),
                            value: rippleAnimation
                        )
                }
                .animation(
                    .easeOut(duration: 1.5).repeatForever(autoreverses: false),
                    value: rippleAnimation
                )
            }
            
            // 主按钮背景（白色圆形）
            Circle()
                .fill(appState.isFloatingWindowSelected ? Color.blue.opacity(0.1) : Color.white)
                .overlay(
                    Circle()
                        .stroke(appState.isFloatingWindowSelected ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: appState.isFloatingWindowSelected ? 2 : 1)
                )
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .scaleEffect(isDragOver ? 1.1 : 1.0)
                .scaleEffect(appState.isFloatingWindowSelected ? 1.02 : 1.0)
            
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
                        .frame(width: 38, height: 38)
                        .foregroundColor(appState.isFloatingWindowSelected ? .blue : .gray)
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
        .onTapGesture(count: 2) {
            handleDoubleTap()
        }
        .onTapGesture {
            handleSingleTap()
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDragOver) { providers in
            return handleDrop(providers: providers)
        }
        .onChange(of: isDragOver) { _, isDragging in
            if isDragging {
                pulseAnimation = true
            } else {
                pulseAnimation = false
            }
        }
        .onChange(of: appState.isFloatingWindowSelected) { _, isSelected in
            if isSelected {
                rippleAnimation = true
            } else {
                rippleAnimation = false
            }
        }
        .help("单击选中/取消选中，双击展开输入框，拖拽图片上传")
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
    
    private func handleSingleTap() {
        // 取消之前的单击延迟任务
        singleTapWorkItem?.cancel()
        
        // 创建新的延迟任务
        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.appState.toggleFloatingWindowSelection()
            }
        }
        
        singleTapWorkItem = workItem
        
        // 延迟200ms执行单击，等待可能的双击
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }
    
    private func handleDoubleTap() {
        // 取消单击延迟任务
        singleTapWorkItem?.cancel()
        singleTapWorkItem = nil
        
        // 立即执行双击操作
        toggleExpansion()
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
    
    // 显示上传结果
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

