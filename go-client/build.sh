#!/bin/bash

# InstaGo 服务端构建脚本
# 编译Go服务端为macOS可执行文件

set -e

echo "🏗️ 开始构建InstaGo服务端..."

# 进入Go项目目录
cd "$(dirname "$0")"

# 设置输出目录
OUTPUT_DIR="../mac-client/InstaGo"
OUTPUT_FILE="instago-server"

# 确保输出目录存在
mkdir -p "$OUTPUT_DIR"

# 设置编译环境变量
export CGO_ENABLED=1
export GOOS=darwin

# 检测系统架构
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    export GOARCH=arm64
    echo "📱 编译目标: Apple Silicon (arm64)"
else
    export GOARCH=amd64
    echo "💻 编译目标: Intel (amd64)"
fi

# 编译Go程序
echo "⚙️ 编译Go服务端..."
go build -ldflags "-s -w" -o "$OUTPUT_DIR/$OUTPUT_FILE" .

# 检查编译结果
if [ -f "$OUTPUT_DIR/$OUTPUT_FILE" ]; then
    echo "✅ 编译成功！"
    echo "📁 输出文件: $OUTPUT_DIR/$OUTPUT_FILE"
    
    # 显示文件信息
    ls -lh "$OUTPUT_DIR/$OUTPUT_FILE"
    
    # 设置执行权限
    chmod +x "$OUTPUT_DIR/$OUTPUT_FILE"
    echo "🔐 已设置执行权限"
    
else
    echo "❌ 编译失败！"
    exit 1
fi

echo "🎉 构建完成！服务端可执行文件已准备好打包到Swift应用中。" 