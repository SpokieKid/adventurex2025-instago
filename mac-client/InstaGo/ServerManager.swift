 //
//  ServerManager.swift
//  InstaGo
//
//  Created by 陈瀚翔 on 23/7/2025.
//

import Foundation
import Network

class ServerManager: ObservableObject {
    static let shared = ServerManager()
    
    @Published var isServerRunning = false
    @Published var serverPort = 8080
    @Published var serverURL = "http://localhost:8080"
    
    private var serverProcess: Process?
    private let serverExecutableName = "instago-server"
    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "ServerManager")
    
    private init() {
        print("🔧 ServerManager 初始化")
        setupNetworkMonitoring()
    }
    
    deinit {
        stopServer()
        monitor?.cancel()
    }
    
    // MARK: - 服务器管理
    
    func startServer() {
        guard !isServerRunning else {
            print("🟡 服务器已在运行中")
            return
        }
        
        print("🚀 开始启动 Go 服务器...")
        
        guard let serverPath = getServerExecutablePath() else {
            print("❌ 找不到服务器可执行文件")
            return
        }
        
        print("📍 服务器路径: \(serverPath)")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: serverPath)
        
        // 设置环境变量
        var environment = ProcessInfo.processInfo.environment
        environment["PORT"] = "\(serverPort)"
        
        // 设置数据库路径到应用支持目录
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, 
                                                   in: .userDomainMask).first!
        let instagoAppSupportURL = appSupportURL.appendingPathComponent("InstaGo")
        
        // 确保目录存在
        try? FileManager.default.createDirectory(at: instagoAppSupportURL, 
                                               withIntermediateDirectories: true, 
                                               attributes: nil)
        
        let dbPath = instagoAppSupportURL.appendingPathComponent("instago.db").path
        environment["DB_PATH"] = dbPath
        
        // 加载.env文件中的环境变量
        loadEnvironmentVariables(into: &environment)
        
        process.environment = environment
        
        // 设置输出重定向（可选，用于调试）
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        // 监听输出（可选，用于调试）
        pipe.fileHandleForReading.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                print("📄 服务器输出: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
        
        // 设置进程终止处理
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                print("🔴 服务器进程已终止，退出码: \(process.terminationStatus)")
                self?.isServerRunning = false
                self?.serverProcess = nil
                
                // 清理输出重定向
                pipe.fileHandleForReading.readabilityHandler = nil
            }
        }
        
        do {
            try process.run()
            self.serverProcess = process
            
            print("✅ 服务器进程已启动，PID: \(process.processIdentifier)")
            
            // 等待一段时间然后检查服务器是否真正启动
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.checkServerHealth()
            }
            
        } catch {
            print("❌ 启动服务器失败: \(error.localizedDescription)")
        }
    }
    
    func stopServer() {
        print("🛑 正在停止服务器...")
        
        // 如果有已知的服务器进程，先尝试优雅终止
        if let process = serverProcess, process.isRunning {
            print("🔸 终止已知服务器进程 PID: \(process.processIdentifier)")
            process.terminate()
            
            // 等待一段时间检查是否成功终止
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                if process.isRunning {
                    print("⚠️ 优雅终止超时，强制杀死进程")
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }
        
        // 额外保险：查找并终止所有占用8080端口的进程
        killProcessesOnPort(serverPort)
        
        isServerRunning = false
        serverProcess = nil
        
        print("✅ 服务器停止流程完成")
    }
    
    // MARK: - 端口清理
    
    private func killProcessesOnPort(_ port: Int) {
        print("🔍 查找占用端口 \(port) 的进程...")
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/lsof")
        task.arguments = ["-ti", ":\(port)"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                let pids = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: .newlines)
                    .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
                
                if !pids.isEmpty {
                    print("🎯 发现占用端口 \(port) 的进程: \(pids)")
                    
                    for pid in pids {
                        print("🔫 终止进程 PID: \(pid)")
                        
                        // 先尝试SIGTERM优雅终止
                        kill(pid, SIGTERM)
                        
                        // 短暂等待后强制杀死
                        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                            kill(pid, SIGKILL)
                        }
                    }
                } else {
                    print("✅ 端口 \(port) 未被占用")
                }
            } else {
                print("✅ 端口 \(port) 未被占用")
            }
        } catch {
            print("⚠️ 检查端口占用失败: \(error.localizedDescription)")
        }
    }
    
    func restartServer() {
        print("🔄 重启服务器...")
        stopServer()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.startServer()
        }
    }
    
    // MARK: - 服务器健康检查
    
    func checkServerHealth() {
        let healthURL = URL(string: "\(serverURL)/")!
        
        let task = URLSession.shared.dataTask(with: healthURL) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200 {
                    print("✅ 服务器健康检查通过")
                    self?.isServerRunning = true
                } else {
                    print("❌ 服务器健康检查失败: \(error?.localizedDescription ?? "未知错误")")
                    self?.isServerRunning = false
                }
            }
        }
        
        task.resume()
    }
    
    // MARK: - 工具方法
    
    private func loadEnvironmentVariables(into environment: inout [String: String]) {
        // 尝试多个可能的.env文件位置
        let possibleEnvPaths = [
            // Swift项目目录中的.env文件
            Bundle.main.path(forResource: ".env", ofType: nil),
            Bundle.main.resourcePath?.appending("/.env"),
            // 应用包中的.env文件
            "\(Bundle.main.bundlePath)/.env",
            // 开发时的路径
            FileManager.default.currentDirectoryPath + "/.env",
            FileManager.default.currentDirectoryPath + "/../.env",
            FileManager.default.currentDirectoryPath + "/../../.env"
        ]
        
        var loadedEnvPath: String?
        
        for envPath in possibleEnvPaths {
            guard let path = envPath, FileManager.default.fileExists(atPath: path) else {
                continue
            }
            
            print("🔍 找到.env文件: \(path)")
            loadedEnvPath = path
            break
        }
        
        guard let envPath = loadedEnvPath else {
            print("⚠️ 未找到.env文件，使用默认环境变量")
            return
        }
        
        do {
            let envContent = try String(contentsOfFile: envPath, encoding: .utf8)
            print("📄 读取.env文件内容，大小: \(envContent.count) 字符")
            
            // 解析.env文件内容
            let lines = envContent.components(separatedBy: .newlines)
            var loadedCount = 0
            
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // 跳过空行和注释
                if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                    continue
                }
                
                // 解析 KEY=VALUE 格式
                let components = trimmedLine.components(separatedBy: "=")
                if components.count >= 2 {
                    let key = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = components[1...].joined(separator: "=").trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // 移除引号（如果有）
                    let cleanValue = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    
                    environment[key] = cleanValue
                    loadedCount += 1
                    
                    // 记录加载的环境变量（但不显示敏感信息）
                    if key.contains("API_KEY") || key.contains("SECRET") || key.contains("PASSWORD") {
                        print("🔐 加载环境变量: \(key)=***")
                    } else {
                        print("📝 加载环境变量: \(key)=\(cleanValue)")
                    }
                }
            }
            
            print("✅ 成功加载 \(loadedCount) 个环境变量")
            
        } catch {
            print("❌ 读取.env文件失败: \(error.localizedDescription)")
        }
    }
    
    private func getServerExecutablePath() -> String? {
        // 首先尝试从应用包中获取
        if let bundlePath = Bundle.main.path(forResource: serverExecutableName, ofType: nil) {
            return bundlePath
        }
        
        // 尝试从应用包的 InstaGo 目录中获取
        if let resourcePath = Bundle.main.resourcePath {
            let serverPath = "\(resourcePath)/\(serverExecutableName)"
            if FileManager.default.fileExists(atPath: serverPath) {
                return serverPath
            }
        }
        
        // 尝试从项目开发目录获取（开发时）
        let currentDir = FileManager.default.currentDirectoryPath
        let devServerPath = "\(currentDir)/\(serverExecutableName)"
        if FileManager.default.fileExists(atPath: devServerPath) {
            return devServerPath
        }
        
        // 尝试从 go-client 目录获取
        let goClientServerPath = "\(currentDir)/../go-client/\(serverExecutableName)"
        if FileManager.default.fileExists(atPath: goClientServerPath) {
            return goClientServerPath
        }
        
        print("🔍 搜索服务器可执行文件的路径:")
        print("   - Bundle: \(Bundle.main.resourcePath ?? "无")")
        print("   - 当前目录: \(currentDir)")
        print("   - Go客户端目录: \(goClientServerPath)")
        
        return nil
    }
    
    private func setupNetworkMonitoring() {
        monitor = NWPathMonitor()
        monitor?.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied {
                print("🌐 网络连接可用")
                // 网络恢复时可以重新检查服务器状态
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if self?.serverProcess?.isRunning == true {
                        self?.checkServerHealth()
                    }
                }
            } else {
                print("🚫 网络连接不可用")
            }
        }
        monitor?.start(queue: queue)
    }
    
    // MARK: - 应用生命周期集成
    
    func applicationDidFinishLaunching() {
        print("🎯 ServerManager: 应用启动完成，开始启动服务器")
        startServer()
    }
    
    func applicationWillTerminate() {
        print("🔚 ServerManager: 应用即将退出，停止服务器")
        
        // 停止网络监控
        monitor?.cancel()
        monitor = nil
        
        // 停止服务器
        stopServer()
        
        // 确保所有异步任务完成
        if let process = serverProcess, process.isRunning {
            print("⏳ 等待服务器进程完全终止...")
            
            // 同步等待进程终止，最多等待5秒
            let deadline = Date().addingTimeInterval(5.0)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            
            // 如果还在运行，强制终止
            if process.isRunning {
                print("🚨 强制终止残留的服务器进程")
                kill(process.processIdentifier, SIGKILL)
            }
        }
        
        // 最后再次清理端口
        killProcessesOnPort(serverPort)
        
        print("✅ ServerManager: 服务器清理完成")
    }
}

