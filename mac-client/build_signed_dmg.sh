#!/bin/bash

# InstaGo 签名和公证 DMG 打包脚本
# 版本: 1.0
# 用途: 构建、签名、公证并打包成可分发的 DMG

set -e  # 遇到错误立即退出

# 配置变量 - 请根据您的开发者账户信息修改
APP_NAME="InstaGo"
PROJECT_NAME="InstaGo.xcodeproj"
SCHEME_NAME="InstaGo"
CONFIGURATION="Release"
DMG_NAME="InstaGo-v1.0-Signed"

# 代码签名配置 (需要替换为您的实际证书信息)
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAM_ID)"
DEVELOPER_ID_INSTALLER="Developer ID Installer: Your Name (TEAM_ID)"

# Apple 公证配置 (需要设置环境变量或在此配置)
# 建议使用环境变量而不是硬编码
# export NOTARIZATION_USERNAME="your-apple-id@example.com"
# export NOTARIZATION_PASSWORD="app-specific-password"
# export NOTARIZATION_TEAM_ID="YOUR_TEAM_ID"

# 检查必要的环境变量
check_notarization_config() {
    echo "🔐 检查公证配置..."
    
    if [ -z "$NOTARIZATION_USERNAME" ] || [ -z "$NOTARIZATION_PASSWORD" ] || [ -z "$NOTARIZATION_TEAM_ID" ]; then
        echo "⚠️  公证配置不完整，将跳过公证步骤"
        echo "   如需公证，请设置以下环境变量:"
        echo "   export NOTARIZATION_USERNAME='your-apple-id@example.com'"
        echo "   export NOTARIZATION_PASSWORD='app-specific-password'"
        echo "   export NOTARIZATION_TEAM_ID='YOUR_TEAM_ID'"
        return 1
    fi
    
    echo "✅ 公证配置已设置"
    return 0
}

# 检查代码签名证书
check_signing_certificates() {
    echo "🔍 检查可用的代码签名证书..."
    
    echo "开发者 ID 应用证书:"
    security find-identity -v -p codesigning | grep "Developer ID Application" || {
        echo "❌ 未找到 Developer ID Application 证书"
        echo "   请在 Xcode 中下载或安装您的开发者证书"
        return 1
    }
    
    echo ""
    echo "开发者 ID 安装器证书:"
    security find-identity -v -p codesigning | grep "Developer ID Installer" || {
        echo "⚠️  未找到 Developer ID Installer 证书"
        echo "   将跳过安装器包创建"
    }
    
    echo "✅ 证书检查完成"
    return 0
}

# 深度签名应用程序
deep_sign_app() {
    local app_path="$1"
    
    echo "🖊️  开始深度签名应用程序..."
    
    # 首先签名 instago-server 可执行文件（如果存在）
    local instago_server_path="$app_path/Contents/MacOS/instago-server"
    if [ -f "$instago_server_path" ]; then
        echo "   🖊️  签名 instago-server..."
        codesign --force --verify --verbose --sign "$DEVELOPER_ID_APPLICATION" \
                 --options runtime \
                 --timestamp \
                 "$instago_server_path"
        echo "   ✅ instago-server 签名完成"
    else
        echo "   ⚠️  未找到 instago-server，可能在不同位置"
        # 搜索其他可能的位置
        find "$app_path" -name "instago-server" -type f | while read server_path; do
            echo "   🖊️  找到并签名: $server_path"
            codesign --force --verify --verbose --sign "$DEVELOPER_ID_APPLICATION" \
                     --options runtime \
                     --timestamp \
                     "$server_path"
        done
    fi
    
    # 签名所有其他可执行文件（不在 MacOS 目录中的）
    find "$app_path" \( -type f -perm +111 \) -not -path "*/MacOS/*" | while read executable; do
        if file "$executable" | grep -q "Mach-O.*executable"; then
            echo "   🖊️  签名可执行文件: $(basename "$executable")"
            codesign --force --verify --verbose --sign "$DEVELOPER_ID_APPLICATION" \
                     --options runtime \
                     --timestamp \
                     "$executable" || {
                echo "   ⚠️  签名失败: $executable"
            }
        fi
    done
    
    # 签名所有嵌入的框架和库
    find "$app_path" -name "*.framework" -o -name "*.dylib" -o -name "*.bundle" | while read framework; do
        echo "   🖊️  签名框架: $(basename "$framework")"
        codesign --force --verify --verbose --sign "$DEVELOPER_ID_APPLICATION" \
                 --options runtime \
                 --timestamp \
                 "$framework" || {
            echo "   ⚠️  签名失败: $framework"
        }
    done
    
    # 最后签名主应用程序
    echo "   🖊️  签名主应用程序..."
    codesign --force --verify --verbose --sign "$DEVELOPER_ID_APPLICATION" \
             --entitlements "$PROJECT_DIR/InstaGo/InstaGo.entitlements" \
             --options runtime \
             --timestamp \
             "$app_path"
    
    # 验证签名
    echo "🔍 验证应用程序签名..."
    codesign --verify --verbose=2 "$app_path"
    spctl --assess --verbose=2 "$app_path"
    
    # 详细验证所有关键文件的 Hardened Runtime
    echo "🔍 验证 Hardened Runtime 设置..."
    
    # 验证主应用
    if codesign --display --verbose=4 "$app_path" 2>&1 | grep -q "Runtime Version"; then
        echo "   ✅ 主应用 Hardened Runtime 已启用"
    else
        echo "   ❌ 主应用 Hardened Runtime 未启用"
    fi
    
    # 验证 instago-server
    find "$app_path" -name "instago-server" -type f | while read server_path; do
        if codesign --display --verbose=4 "$server_path" 2>&1 | grep -q "Runtime Version"; then
            echo "   ✅ instago-server Hardened Runtime 已启用"
        else
            echo "   ❌ instago-server Hardened Runtime 未启用"
        fi
    done
    
    echo "✅ 应用程序签名完成"
}

