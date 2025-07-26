#!/bin/bash

# InstaGo DMG 打包脚本
# 版本: 1.0
# 用途: 自动构建 Release 版本并打包成 DMG

set -e  # 遇到错误立即退出

# 配置变量
APP_NAME="InstaGo"
PROJECT_NAME="InstaGo.xcodeproj"
SCHEME_NAME="InstaGo"
CONFIGURATION="Release"
DMG_NAME="InstaGo-v1.0"
BACKGROUND_IMAGE_NAME="background.png"

# 路径配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
BUILD_DIR="$PROJECT_DIR/build"
DMG_TEMP_DIR="$PROJECT_DIR/dmg_temp"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
FINAL_DMG_PATH="$PROJECT_DIR/$DMG_NAME.dmg"

echo "🚀 开始构建 $APP_NAME DMG 包..."
echo "📁 项目目录: $PROJECT_DIR"
echo "🔨 构建目录: $BUILD_DIR"

# 清理之前的构建
echo "🧹 清理之前的构建文件..."
rm -rf "$BUILD_DIR"
rm -rf "$DMG_TEMP_DIR"
rm -f "$FINAL_DMG_PATH"

# 创建构建目录
mkdir -p "$BUILD_DIR"

# 1. 构建 Archive
echo "📦 正在构建 Archive..."
cd "$PROJECT_DIR"
xcodebuild archive \
    -project "$PROJECT_NAME" \
    -scheme "$SCHEME_NAME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES

if [ ! -d "$APP_PATH" ]; then
    echo "❌ 构建失败: 找不到应用程序文件"
    exit 1
fi

echo "✅ Archive 构建完成: $APP_PATH"

# 2. 验证应用程序
echo "🔍 验证应用程序..."
if [ ! -f "$APP_PATH/Contents/MacOS/$APP_NAME" ]; then
    echo "❌ 应用程序可执行文件缺失"
    exit 1
fi

# 检查代码签名状态
echo "🔐 检查代码签名..."
codesign -dv "$APP_PATH" 2>&1 || echo "⚠️  警告: 应用程序未签名或签名验证失败"

# 3. 创建 DMG 临时目录结构
echo "📂 创建 DMG 临时目录..."
mkdir -p "$DMG_TEMP_DIR"

# 复制应用程序到临时目录
echo "📋 复制应用程序到 DMG 目录..."
cp -R "$APP_PATH" "$DMG_TEMP_DIR/"

# 创建 Applications 软链接
echo "🔗 创建 Applications 软链接..."
ln -s "/Applications" "$DMG_TEMP_DIR/Applications"

# 4. 创建 DMG 背景图片（如果不存在）
BACKGROUND_PATH="$DMG_TEMP_DIR/.background/$BACKGROUND_IMAGE_NAME"
mkdir -p "$DMG_TEMP_DIR/.background"

if [ ! -f "$BACKGROUND_PATH" ]; then
    echo "🎨 创建 DMG 背景图片..."
    # 创建一个简单的背景图片（512x320）
    cat > "$PROJECT_DIR/create_background.py" << 'EOF'
from PIL import Image, ImageDraw, ImageFont
import sys
import os

# 创建背景图片
width, height = 512, 320
image = Image.new('RGB', (width, height), color='#f0f0f0')
draw = ImageDraw.Draw(image)

# 绘制渐变背景
for y in range(height):
    alpha = y / height
    color = tuple(int(240 - alpha * 40) for _ in range(3))
    draw.line([(0, y), (width, y)], fill=color)

# 添加文字说明
try:
    font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 24)
except:
    font = ImageFont.load_default()

text = "将 InstaGo 拖拽到 Applications 文件夹"
text_width = draw.textlength(text, font=font)
text_x = (width - text_width) // 2
text_y = height - 50

draw.text((text_x, text_y), text, fill='#333333', font=font)

# 保存图片
output_path = sys.argv[1] if len(sys.argv) > 1 else 'background.png'
image.save(output_path)
print(f"✅ 背景图片已创建: {output_path}")
EOF

    # 检查是否安装了 Python 和 PIL
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "from PIL import Image; print('PIL available')" >/dev/null 2>&1 && \
        python3 "$PROJECT_DIR/create_background.py" "$BACKGROUND_PATH" || \
        echo "⚠️  无法创建背景图片，将跳过"
    else
        echo "⚠️  未安装 Python3，跳过背景图片创建"
    fi
    
    # 清理临时脚本
    rm -f "$PROJECT_DIR/create_background.py"
fi

# 5. 创建临时 DMG
echo "💿 创建临时 DMG..."
TEMP_DMG_PATH="$BUILD_DIR/temp.dmg"
hdiutil create \
    -srcfolder "$DMG_TEMP_DIR" \
    -volname "$APP_NAME" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -format UDRW \
    -size 200m \
    "$TEMP_DMG_PATH"

# 6. 挂载临时 DMG 并设置属性
echo "🔧 配置 DMG 属性..."
MOUNT_POINT=$(hdiutil attach "$TEMP_DMG_PATH" | grep "/Volumes" | awk '{print $3}')

if [ -z "$MOUNT_POINT" ]; then
    echo "❌ 无法挂载临时 DMG"
    exit 1
fi

echo "📎 DMG 已挂载到: $MOUNT_POINT"

# 设置 Finder 窗口属性
echo "🖼️  设置 Finder 窗口属性..."
cat > "$BUILD_DIR/set_dmg_properties.applescript" << EOF
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 100, 912, 420}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 72
        set background picture of viewOptions to file ".background:$BACKGROUND_IMAGE_NAME"
        
        -- 设置图标位置
        set position of item "$APP_NAME.app" of container window to {140, 120}
        set position of item "Applications" of container window to {372, 120}
        
        update without registering applications
        delay 2
        close
    end tell
end tell
EOF

# 执行 AppleScript 设置
osascript "$BUILD_DIR/set_dmg_properties.applescript" || echo "⚠️  AppleScript 执行失败，DMG 布局可能不完美"

# 确保更改已同步
sync

# 7. 卸载并压缩 DMG
echo "💾 卸载临时 DMG..."
hdiutil detach "$MOUNT_POINT"

echo "🗜️  压缩最终 DMG..."
hdiutil convert "$TEMP_DMG_PATH" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$FINAL_DMG_PATH"

# 8. 清理临时文件
echo "🧹 清理临时文件..."
rm -rf "$BUILD_DIR"
rm -rf "$DMG_TEMP_DIR"

# 9. 验证最终 DMG
echo "✅ 验证最终 DMG..."
if [ -f "$FINAL_DMG_PATH" ]; then
    DMG_SIZE=$(du -h "$FINAL_DMG_PATH" | awk '{print $1}')
    echo "🎉 DMG 创建成功!"
    echo "📁 文件位置: $FINAL_DMG_PATH"
    echo "📏 文件大小: $DMG_SIZE"
    
    # 验证 DMG 可以正常挂载
    echo "🔍 验证 DMG 完整性..."
    if hdiutil verify "$FINAL_DMG_PATH" >/dev/null 2>&1; then
        echo "✅ DMG 验证通过"
    else
        echo "⚠️  DMG 验证警告，请手动测试"
    fi
else
    echo "❌ DMG 创建失败"
    exit 1
fi

echo ""
echo "🚀 构建完成! 您现在可以分发 $FINAL_DMG_PATH 文件"
echo ""
echo "📝 下一步:"
echo "1. 测试 DMG 文件是否正常工作"
echo "2. 如需分发给其他用户，建议进行代码签名和公证"
echo "3. 可以上传到 GitHub Releases 或其他分发平台" 