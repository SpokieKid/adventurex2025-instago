#!/bin/bash

# InstaGo URL Scheme 测试脚本
# 用于验证多实例启动问题修复

echo "🧪 InstaGo URL Scheme 测试开始"
echo "=================================="

# 检查应用是否已经在运行
echo "1. 检查当前运行的 InstaGo 实例..."
RUNNING_INSTANCES=$(ps aux | grep -v grep | grep InstaGo | wc -l)
echo "   当前运行的实例数: $RUNNING_INSTANCES"

if [ $RUNNING_INSTANCES -eq 0 ]; then
    echo "   ⚠️  InstaGo 没有运行，请先启动应用"
    echo "   💡 提示: 从 Xcode 启动或双击 InstaGo.app"
    exit 1
elif [ $RUNNING_INSTANCES -gt 1 ]; then
    echo "   ❌ 检测到多个实例！这表明修复可能无效"
    echo "   📝 请检查 Info.plist 配置是否正确"
else
    echo "   ✅ 单实例运行正常"
fi

echo ""
echo "2. 测试 URL Scheme 回调..."

# 测试URL格式
TEST_URL="instago://auth?token=test_token_$(date +%s)&user_id=test123&user_name=TestUser&user_email=test@example.com"

echo "   发送测试URL: $TEST_URL"
echo "   预期行为: 激活现有应用实例，不启动新实例"

# 发送URL
open "$TEST_URL"

# 等待处理
echo "   等待 3 秒处理..."
sleep 3

# 再次检查实例数
echo ""
echo "3. 验证处理结果..."
NEW_RUNNING_INSTANCES=$(ps aux | grep -v grep | grep InstaGo | wc -l)
echo "   处理后的实例数: $NEW_RUNNING_INSTANCES"

if [ $NEW_RUNNING_INSTANCES -eq 1 ]; then
    echo "   ✅ 测试通过！仍然只有一个实例在运行"
    echo "   🎉 多实例问题已修复"
elif [ $NEW_RUNNING_INSTANCES -gt 1 ]; then
    echo "   ❌ 测试失败！启动了多个实例"
    echo "   🔧 建议检查:"
    echo "      - Info.plist 是否正确配置"
    echo "      - 应用是否重新构建"
    echo "      - 系统是否需要重启"
else
    echo "   ⚠️  应用似乎已退出，请检查日志"
fi

echo ""
echo "4. 检查日志输出..."
echo "   💡 你可以在 Console.app 中搜索 'InstaGo' 查看详细日志"
echo "   🔍 关键日志标识:"
echo "      - '🔗 收到URL事件'"
echo "      - '✅ 确认为登录回调'"
echo "      - '🔄 应用重新打开请求'"

echo ""
echo "=================================="
echo "🧪 测试完成"

# 显示当前进程详情
echo ""
echo "当前 InstaGo 进程详情:"
ps aux | grep -v grep | grep InstaGo || echo "   无运行进程"

echo ""
echo "💡 如果测试失败，请参考 MULTIPLE_INSTANCE_FIX.md 进行故障排除" 