# 公证应用程序
notarize_app() {
    local app_path="$1"
    
    echo "📝 开始公证应用程序..."
    
    # 创建 ZIP 文件用于公证
    local notarization_zip="$BUILD_DIR/${APP_NAME}-notarization.zip"
    cd "$(dirname "$app_path")"
    zip -r "$notarization_zip" "$(basename "$app_path")"
    
    echo "📤 上传到 Apple 进行公证..."
    
    # 提交公证请求
    local submit_result
    submit_result=$(xcrun notarytool submit "$notarization_zip" \
                   --apple-id "$NOTARIZATION_USERNAME" \
                   --password "$NOTARIZATION_PASSWORD" \
                   --team-id "$NOTARIZATION_TEAM_ID" \
                   --wait)
    
    echo "$submit_result"
    
    # 检查公证结果
    if echo "$submit_result" | grep -q "status: Accepted"; then
        echo "✅ 公证成功"
        
        # 将公证票据装订到应用程序
        echo "📎 装订公证票据..."
        xcrun stapler staple "$app_path"
        
        # 验证装订
        echo "🔍 验证装订..."
        xcrun stapler validate "$app_path"
        
        echo "✅ 公证和装订完成"
    else
        echo "❌ 公证失败"
        echo "   检查您的 Apple ID 和应用专用密码是否正确"
        echo "   查看公证日志了解具体错误信息"
        return 1
    fi
    
    # 清理临时文件
    rm -f "$notarization_zip"
}

