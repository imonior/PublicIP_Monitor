#!/bin/sh

# =============================================================================
# 通用消息推送器 - 梅林路由器专用版
# 支持：企业微信、钉钉、IYUU、Telegram
# 版本：v2.1
# =============================================================================

# 配置文件路径
CONF_FILE="/jffs/addons/Notice_Pusher.conf"

# 加载配置
[ -f "$CONF_FILE" ] && . "$CONF_FILE"

# 参数验证
TITLE="\$1"
DESC="\$2"
[ -z "$TITLE" ] || [ -z "$DESC" ] || [ "$TITLE" = "null" ] || [ "$DESC" = "null" ] || [ "$TITLE" = "None" ] && {
    echo "[ERROR] 参数错误: 标题和内容不能为空"
    exit 1
}

# 日志函数
log_msg() {
    echo "[$(date '+%H:%M:%S')] Notice_Pusher: \$1"
}

# 检查命令是否存在（梅林兼容）
check_cmd() {
    which "\$1" >/dev/null 2>&1
}

# URL编码函数（busybox兼容）
urlencode() {
    local input="\$1"
    local output=""
    local length i char hex
    
    length=${#input}
    i=0
    
    while [ $i -lt $length ]; do
        char=$(echo "$input" | cut -c$((i+1)))
        case "$char" in
            [a-zA-Z0-9.~_-]) 
                output="${output}${char}" 
                ;;
            ' ') 
                output="${output}%20" 
                ;;
            *) 
                hex=$(printf '%02X' "'$char" 2>/dev/null)
                if [ $? -eq 0 ]; then
                    output="${output}%${hex}"
                else
                    output="${output}${char}"
                fi
                ;;
        esac
        i=$((i+1))
    done
    
    echo "$output"
}

# HTTP发送函数
send_http() {
    local url="\$1"
    if check_cmd curl; then
        curl -s --connect-timeout 10 --max-time 30 "$url" >/dev/null 2>&1 &
        return $?
    elif check_cmd wget; then
        wget -qO- -T 30 "$url" >/dev/null 2>&1 &
        return $?
    else
        log_msg "错误: 系统缺少curl或wget工具"
        return 1
    fi
}

# JSON POST发送函数
send_json() {
    local url="\$1"
    local json="\$2"
    
    if check_cmd curl; then
        curl -s --connect-timeout 10 --max-time 30 \
             -H "Content-Type: application/json" \
             -d "$json" "$url" >/dev/null 2>&1 &
        return $?
    elif check_cmd wget; then
        wget -qO- -T 30 \
             --header="Content-Type: application/json" \
             --post-data="$json" "$url" >/dev/null 2>&1 &
        return $?
    else
        log_msg "错误: 系统缺少curl或wget工具"
        return 1
    fi
}

# 推送计数器
PUSH_COUNT=0
SUCCESS_COUNT=0

# ===== 企业微信机器人 =====
if [ -n "$WX_WEBHOOK_KEY" ] && [ "$ENABLE_WECHAT" = "true" ]; then
    log_msg "发送企业微信通知..."
    WX_URL="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=${WX_WEBHOOK_KEY}"
    WX_JSON="{\"msgtype\":\"text\",\"text\":{\"content\":\"${TITLE}\\n${DESC}\"}}"
    
    if send_json "$WX_URL" "$WX_JSON"; then
        log_msg "企业微信通知发送成功"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        log_msg "企业微信通知发送失败"
    fi
    PUSH_COUNT=$((PUSH_COUNT + 1))
fi

