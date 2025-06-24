#!/bin/sh

# =============================================================================
# 梅林路由器IP监控系统一键安装脚本
# 版本: v2.1 - 在线安装优化版
# =============================================================================

set -e  # 遇到错误立即退出

# 配置下载源
readonly BASE_URL="https://raw.githubusercontent.com/your-username/router-ip-monitor/main"
readonly INSTALL_DIR="/jffs/addons"
readonly PUSHER_SCRIPT="$INSTALL_DIR/Notice_Pusher.sh"
readonly MONITOR_SCRIPT="$INSTALL_DIR/PublicIP_Monitor.sh"
readonly CONFIG_FILE="$INSTALL_DIR/Notice_Pusher.conf"

echo "========================================"
echo "  梅林路由器IP监控系统安装程序 v2.1"
echo "========================================"

# 检查系统环境
echo "正在检查系统环境..."

if [ ! -d "/jffs" ]; then
    echo "❌ 错误: 未找到/jffs目录，请确保JFFS分区已启用"
    exit 1
fi

if ! which curl >/dev/null 2>&1 && ! which wget >/dev/null 2>&1; then
    echo "❌ 错误: 系统缺少curl或wget工具"
    exit 1
fi

# 选择下载工具
if which curl >/dev/null 2>&1; then
    DOWNLOAD_CMD="curl -fsSL"
    echo "✅ 使用curl下载文件"
elif which wget >/dev/null 2>&1; then
    DOWNLOAD_CMD="wget -qO-"
    echo "✅ 使用wget下载文件"
fi

# 创建安装目录
echo "正在创建安装目录..."
mkdir -p "$INSTALL_DIR"

# 备份现有文件
backup_if_exists() {
    local file="\$1"
    if [ -f "$file" ]; then
        local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
        echo "📦 备份现有文件: $(basename "$file") -> $(basename "$backup")"
        cp "$file" "$backup"
    fi
}

backup_if_exists "$PUSHER_SCRIPT"
backup_if_exists "$MONITOR_SCRIPT"
backup_if_exists "$CONFIG_FILE"

# 下载文件函数
download_file() {
    local url="\$1"
    local dest="\$2"
    local name="\$3"
    
    echo "📥 正在下载 $name..."
    if $DOWNLOAD_CMD "$url" > "$dest.tmp"; then
        mv "$dest.tmp" "$dest"
        echo "✅ $name 下载成功"
        return 0
    else
        echo "❌ $name 下载失败"
        rm -f "$dest.tmp"
        return 1
    fi
}

# 下载核心文件
echo ""
echo "正在下载核心文件..."

download_file "$BASE_URL/Notice_Pusher.sh" "$PUSHER_SCRIPT" "推送模块" || {
    echo "❌ 推送模块下载失败，安装中止"
    exit 1
}

download_file "$BASE_URL/PublicIP_Monitor.sh" "$MONITOR_SCRIPT" "IP监控脚本" || {
    echo "❌ IP监控脚本下载失败，安装中止"
    exit 1
}

# 下载配置文件（如果不存在）
if [ ! -f "$CONFIG_FILE" ]; then
    download_file "$BASE_URL/Notice_Pusher.conf" "$CONFIG_FILE" "配置文件" || {
        echo "❌ 配置文件下载失败，安装中止"
        exit 1
    }
else
    echo "⏭️  配置文件已存在，跳过下载"
fi

# 设置执行权限
echo ""
echo "正在设置文件权限..."
chmod +x "$PUSHER_SCRIPT" && echo "✅ 推送模块权限设置完成"
chmod +x "$MONITOR_SCRIPT" && echo "✅ 监控脚本权限设置完成"
chmod 644 "$CONFIG_FILE" && echo "✅ 配置文件权限设置完成"

# 验证安装
echo ""
echo "正在验证安装..."
if [ -x "$PUSHER_SCRIPT" ] && [ -x "$MONITOR_SCRIPT" ] && [ -f "$CONFIG_FILE" ]; then
    echo "✅ 所有文件安装成功！"
else
    echo "❌ 安装验证失败"
    exit 1
fi

echo ""
echo "========================================"
echo "  🎉 安装完成！"
echo "========================================"
echo ""
echo "📁 安装路径:"
echo "   推送模块: $PUSHER_SCRIPT"
echo "   监控脚本: $MONITOR_SCRIPT"
echo "   配置文件: $CONFIG_FILE"
echo ""
echo "🔧 下一步操作:"
echo "   1. 编辑配置文件:"
echo "      vi $CONFIG_FILE"
echo ""
echo "   2. 启用推送方式（设置为true）:"
echo "      ENABLE_DINGTALK=\"true\"      # 钉钉"
echo "      ENABLE_WECHAT=\"true\"        # 企业微信"
echo "      ENABLE_TELEGRAM=\"true\"      # Telegram"
echo "      ENABLE_IYUU=\"true\"          # IYUU"
echo "      ENABLE_SERVERCHAN=\"true\"    # Server酱"
echo ""
echo "   3. 填入对应的Token/密钥"
echo ""
echo "   4. 测试推送功能:"
echo "      $PUSHER_SCRIPT \"测试\" \"这是测试消息\""
echo ""
echo "   5. 测试IP监控:"
echo "      $MONITOR_SCRIPT"
echo ""
echo "   6. 添加定时任务:"
echo "      crontab -e"
echo "      # 每5分钟检查一次"
echo "      */5 * * * * $MONITOR_SCRIPT >/dev/null 2>&1"
echo ""
echo "📖 项目地址: https://github.com/your-username/router-ip-monitor"
echo "🐛 问题反馈: https://github.com/your-username/router-ip-monitor/issues"
echo "========================================"
