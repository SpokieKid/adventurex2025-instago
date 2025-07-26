#!/bin/bash

# InstaGo 登录流程测试脚本
# 模拟用户的测试流程：登录状态 -> 登出 -> 前端回调 -> 验证实例数

echo "🧪 InstaGo 登录流程测试"
echo "========================================="

# 函数：检查InstaGo实例数
check_instances() {
    local description="$1"
    echo ""
    echo "📊 $description"
    echo "   检查运行的InstaGo实例..."
    
    # 检查进程数
    local instances=$(ps aux | grep -v grep | grep -c InstaGo)
    echo "   当前实例数: $instances"
    
    # 显示详细信息
    if [ $instances -gt 0 ]; then
        echo "   实例详情:"
        ps aux | grep -v grep | grep InstaGo | while read line; do
            echo "     $line"
        done
    else
        echo "   没有找到运行的实例"
    fi
    
    return $instances
}

# 函数：等待用户确认
wait_for_user() {
    local message="$1"
    echo ""
    echo "⏸️  $message"
    read -p "   按回车键继续..."
}

# 函数：发送测试回调
send_callback() {
    local token_suffix="$1"
    local test_url="instago://auth?token=test_token_${token_suffix}&user_id=test_${token_suffix}&user_name=TestUser_${token_suffix}&user_email=test${token_suffix}@example.com"
    
    echo ""
    echo "📤 发送测试回调URL:"
    echo "   $test_url"
    
    open "$test_url"
    sleep 2
}

# 开始测试
echo "🚀 开始模拟登录流程测试"

# 第1步：检查初始状态
check_instances "第1步：检查初始状态"
initial_instances=$?

if [ $initial_instances -eq 0 ]; then
    echo "❌ InstaGo没有运行，请先启动应用"
    echo "💡 建议: 从Xcode启动或双击InstaGo.app"
    exit 1
elif [ $initial_instances -gt 1 ]; then
    echo "⚠️  已经有多个实例在运行！"
    wait_for_user "请手动关闭多余的实例，或者重启所有InstaGo实例后重新测试"
fi

# 第2步：模拟用户已登录状态
wait_for_user "第2步：请确保应用处于登录状态（在状态栏中检查）"

# 第3步：模拟用户登出
wait_for_user "第3步：请在状态栏中点击'登出'按钮"

check_instances "登出后状态检查"
post_logout_instances=$?

if [ $post_logout_instances -ne $initial_instances ]; then
    echo "⚠️  登出后实例数发生变化！"
fi

# 第4步：模拟前端回调（使用时间戳避免重复检测）
echo ""
echo "🌐 第4步：模拟前端登录回调"
echo "   这模拟了前端页面自动发送回调的情况"

timestamp=$(date +%s)
send_callback $timestamp

# 等待处理
echo "   等待3秒处理回调..."
sleep 3

# 第5步：检查回调后的状态
check_instances "第5步：回调处理后状态检查"
post_callback_instances=$?

# 分析结果
echo ""
echo "========================================="
echo "📋 测试结果分析"
echo "========================================="

echo "初始实例数: $initial_instances"
echo "登出后实例数: $post_logout_instances"
echo "回调后实例数: $post_callback_instances"

if [ $post_callback_instances -eq 1 ]; then
    echo "✅ 测试通过！始终保持单实例运行"
    echo "🎉 多实例问题已修复"
elif [ $post_callback_instances -gt 1 ]; then
    echo "❌ 测试失败！回调后出现了多个实例"
    echo ""
    echo "🔧 可能的原因："
    echo "   1. Info.plist配置未生效（需要重新构建）"
    echo "   2. 系统Launch Services缓存未更新"
    echo "   3. 前端发送了多个回调请求"
    echo ""
    echo "🛠️  建议的修复步骤："
    echo "   1. 重新构建应用: xcodebuild -scheme InstaGo build"
    echo "   2. 清除系统缓存: /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user"
    echo "   3. 重启macOS"
else
    echo "⚠️  所有实例都已退出，请检查日志"
fi

# 第6步：检查应用登录状态
echo ""
echo "📱 第6步：检查应用登录状态"
wait_for_user "请检查应用是否正确处理了登录回调（查看状态栏中的登录状态）"

# 显示日志查看提示
echo ""
echo "🔍 调试信息"
echo "========================================="
echo "如果测试失败，请查看以下日志："
echo ""
echo "1. 应用日志（Console.app）:"
echo "   - 搜索 'InstaGo' 或 'instago'"
echo "   - 关键词: '🔗 收到URL事件', '📊 当前运行的InstaGo实例数'"
echo ""
echo "2. 系统日志:"
echo "   log show --predicate 'process == \"InstaGo\"' --last 5m"
echo ""
echo "3. Launch Services 注册状态:"
echo "   /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump | grep -i instago"

# 最终清理提示
echo ""
echo "🧹 测试完成提示"
echo "========================================="
echo "如果发现多个实例在运行，可以使用以下命令清理："
echo "   pkill -f InstaGo"
echo ""
echo "然后重新启动应用进行下一轮测试。"

echo ""
echo "🏁 测试完成" 