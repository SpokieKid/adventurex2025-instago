# Mac App 多实例启动问题修复

## 问题描述

从前端 auth 回来时，会启动两个 Mac app 的实例，而不是激活现有的实例。

**具体测试流程问题**:
1. 打开 InstaGo 时状态栏已经是登录状态
2. 用户点击登出
3. 启动前端页面 (https://instago-manage.vercel.app/login?callback=instago://auth)
4. 前端检测到已登录状态，自动发送回调信息
5. 启动了第二个 InstaGo app 实例，并且两个都是未登录状态

## 问题原因

1. **Info.plist 配置缺失**: 没有设置 `LSMultipleInstancesProhibited` 防止多实例启动
2. **URL Scheme 处理**: 系统默认为每个 URL 回调启动新实例
3. **应用激活策略**: 缺少正确的应用激活和窗口管理逻辑
4. **前端状态不同步**: 前端页面保持登录状态，与Mac app的登出状态不一致
5. **重复回调处理**: 缺少对重复回调请求的检测和防护
6. **时序竞争问题**: 登出操作和前端回调之间存在时序冲突

## 修复方案

### 1. Info.plist 配置更新

添加了以下关键配置：

```xml
<!-- 防止多实例启动 -->
<key>LSMultipleInstancesProhibited</key>
<true/>

<!-- 应用类型配置 - 后台应用 -->
<key>LSUIElement</key>
<true/>

<!-- 支持自动终止 -->
<key>NSSupportsAutomaticTermination</key>
<false/>

<!-- 支持突然终止 -->
<key>NSSupportsSuddenTermination</key>
<false/>
```

### 2. AppDelegate 改进

- 添加了 `applicationShouldHandleReopen` 方法处理应用重新打开
- 在 URL 处理中添加了 `NSApp.activate(ignoringOtherApps: true)` 确保应用激活
- 改进了悬浮窗的显示逻辑
- 添加了多实例检测和自动清理逻辑
- 强化了URL处理，防止重复启动

### 3. AppState 回调处理增强

- 添加了回调冷却机制，防止5秒内重复处理相同URL
- 实现了已登录状态下的重新登录确认对话框
- 改进了登出逻辑，清除回调记录确保状态一致性
- 分离了回调处理逻辑，提高代码可维护性

## 测试方法

### 测试步骤

1. **构建并启动应用**:
   ```bash
   cd mac-client
   xcodebuild -scheme InstaGo build
   open InstaGo.app
   ```

2. **验证单实例**:
   - 确认应用在 Activity Monitor 中只有一个实例
   - 检查菜单栏中只有一个 InstaGo 图标

3. **测试 URL Scheme 回调**:
   - 在终端中执行:
     ```bash
     open "instago://auth?token=test_token&user_id=123&user_name=testuser&user_email=test@example.com"
     ```
   - 应该看到应用被激活，而不是启动新实例

4. **测试前端登录流程**:
   - 从菜单栏点击"登录"
   - 在浏览器中完成登录流程
   - 验证回调后只有一个应用实例在运行

5. **测试完整登录流程**:
   ```bash
   cd mac-client
   ./test_login_flow.sh
   ```
   这个脚本会模拟完整的测试流程：
   - 检查初始状态
   - 引导用户登出
   - 模拟前端回调
   - 验证实例数量和登录状态

### 验证成功标准

- ✅ Activity Monitor 中始终只显示一个 InstaGo 进程
- ✅ URL 回调后应用被激活到前台
- ✅ 悬浮窗正确显示
- ✅ 登录回调正确处理

## 技术细节

### LSMultipleInstancesProhibited

这个配置告诉 macOS 系统该应用不允许启动多个实例。当系统尝试启动第二个实例时，会自动激活已存在的实例。

### LSUIElement

设置应用为 UI Element，这样应用不会出现在 Dock 中，但仍然可以处理 URL Scheme。

### URL Scheme 处理流程

1. 系统接收到 `instago://` URL
2. 检查是否有已运行的实例
3. 如果有，激活现有实例并传递 URL
4. 如果没有，启动新实例并传递 URL

## 故障排除

### 如果仍然出现多实例

1. **重新构建应用**: Info.plist 更改需要重新构建
2. **清除系统缓存**: 
   ```bash
   /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user
   ```
3. **重启 macOS**: 确保系统完全识别新的配置
4. **检查前端状态同步**: 
   - 清除浏览器缓存和localStorage
   - 确保前端正确处理登出状态
   - 验证前端不会在用户登出后自动发送回调
5. **手动清理进程**:
   ```bash
   pkill -f InstaGo
   ```
6. **检查Bundle Identifier**: 确保没有重复的应用标识符

### 调试日志

应用会输出详细的日志信息：
- `🎯 应用启动完成`
- `🔗 收到URL事件`
- `📊 当前运行的InstaGo实例数`
- `⏰ 检测到重复回调请求，忽略处理`
- `⚠️ 用户已登录，收到新的登录回调`
- `✅ 确认为登录回调，激活应用并发送通知`
- `🔄 应用重新打开请求`
- `🔚 尝试终止额外的InstaGo实例`

可以通过 Console.app 查看这些日志来诊断问题。

**关键诊断命令**:
```bash
# 查看应用日志
log show --predicate 'process == "InstaGo"' --last 10m

# 检查URL scheme注册
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump | grep -i instago

# 检查运行的实例
ps aux | grep -v grep | grep InstaGo
```

## 后续改进

1. 添加应用版本检查，确保只有最新版本在运行
2. 改进错误处理，处理异常的URL格式
3. 添加用户通知，提示登录状态变化
4. 实现前端和Mac app之间的状态同步机制
5. 添加回调URL签名验证，防止恶意回调
6. 改进用户体验，在重新登录时提供更好的反馈
7. 添加自动恢复机制，处理异常状态

## 前端配合建议

为了彻底解决多实例问题，建议前端也做以下改进：

1. **状态同步**: 在检测到用户登出时，清除本地存储的登录状态
2. **避免自动回调**: 不要在用户未主动登录时自动发送回调
3. **回调去重**: 实现客户端的回调去重机制
4. **状态检查**: 在发送回调前，通过其他方式确认用户的真实登录意图 