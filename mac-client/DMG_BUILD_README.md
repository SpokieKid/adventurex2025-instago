# InstaGo DMG 打包指南

本指南将帮助您将 InstaGo Mac 应用程序打包成可分发的 DMG 文件。

## 📋 前置条件

### 基本要求
- macOS 10.15 或更高版本
- Xcode 12 或更高版本
- Xcode Command Line Tools
- 有效的 Apple 开发者账户（如需代码签名和公证）

### 安装 Command Line Tools
```bash
xcode-select --install
```

## 🚀 快速开始

### 方法 1: 基本 DMG 打包（无签名）

如果您只是想为自己或内部使用创建 DMG，使用基本脚本：

```bash
# 进入项目目录
cd mac-client

# 给脚本添加执行权限
chmod +x build_dmg.sh

# 运行打包脚本
./build_dmg.sh
```

这将生成 `InstaGo-v1.0.dmg` 文件，适用于：
- 个人使用
- 内部团队分发
- 开发测试

### 方法 2: 签名和公证的 DMG（推荐用于公开分发）

如果您需要分发给其他用户，使用签名脚本：

```bash
# 给脚本添加执行权限
chmod +x build_signed_dmg.sh

# 设置公证环境变量（可选）
export NOTARIZATION_USERNAME="your-apple-id@example.com"
export NOTARIZATION_PASSWORD="your-app-specific-password"
export NOTARIZATION_TEAM_ID="YOUR_TEAM_ID"

# 运行签名打包脚本
./build_signed_dmg.sh
```

## 🔧 配置说明

### 代码签名配置

1. **获取开发者证书**
   - 登录 [Apple Developer Portal](https://developer.apple.com)
   - 下载 "Developer ID Application" 证书
   - 在 Keychain Access 中安装证书

2. **修改脚本中的证书名称**
   编辑 `build_signed_dmg.sh`，修改以下行：
   ```bash
   DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAM_ID)"
   ```
   替换为您实际的证书名称。

### 公证配置

1. **创建应用专用密码**
   - 访问 [appleid.apple.com](https://appleid.apple.com)
   - 登录您的 Apple ID
   - 在"应用专用密码"部分创建新密码

2. **设置环境变量**
   ```bash
   export NOTARIZATION_USERNAME="your-apple-id@example.com"
   export NOTARIZATION_PASSWORD="abcd-efgh-ijkl-mnop"  # 应用专用密码
   export NOTARIZATION_TEAM_ID="ABC123DEFG"           # 团队 ID
   ```

3. **查找团队 ID**
   ```bash
   xcrun altool --list-providers -u "your-apple-id@example.com" -p "your-app-password"
   ```

## 📁 输出文件

### 基本打包
- `InstaGo-v1.0.dmg` - 标准 DMG 文件

### 签名打包
- `InstaGo-v1.0-Signed.dmg` - 签名和公证的 DMG 文件

## 🔍 验证 DMG

### 检查 DMG 完整性
```bash
hdiutil verify InstaGo-v1.0.dmg
```

### 检查代码签名
```bash
# 检查 DMG 签名
codesign -dv InstaGo-v1.0-Signed.dmg

# 挂载 DMG 并检查应用签名
hdiutil attach InstaGo-v1.0-Signed.dmg
codesign -dv "/Volumes/InstaGo/InstaGo.app"
spctl --assess "/Volumes/InstaGo/InstaGo.app"
```

## 🐛 常见问题

### Q: 构建失败，提示找不到 Scheme
**A:** 确保 Xcode 项目中存在名为 "InstaGo" 的 Scheme。可以在 Xcode 中通过 Product → Scheme → Manage Schemes 查看。

### Q: 代码签名失败
**A:** 检查以下几点：
1. 确保已安装正确的开发者证书
2. 证书名称与脚本中的配置一致
3. 证书未过期且有效

### Q: 公证失败
**A:** 常见原因：
1. 应用专用密码错误
2. 团队 ID 不正确
3. 应用程序不符合公证要求（如使用了不被允许的 API）

### Q: DMG 在其他 Mac 上无法打开
**A:** 这通常是权限问题：
1. 使用签名版本的脚本
2. 完成公证流程
3. 确保目标 Mac 允许来自已识别开发者的应用

## 🔄 自动化构建

您可以将这些脚本集成到 CI/CD 流程中：

### GitHub Actions 示例
```yaml
name: Build DMG
on:
  release:
    types: [published]

jobs:
  build:
    runs-on: macos-latest
    steps:
    - uses: actions/checkout@v2
    
    - name: Build DMG
      run: |
        cd mac-client
        chmod +x build_dmg.sh
        ./build_dmg.sh
        
    - name: Upload DMG
      uses: actions/upload-release-asset@v1
      with:
        upload_url: ${{ github.event.release.upload_url }}
        asset_path: ./mac-client/InstaGo-v1.0.dmg
        asset_name: InstaGo-v1.0.dmg
        asset_content_type: application/x-apple-diskimage
```

## 📚 更多资源

- [Apple 代码签名指南](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/)
- [应用公证指南](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [DMG 创建工具文档](https://ss64.com/osx/hdiutil.html)

## 🆘 获得帮助

如果遇到问题：

1. 检查 Xcode 构建日志
2. 验证证书和权限设置
3. 查看 Apple 开发者文档
4. 联系开发团队获得支持

---

**注意**: 代码签名和公证是可选的，但对于公开分发的应用程序强烈推荐。未签名的应用可能会被 macOS 安全机制阻止。 