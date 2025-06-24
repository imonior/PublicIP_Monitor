#!/bin/sh

# =============================================================================
# 梅林路由器智能IP监控脚本 - 在线安装优化版
# 功能: 监控公网IP变化，智能推送通知
# 版本: v2.1
# =============================================================================

# 配置常量
readonly IP_CACHE_FILE="/tmp/last_public_ip.txt"
readonly PUSH_SCRIPT="/jffs/addons/Notice_Pusher.sh"
readonly LOG_FILE="/tmp/syslog.log"
readonly SCRIPT_NAME="PublicIP_Monitor"

# IP查询服务列表（按可靠性排序）
readonly IP_SERVICES="
https://ifconfig.me/ip
https://api.ipify.org
https://checkip.amazonaws.com
https://icanhazip.com
https://myip.ipip.net
https://ipinfo.io/ip
"

# 日志函数
log_msg() {
    local level="\$1"
    local message="\$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] $SCRIPT_NAME [$level]: $message"
    echo "[$timestamp] $SCRIPT_NAME [$level]: $message" >> "$LOG_FILE" 2>/dev/null
}

# 检查命令是否存在
check_cmd() {
    which "\$1" >/dev/null 2>&1
}

# 检查推送模块
check_push_module() {
    if [ ! -f "$PUSH_SCRIPT" ]; then
        log_msg "ERROR" "推送模块不存在: $PUSH_SCRIPT"
        return 1
    fi
    
    if [ ! -x "$PUSH_SCRIPT" ]; then
        log_msg "INFO" "为推送模块添加执行权限..."
        chmod +x "$PUSH_SCRIPT" 2>/dev/null
        if [ $? -ne 0 ]; then
            log_msg "ERROR" "无法添加执行权限: $PUSH_SCRIPT"
            return 1
        fi
    fi
    
    return 0
}

# 调用推送模块
call_push_notify() {
    local title="\$1"
    local desc="\$2"
    
    log_msg "INFO" "调用推送模块发送通知..."
    "$PUSH_SCRIPT" "$title" "$desc"
    local result=$?
    
    if [ $result -eq 0 ]; then
        log_msg "INFO" "通知推送成功"
    else
        log_msg "WARN" "通知推送失败 (退出码: $result)"
    fi
    
    return $result
}

# IP格式验证
validate_ip() {
    local ip="\$1"
    
    # 基本格式检查
    echo "$ip" | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' >/dev/null 2>&1 || return 1
    
    # 检查每个段的范围 (0-255)
    local IFS='.'
    set -- $ip
    for segment in "$@"; do
        [ "$segment" -ge 0 ] && [ "$segment" -le 255 ] 2>/dev/null || return 1
    done
    
    return 0
}

# 获取公网IP（增强容错）
get_public_ip() {
    local ip=""
    local service
    local attempt=0
    local max_attempts=2
    
    # 检查网络工具可用性
    if ! check_cmd curl && ! check_cmd wget; then
        log_msg "ERROR" "系统缺少curl或wget工具"
        return 1
    fi
    
    # 遍历IP服务
    for service in $IP_SERVICES; do
        attempt=0
        while [ $attempt -lt $max_attempts ]; do
            attempt=$((attempt + 1))
            log_msg "INFO" "尝试从 $service 获取IP (第${attempt}次)..."
            
            # 优先使用curl
            if check_cmd curl; then
                ip=$(curl -s --connect-timeout 8 --max-time 15 "$service" 2>/dev/null | tr -d '\r\n\t ')
            elif check_cmd wget; then
                ip=$(wget -qO- -T 15 "$service" 2>/dev/null | tr -d '\r\n\t ')
            fi
            
            # 验证获取的IP
            if [ $? -eq 0 ] && [ -n "$ip" ] && validate_ip "$ip"; then
                log_msg "INFO" "成功获取公网IP: $ip"
                echo "$ip"
                return 0
            else
                log_msg "WARN" "从 $service 获取的内容无效: '$ip'"
                ip=""
                sleep 2  # 短暂延迟后重试
            fi
        done
    done
    
    log_msg "ERROR" "所有IP查询服务均失败"
    return 1
}

# 读取缓存的IP
get_cached_ip() {
    if [ -f "$IP_CACHE_FILE" ]; then
        local cached_ip=$(cat "$IP_CACHE_FILE" 2>/dev/null | tr -d '\r\n\t ')
        if validate_ip "$cached_ip"; then
            echo "$cached_ip"
        else
            log_msg "WARN" "缓存文件中的IP格式无效，将重新获取"
            rm -f "$IP_CACHE_FILE" 2>/dev/null
            echo ""
        fi
    else
        echo ""
    fi
}