# ===== 钉钉机器人 =====
if [ -n "$DINGTALK_WEBHOOK_TOKEN" ] && [ "$ENABLE_DINGTALK" = "true" ]; then
    log_msg "发送钉钉通知..."
    
    # 检查是否启用加签
    if [ -n "$DINGTALK_SECRET" ] && check_cmd openssl; then
        # 加签模式
        timestamp=$(date +%s)000
        string_to_sign="${timestamp}\n${DINGTALK_SECRET}"
        sign=$(echo -n "$string_to_sign" | openssl dgst -sha256 -hmac "$DINGTALK_SECRET" -binary | base64 2>/dev/null)
        
        if [ $? -eq 0 ] && [ -n "$sign" ]; then
            encoded_sign=$(urlencode "$sign")
            DINGTALK_URL="https://oapi.dingtalk.com/robot/send?access_token=${DINGTALK_WEBHOOK_TOKEN}&timestamp=${timestamp}&sign=${encoded_sign}"
            log_msg "使用加签模式发送钉钉通知"
        else
            DINGTALK_URL="https://oapi.dingtalk.com/robot/send?access_token=${DINGTALK_WEBHOOK_TOKEN}"
            log_msg "加签失败，使用普通模式发送钉钉通知"
        fi
    else
        # 普通模式
        DINGTALK_URL="https://oapi.dingtalk.com/robot/send?access_token=${DINGTALK_WEBHOOK_TOKEN}"
    fi
    
    DINGTALK_JSON="{\"msgtype\":\"text\",\"text\":{\"content\":\"${TITLE}\\n${DESC}\"}}"
    
    if send_json "$DINGTALK_URL" "$DINGTALK_JSON"; then
        log_msg "钉钉通知发送成功"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        log_msg "钉钉通知发送失败"
    fi
    PUSH_COUNT=$((PUSH_COUNT + 1))
fi

# ===== IYUU推送 =====
if [ -n "$IYUU_KEY" ] && [ "$ENABLE_IYUU" = "true" ]; then
    log_msg "发送IYUU通知..."
    ENCODED_TITLE=$(urlencode "$TITLE")
    ENCODED_DESC=$(urlencode "$DESC")
    IYUU_URL="https://iyuu.cn/${IYUU_KEY}.send?text=${ENCODED_TITLE}&desp=${ENCODED_DESC}"
    
    if send_http "$IYUU_URL"; then
        log_msg "IYUU通知发送成功"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        log_msg "IYUU通知发送失败"
    fi
    PUSH_COUNT=$((PUSH_COUNT + 1))
fi

# ===== Telegram Bot =====
if [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_USER_ID" ] && [ "$ENABLE_TELEGRAM" = "true" ]; then
    log_msg "发送Telegram通知..."
    TG_API="https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage"
    TG_TEXT=$(urlencode "${TITLE}\n${DESC}")
    TG_PAYLOAD="chat_id=${TG_USER_ID}&text=${TG_TEXT}&parse_mode=HTML"
    
    if check_cmd curl; then
        curl -s --connect-timeout 10 --max-time 30 \
             -X POST "$TG_API" -d "$TG_PAYLOAD" >/dev/null 2>&1 &
        curl_result=$?
    elif check_cmd wget; then
        wget -qO- -T 30 --post-data="$TG_PAYLOAD" "$TG_API" >/dev/null 2>&1 &
        curl_result=$?
    else
        curl_result=1
    fi
    
    if [ $curl_result -eq 0 ]; then
        log_msg "Telegram通知发送成功"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        log_msg "Telegram通知发送失败"
    fi
    PUSH_COUNT=$((PUSH_COUNT + 1))
fi

# ===== Server酱推送 =====
if [ -n "$SERVERCHAN_KEY" ] && [ "$ENABLE_SERVERCHAN" = "true" ]; then
    log_msg "发送Server酱通知..."
    ENCODED_TITLE=$(urlencode "$TITLE")
    ENCODED_DESC=$(urlencode "$DESC")
    SC_URL="https://sctapi.ftqq.com/${SERVERCHAN_KEY}.send?title=${ENCODED_TITLE}&desp=${ENCODED_DESC}"
    
    if send_http "$SC_URL"; then
        log_msg "Server酱通知发送成功"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        log_msg "Server酱通知发送失败"
    fi
    PUSH_COUNT=$((PUSH_COUNT + 1))
fi

# ===== 结果统计 =====
if [ $PUSH_COUNT -eq 0 ]; then
    log_msg "警告: 未配置或启用任何推送方式"
    echo "请编辑配置文件: $CONF_FILE"
    exit 1
else
    log_msg "推送完成: 成功 $SUCCESS_COUNT/$PUSH_COUNT 个通道"
    if [ $SUCCESS_COUNT -gt 0 ]; then
        echo "推送通知已发送: $TITLE"
        exit 0
    else
        echo "推送通知发送失败: $TITLE"
        exit 1
    fi
fi