// MARK: - 扩展：服务器状态查询

extension ServerManager {
    
    var isHealthy: Bool {
        return isServerRunning && serverProcess?.isRunning == true
    }
    
    var statusDescription: String {
        if isHealthy {
            return "运行中 (端口 \(serverPort))"
        } else if serverProcess?.isRunning == true {
            return "启动中..."
        } else {
            return "已停止"
        }
    }
    
    func getServerInfo() -> [String: Any] {
        return [
            "isRunning": isServerRunning,
            "port": serverPort,
            "url": serverURL,
            "processID": serverProcess?.processIdentifier ?? -1,
            "isProcessRunning": serverProcess?.isRunning ?? false
        ]
    }
}

// MARK: - 扩展：API 调用辅助方法

extension ServerManager {
    
    func uploadImage(imageData: Data, label: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard isServerRunning else {
            completion(.failure(NSError(domain: "ServerManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "服务器未运行"])))
            return
        }
        
        let uploadURL = URL(string: "\(serverURL)/upload")!
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        
        // 创建multipart/form-data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // 添加图片数据
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        
        // 添加标签
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"label\"\r\n\r\n".data(using: .utf8)!)
        body.append(label.data(using: .utf8) ?? Data())
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(NSError(domain: "ServerManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "无效响应数据"])))
                    return
                }
                
                completion(.success(json))
            }
        }.resume()
    }
    
    func searchImages(query: String, limit: Int = 10, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard isServerRunning else {
            completion(.failure(NSError(domain: "ServerManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "服务器未运行"])))
            return
        }
        
        let searchURL = URL(string: "\(serverURL)/search")!
        var request = URLRequest(url: searchURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "query": query,
            "limit": limit
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(NSError(domain: "ServerManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "无效响应数据"])))
                    return
                }
                
                completion(.success(json))
            }
        }.resume()
    }
}