# 保存IP到缓存
save_ip_cache() {
    local ip="\$1"
    echo "$ip" > "$IP_CACHE_FILE" 2>/dev/null
    if [ $? -eq 0 ]; then
        log_msg "INFO" "IP已保存到缓存: $ip"
    else
        log_msg "WARN" "无法保存IP到缓存文件"
    fi
}

# 获取路由器信息
get_router_info() {
    local model=""
    local firmware=""
    local uptime=""
    local info=""
    
    # 获取路由器型号
    if [ -f "/proc/version" ]; then
        model=$(cat /proc/version 2>/dev/null | grep -o "ASUS[^[:space:]]*" | head -1)
    fi
    
    if [ -z "$model" ] && [ -f "/tmp/sysinfo/model" ]; then
        model=$(cat /tmp/sysinfo/model 2>/dev/null)
    fi
    
    # 获取固件版本
    if [ -f "/rom/etc/version" ]; then
        firmware=$(cat /rom/etc/version 2>/dev/null)
    fi
    
    # 获取运行时间
    if [ -f "/proc/uptime" ]; then
        local uptime_sec=$(cat /proc/uptime 2>/dev/null | cut -d' ' -f1 | cut -d'.' -f1)
        if [ -n "$uptime_sec" ] && [ "$uptime_sec" -gt 0 ] 2>/dev/null; then
            local days=$((uptime_sec / 86400))
            local hours=$(((uptime_sec % 86400) / 3600))
            uptime="${days}天${hours}小时"
        fi
    fi
    
    # 构建信息字符串
    [ -n "$model" ] && info="${info}📱 路由器: $model\n"
    [ -n "$firmware" ] && info="${info}💿 固件: $firmware\n"
    [ -n "$uptime" ] && info="${info}⏱️ 运行: $uptime"
    
    echo "$info"
}

# 主函数
main() {
    log_msg "INFO" "========== IP监控脚本开始执行 =========="
    
    # 检查推送模块
    if ! check_push_module; then
        log_msg "ERROR" "推送模块检查失败，脚本退出"
        exit 1
    fi
    
    # 获取当前IP
    log_msg "INFO" "开始获取当前公网IP..."
    current_ip=$(get_public_ip)
    if [ $? -ne 0 ] || [ -z "$current_ip" ]; then
        log_msg "ERROR" "无法获取当前公网IP"
        
        # 发送获取IP失败通知
        router_info=$(get_router_info)
        call_push_notify "🚨 路由器IP监控异常" "无法获取路由器当前公网IP地址，请检查网络连接。

⏰ 检测时间: $(date '+%Y-%m-%d %H:%M:%S')
$router_info

🔧 建议检查:
• 网络连接是否正常
• DNS设置是否正确
• 防火墙是否阻止访问"
        exit 1
    fi
    
    # 获取缓存IP
    cached_ip=$(get_cached_ip)
    
    log_msg "INFO" "当前IP: $current_ip"
    if [ -n "$cached_ip" ]; then
        log_msg "INFO" "缓存IP: $cached_ip"
    else
        log_msg "INFO" "缓存IP: (无记录)"
    fi
    
    # 比较IP变化
    if [ "$current_ip" = "$cached_ip" ]; then
        log_msg "INFO" "IP地址未发生变化，无需通知"
        log_msg "INFO" "========== 脚本执行完成 =========="
        exit 0
    fi
    
    # IP发生变化，准备通知
    log_msg "INFO" "检测到IP地址变化，准备发送通知"
    router_info=$(get_router_info)
    
    if [ -z "$cached_ip" ]; then
        # 首次运行
        title="🟢 路由器IP监控服务启动"
        desc="路由器IP监控服务已成功启动并开始工作。

🌐 当前外网IP: $current_ip
⏰ 启动时间: $(date '+%Y-%m-%d %H:%M:%S')
$router_info

📝 说明: 后续仅在IP地址发生变化时发送通知。"
    else
        # IP变化
        title="🔄 路由器IP地址变更通知"
        desc="检测到路由器外网IP地址发生变化：

🔴 旧IP地址: $cached_ip
🟢 新IP地址: $current_ip
⏰ 变更时间: $(date '+%Y-%m-%d %H:%M:%S')
$router_info

💡 提醒事项:
• 请及时更新DDNS记录
• 检查端口转发规则
• 更新远程访问配置"
    fi
    
    # 发送通知
    if call_push_notify "$title" "$desc"; then
        # 通知成功，保存新IP
        save_ip_cache "$current_ip"
        log_msg "INFO" "IP变化通知发送成功"
    else
        log_msg "ERROR" "IP变化通知发送失败"
        exit 1
    fi
    
    log_msg "INFO" "========== 脚本执行完成 =========="
}

# 脚本入口
main "$@"