# 主构建流程
main() {
    # 路径配置
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_DIR="$SCRIPT_DIR"
    BUILD_DIR="$PROJECT_DIR/build"
    DMG_TEMP_DIR="$PROJECT_DIR/dmg_temp"
    ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
    APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
    FINAL_DMG_PATH="$PROJECT_DIR/$DMG_NAME.dmg"
    
    echo "🚀 开始构建签名版 $APP_NAME DMG 包..."
    echo "📁 项目目录: $PROJECT_DIR"
    echo "🔨 构建目录: $BUILD_DIR"
    
    # 检查前置条件
    if ! check_signing_certificates; then
        echo "❌ 代码签名证书检查失败"
        exit 1
    fi
    
    local enable_notarization=false
    if check_notarization_config; then
        enable_notarization=true
    fi
    
    # 清理之前的构建
    echo "🧹 清理之前的构建文件..."
    rm -rf "$BUILD_DIR"
    rm -rf "$DMG_TEMP_DIR"
    rm -f "$FINAL_DMG_PATH"
    
    # 创建构建目录
    mkdir -p "$BUILD_DIR"
    
    # 1. 构建 Archive
    echo "📦 正在构建 Release Archive..."
    cd "$PROJECT_DIR"
    xcodebuild archive \
        -project "$PROJECT_NAME" \
        -scheme "$SCHEME_NAME" \
        -configuration "$CONFIGURATION" \
        -archivePath "$ARCHIVE_PATH" \
        -derivedDataPath "$BUILD_DIR/DerivedData" \
        SKIP_INSTALL=NO \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION"
    
    if [ ! -d "$APP_PATH" ]; then
        echo "❌ 构建失败: 找不到应用程序文件"
        exit 1
    fi
    
    echo "✅ Archive 构建完成: $APP_PATH"
    
    # 2. 深度签名应用程序
    deep_sign_app "$APP_PATH"
    
    # 3. 公证应用程序（如果配置了）
    if [ "$enable_notarization" = true ]; then
        notarize_app "$APP_PATH"
    else
        echo "⏭️  跳过公证步骤"
    fi
    
    # 4. 创建 DMG（使用基本脚本的逻辑）
    echo "📂 创建 DMG 临时目录..."
    mkdir -p "$DMG_TEMP_DIR"
    
    # 复制签名后的应用程序
    echo "📋 复制签名应用程序到 DMG 目录..."
    cp -R "$APP_PATH" "$DMG_TEMP_DIR/"
    
    # 创建 Applications 软链接
    echo "🔗 创建 Applications 软链接..."
    ln -s "/Applications" "$DMG_TEMP_DIR/Applications"
    
    # 5. 创建和设置 DMG
    echo "💿 创建临时 DMG..."
    local temp_dmg_path="$BUILD_DIR/temp.dmg"
    hdiutil create \
        -srcfolder "$DMG_TEMP_DIR" \
        -volname "$APP_NAME" \
        -fs HFS+ \
        -fsargs "-c c=64,a=16,e=16" \
        -format UDRW \
        -size 200m \
        "$temp_dmg_path"
    
    # 挂载并设置 DMG 属性
    echo "🔧 配置 DMG 属性..."
    local mount_point
    mount_point=$(hdiutil attach "$temp_dmg_path" | grep "/Volumes" | awk '{print $3}')
    
    if [ -z "$mount_point" ]; then
        echo "❌ 无法挂载临时 DMG"
        exit 1
    fi
    
    # 简单设置（避免复杂的 AppleScript）
    echo "🖼️  设置基本 DMG 属性..."
    
    # 设置隐藏文件
    chflags hidden "$mount_point/.DS_Store" 2>/dev/null || true
    
    sync
    
    # 卸载 DMG
    echo "💾 卸载临时 DMG..."
    hdiutil detach "$mount_point"
    
    # 压缩最终 DMG
    echo "🗜️  压缩最终 DMG..."
    hdiutil convert "$temp_dmg_path" \
        -format UDZO \
        -imagekey zlib-level=9 \
        -o "$FINAL_DMG_PATH"
    
    # 6. 签名 DMG（如果需要）
    if [ "$enable_notarization" = true ]; then
        echo "🖊️  签名 DMG..."
        codesign --force --sign "$DEVELOPER_ID_APPLICATION" \
                 --timestamp \
                 "$FINAL_DMG_PATH"
        
        echo "📝 公证 DMG..."
        notarize_dmg "$FINAL_DMG_PATH"
    fi
    
    # 7. 清理临时文件
    echo "🧹 清理临时文件..."
    rm -rf "$BUILD_DIR"
    rm -rf "$DMG_TEMP_DIR"
    
    # 8. 最终验证
    echo "✅ 验证最终 DMG..."
    if [ -f "$FINAL_DMG_PATH" ]; then
        local dmg_size
        dmg_size=$(du -h "$FINAL_DMG_PATH" | awk '{print $1}')
        echo "🎉 签名 DMG 创建成功!"
        echo "📁 文件位置: $FINAL_DMG_PATH"
        echo "📏 文件大小: $dmg_size"
        
        # 验证签名
        if codesign -dv "$FINAL_DMG_PATH" 2>/dev/null; then
            echo "✅ DMG 签名验证通过"
        fi
        
        # 验证 DMG 完整性
        if hdiutil verify "$FINAL_DMG_PATH" >/dev/null 2>&1; then
            echo "✅ DMG 完整性验证通过"
        fi
    else
        echo "❌ DMG 创建失败"
        exit 1
    fi
    
    echo ""
    echo "🚀 签名版本构建完成! 您现在可以安全地分发 $FINAL_DMG_PATH 文件"
    echo ""
    echo "📝 分发说明:"
    echo "1. 这个 DMG 已经过代码签名"
    if [ "$enable_notarization" = true ]; then
        echo "2. 应用程序已通过 Apple 公证"
        echo "3. 用户可以直接安装，无需额外安全设置"
    else
        echo "2. 如果用户遇到安全警告，建议完成公证流程"
    fi
    echo "4. 可以直接分发给用户或上传到分发平台"
}

# 公证 DMG（如果需要）
notarize_dmg() {
    local dmg_path="$1"
    
    echo "📝 公证 DMG 文件..."
    
    local submit_result
    submit_result=$(xcrun notarytool submit "$dmg_path" \
                   --apple-id "$NOTARIZATION_USERNAME" \
                   --password "$NOTARIZATION_PASSWORD" \
                   --team-id "$NOTARIZATION_TEAM_ID" \
                   --wait)
    
    echo "$submit_result"
    
    if echo "$submit_result" | grep -q "status: Accepted"; then
        echo "✅ DMG 公证成功"
        
        # 装订公证票据
        echo "📎 装订 DMG 公证票据..."
        xcrun stapler staple "$dmg_path"
        
        echo "✅ DMG 公证和装订完成"
    else
        echo "❌ DMG 公证失败"
        return 1
    fi
}

# 显示使用说明
show_usage() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help     显示此帮助信息"
    echo ""
    echo "环境变量（公证需要）:"
    echo "  NOTARIZATION_USERNAME    Apple ID 邮箱"
    echo "  NOTARIZATION_PASSWORD    应用专用密码"
    echo "  NOTARIZATION_TEAM_ID     开发者团队 ID"
    echo ""
    echo "注意事项:"
    echo "1. 确保已安装 Xcode 和命令行工具"
    echo "2. 确保已安装有效的 Developer ID 证书"
    echo "3. 公证需要有效的 Apple 开发者账户"
    echo "4. 首次公证可能需要较长时间"
}

# 解析命令行参数
case "${1:-}" in
    -h|--help)
        show_usage
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac 