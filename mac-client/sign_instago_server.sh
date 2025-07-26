#!/bin/bash

# InstaGo Server 代码签名脚本
# 专门处理 instago-server 的签名和 Hardened Runtime 设置

set -e

# 配置变量
APP_NAME="InstaGo"
SERVER_BINARY="instago-server"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_PATH="$PROJECT_DIR/InstaGo/$SERVER_BINARY"

# 默认开发者证书配置（需要根据实际情况修改）
DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-Developer ID Application: Your Name (TEAM_ID)}"

echo "🔐 InstaGo Server 代码签名工具"
echo "================================"
echo ""

# 检查服务器二进制文件是否存在
check_server_binary() {
    if [ ! -f "$SERVER_PATH" ]; then
        echo "❌ 找不到服务器二进制文件: $SERVER_PATH"
        echo "请先运行 ../go-client/build.sh 构建服务器"
        exit 1
    fi
    
    echo "✅ 找到服务器二进制文件: $SERVER_PATH"
    
    # 显示文件信息
    local file_size=$(du -h "$SERVER_PATH" | awk '{print $1}')
    echo "📏 文件大小: $file_size"
}

# 检查可用的代码签名证书
check_signing_certificates() {
    echo ""
    echo "🔍 检查可用的代码签名证书..."
    
    local cert_count=$(security find-identity -v -p codesigning | grep "Developer ID Application" | wc -l | tr -d ' ')
    
    if [ "$cert_count" -eq 0 ]; then
        echo "❌ 未找到 Developer ID Application 证书"
        echo ""
        echo "📋 解决方案："
        echo "1. 在 Xcode 中登录您的 Apple 开发者账户"
        echo "2. 前往 Xcode → Preferences → Accounts → Manage Certificates"
        echo "3. 点击 '+' 添加 'Developer ID Application' 证书"
        echo "4. 或从 Apple Developer 网站下载证书并双击安装"
        echo ""
        echo "🔧 您也可以设置环境变量指定证书："
        echo "export DEVELOPER_ID_APPLICATION=\"Developer ID Application: Your Name (TEAM_ID)\""
        echo ""
        return 1
    fi
    
    echo "✅ 找到 $cert_count 个开发者证书："
    security find-identity -v -p codesigning | grep "Developer ID Application"
    
    # 如果有多个证书，使用第一个
    if [ "$cert_count" -gt 1 ]; then
        DEVELOPER_ID_APPLICATION=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/')
        echo "🎯 将使用证书: $DEVELOPER_ID_APPLICATION"
    fi
    
    return 0
}

# 检查当前签名状态
check_current_signature() {
    echo ""
    echo "🔍 检查当前签名状态..."
    
    local codesign_output
    codesign_output=$(codesign --display --verbose=4 "$SERVER_PATH" 2>&1)
    
    echo "📊 当前签名信息："
    echo "$codesign_output"
    echo ""
    
    # 检查是否有 Runtime Version
    if echo "$codesign_output" | grep -q "Runtime Version"; then
        local runtime_version=$(echo "$codesign_output" | grep "Runtime Version" | awk '{print $3}')
        echo "✅ 已启用 Hardened Runtime (版本: $runtime_version)"
        return 0
    else
        echo "❌ 未启用 Hardened Runtime"
        return 1
    fi
}

# 备份当前二进制文件
backup_binary() {
    local backup_path="${SERVER_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
    echo "💾 备份当前二进制文件到: $(basename "$backup_path")"
    cp "$SERVER_PATH" "$backup_path"
    echo "✅ 备份完成"
}

# 签名服务器二进制文件
sign_server_binary() {
    echo ""
    echo "🖊️ 开始签名服务器二进制文件..."
    echo "📝 使用证书: $DEVELOPER_ID_APPLICATION"
    echo "🔒 启用 Hardened Runtime"
    
    # 执行签名
    codesign \
        --force \
        --verify \
        --verbose \
        --sign "$DEVELOPER_ID_APPLICATION" \
        --options runtime \
        --timestamp \
        "$SERVER_PATH"
    
    echo "✅ 签名完成"
}

# 验证签名结果
verify_signature() {
    echo ""
    echo "🔍 验证签名结果..."
    
    # 验证签名
    if ! codesign --verify --verbose=2 "$SERVER_PATH"; then
        echo "❌ 签名验证失败"
        return 1
    fi
    
    echo "✅ 签名验证通过"
    
    # 检查 Hardened Runtime
    local codesign_output
    codesign_output=$(codesign --display --verbose=4 "$SERVER_PATH" 2>&1)
    
    if echo "$codesign_output" | grep -q "Runtime Version"; then
        local runtime_version=$(echo "$codesign_output" | grep "Runtime Version" | awk '{print $3}')
        echo "✅ Hardened Runtime 已启用 (版本: $runtime_version)"
    else
        echo "❌ Hardened Runtime 未正确设置"
        return 1
    fi
    
    # 显示完整的签名信息
    echo ""
    echo "📋 完整签名信息："
    codesign --display --verbose=4 "$SERVER_PATH"
    
    return 0
}

# 主函数
main() {
    echo "开始处理: $SERVER_PATH"
    echo ""
    
    # 1. 检查服务器二进制文件
    check_server_binary
    
    # 2. 检查当前签名状态
    local needs_signing=true
    if check_current_signature; then
        echo ""
        read -p "🤔 文件已有 Hardened Runtime 签名，是否重新签名？ (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "⏭️ 跳过签名"
            exit 0
        fi
    fi
    
    # 3. 检查代码签名证书
    if ! check_signing_certificates; then
        echo ""
        echo "⚠️ 无法继续：缺少代码签名证书"
        echo "请安装有效的 Developer ID Application 证书后重试"
        exit 1
    fi
    
    # 4. 备份现有文件
    backup_binary
    
    # 5. 执行签名
    if ! sign_server_binary; then
        echo "❌ 签名失败"
        exit 1
    fi
    
    # 6. 验证签名结果
    if ! verify_signature; then
        echo "❌ 签名验证失败"
        exit 1
    fi
    
    echo ""
    echo "🎉 instago-server 签名完成！"
    echo "✅ Hardened Runtime 已启用"
    echo "📝 现在可以继续打包应用程序"
    echo ""
    echo "🔄 下一步建议："
    echo "1. 运行 ./build_signed_dmg.sh 创建完整的签名 DMG"
    echo "2. 或在 Xcode 中 Archive 并导出应用程序"
}

# 显示帮助信息
show_help() {
    echo "InstaGo Server 代码签名工具"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项："
    echo "  -h, --help          显示此帮助信息"
    echo "  -c, --check-only    仅检查当前签名状态，不执行签名"
    echo ""
    echo "环境变量："
    echo "  DEVELOPER_ID_APPLICATION    指定要使用的开发者证书"
    echo ""
    echo "示例："
    echo "  $0                                    # 交互式签名"
    echo "  $0 --check-only                      # 仅检查签名状态"
    echo "  DEVELOPER_ID_APPLICATION=\"Your Cert\" $0  # 使用指定证书"
}

# 仅检查模式
check_only() {
    echo "🔍 检查模式：仅显示当前状态"
    echo ""
    
    check_server_binary
    check_current_signature
    
    echo ""
    if check_signing_certificates; then
        echo "💡 系统已准备就绪，可以执行签名"
    else
        echo "⚠️ 需要安装开发者证书才能进行签名"
    fi
}

# 解析命令行参数
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    -c|--check-only)
        check_only
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac 