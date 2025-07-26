# InstaGo 代码签名和 Hardened Runtime 配置指南

## 概述

本指南将帮助您解决 `instago-server` 的 Hardened Runtime 问题，确保应用程序能够成功通过 Apple 的公证流程。

## 问题诊断

根据您的反馈，当前的问题是：
- `instago-server` 缺少 `Runtime Version=2.0` 标记
- 应用程序使用 adhoc 签名而不是开发者证书签名
- 公证时报告 Hardened Runtime 错误

## 解决方案

### 步骤 1: 获取 Apple 开发者证书

在开始之前，您需要有效的 Apple 开发者证书。

#### 方法 1: 通过 Xcode 获取（推荐）

1. 打开 Xcode
2. 前往 `Xcode → Preferences → Accounts`
3. 点击 `+` 添加您的 Apple ID（需要是 Apple 开发者计划成员）
4. 选择您的开发者团队
5. 点击 `Manage Certificates...`
6. 点击 `+` 并选择 `Developer ID Application`
7. 等待证书下载和安装

#### 方法 2: 从 Apple Developer 网站下载

1. 登录 [Apple Developer](https://developer.apple.com/)
2. 前往 `Certificates, Identifiers & Profiles`
3. 创建新的 `Developer ID Application` 证书
4. 下载并双击安装

### 步骤 2: 验证证书安装

运行以下命令检查证书是否正确安装：

```bash
security find-identity -v -p codesigning
```

您应该看到类似这样的输出：
```
1) ABCD1234... "Developer ID Application: Your Name (TEAM_ID)"
```

### 步骤 3: 重新构建和签名 instago-server

#### 3.1 重新构建 Go 服务器

```bash
cd go-client
./build.sh
```

这将使用优化的编译设置重新构建 `instago-server`。

#### 3.2 签名 instago-server

```bash
cd mac-client
./sign_instago_server.sh
```

或者，如果您有特定的证书：

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAM_ID)"
./sign_instago_server.sh
```

#### 3.3 验证签名结果

脚本完成后，您应该看到：

```bash
codesign --display --verbose=4 InstaGo/instago-server
```

输出中应该包含：
```
Runtime Version=2.0  # 或更高版本
```

### 步骤 4: 完整的应用程序打包和公证

#### 4.1 设置公证凭据

设置环境变量：

```bash
export NOTARIZATION_USERNAME="your-apple-id@example.com"
export NOTARIZATION_PASSWORD="app-specific-password"
export NOTARIZATION_TEAM_ID="YOUR_TEAM_ID"
```

**注意**: 应用专用密码可以在 [appleid.apple.com](https://appleid.apple.com/) 生成。

#### 4.2 运行完整的构建和公证流程

```bash
./build_signed_dmg.sh
```

这个脚本将：
1. 构建 Release Archive
2. 深度签名所有可执行文件（包括 `instago-server`）
3. 启用所有文件的 Hardened Runtime
4. 提交公证
5. 创建最终的 DMG

### 步骤 5: 验证最终结果

#### 5.1 验证 DMG

```bash
xcrun stapler validate InstaGo-v1.0-Signed.dmg
```

#### 5.2 验证应用程序中的所有可执行文件

挂载 DMG 并检查：

```bash
# 挂载 DMG
hdiutil attach InstaGo-v1.0-Signed.dmg

# 检查主应用
codesign --display --verbose=4 "/Volumes/InstaGo/InstaGo.app"

# 检查 instago-server
codesign --display --verbose=4 "/Volumes/InstaGo/InstaGo.app/Contents/MacOS/instago-server"

# 卸载 DMG
hdiutil detach "/Volumes/InstaGo"
```

## 脚本说明

### build.sh (Go 项目)

- 使用优化的编译标志确保与代码签名兼容
- 添加 `-extldflags=-Wl,-headerpad_max_install_names` 为签名预留空间
- 使用 `-trimpath` 确保可重现的构建

### sign_instago_server.sh

- 专门处理 `instago-server` 的签名
- 自动检测和使用可用的开发者证书
- 启用 Hardened Runtime (`--options runtime`)
- 提供详细的验证和诊断信息

### build_signed_dmg.sh (已更新)

- 增强的深度签名功能
- 专门处理 `instago-server` 的签名
- 验证所有可执行文件的 Hardened Runtime
- 支持完整的公证流程

## 常见问题

### Q: 签名失败，提示证书不存在

**A**: 确保您已经安装了有效的 Developer ID Application 证书。运行 `security find-identity -v -p codesigning` 检查。

### Q: 公证失败，提示 Hardened Runtime 错误

**A**: 确保所有可执行文件都使用了 `--options runtime` 标志签名。使用我们提供的脚本可以自动处理这个问题。

### Q: 如何检查特定文件是否启用了 Hardened Runtime？

**A**: 使用以下命令：
```bash
codesign --display --verbose=4 /path/to/file
```
查找 `Runtime Version=2.0` 或更高版本。

### Q: 构建的应用在其他 Mac 上无法运行

**A**: 确保：
1. 使用了 Developer ID 证书（不是开发证书）
2. 完成了公证流程
3. 使用了 `xcrun stapler staple` 装订公证票据

## 快速命令参考

```bash
# 1. 重新构建服务器
cd go-client && ./build.sh

# 2. 检查签名状态
cd mac-client && ./sign_instago_server.sh --check-only

# 3. 签名服务器
./sign_instago_server.sh

# 4. 完整打包（需要证书和公证凭据）
./build_signed_dmg.sh

# 5. 验证最终产品
xcrun stapler validate InstaGo-v1.0-Signed.dmg
```

## 联系支持

如果您在执行这些步骤时遇到问题，请提供以下信息：

1. `security find-identity -v -p codesigning` 的输出
2. `codesign --display --verbose=4 InstaGo/instago-server` 的输出
3. 任何错误消息的完整文本

这将帮助我们快速诊断和解决问题。 