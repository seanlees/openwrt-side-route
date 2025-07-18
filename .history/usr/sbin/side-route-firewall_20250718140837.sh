#!/bin/sh
set -e

# 防止 /lib/functions.sh 中使用未定义变量时报错

# 加载OpenWrt标准函数
. /lib/functions.sh

CONFIG_FILE="/etc/config/side-route"
CONFIG_FILE_TMP="/tmp/side-route"

table_name="side_route_nft"
chain_name="mangle_prerouting"

LOG_TAG="SIDE_ROUTE_FIREWALL"

# 日志记录函数
log() {
    local level="$1"
    local message="$2"
    logger -t "$LOG_TAG" -p "user.$level" "$message"
}

# 确保 nft 表和链存在
ensure_nft_table_chain() {
    if ! nft list tables inet | grep -q "table inet $table_name"; then
        log "info" "Creating nft table: $table_name"
        nft add table inet "$table_name"
    fi

    if ! nft list chain inet "$table_name" "$chain_name" 2>/dev/null | grep -q "chain $chain_name"; then
        log "info" "Creating nft chain: $chain_name"
        nft add chain inet "$table_name" "$chain_name" { type filter hook prerouting priority mangle\; }
    fi
}

# 判断规则是否存在
rule_exists() {
    local expr="$1"
    log "info" "Checking rule: $expr"
    # nft list ruleset | grep -A1 -B1 "$expr" | grep -q "$expr" 2>/dev/null
    nft list chain inet "$table_name" "$chain_name" 2>/dev/null | grep -qF "$expr"
}

# 获取规则表达式
get_rule_expression() {
    local ip="$1"
    local fwmark="$2"
    echo "ip saddr $ip meta mark set $fwmark"
}

# 添加或更新规则
add_or_update_nft_rule() {
    local ip="$1"
    local fwmark="$2"
    local expr=$(get_rule_expression "$ip" "$fwmark")
    if ! rule_exists "$expr"; then
        log "info" "Adding nft rule: $expr"
        nft add rule inet "$table_name" "$chain_name" "$expr"
    fi
}

# 删除规则
delete_nft_rule() {
    local ip="$1"
    local fwmark="$2"
    local expr=$(get_rule_expression "$ip" "$fwmark")
    if rule_exists "$expr"; then
        log "info" "Deleting nft rule: $expr"
        
        local handle=$(nft -a list chain inet "$table_name" "$chain_name" | grep -A2 "$expr" | awk '/# handle/{print $NF}' 2>/dev/null)
        if [ -n "$handle" ]; then
            log "info" "Deleting nft rule: $expr (handle $handle)"
            nft delete rule inet "$table_name" "$chain_name" handle "$handle"
        else
            log "debug" "Rule not found: $expr"
        fi

        #nft --handle list chain inet "$table_name" "$chain_name" |grep "$ip" | awk '/handle/{print $NF}' | xargs nft delete rule inet "$table_name" "$chain_name" 
    fi
}

# 解析设备配置（只输出 ip|enable）
parse_device_section() {
    local section="$1"
    local config="$2"
    local ip enable
    
    # 获取section的配置项
    config_get ip "$section" "ip"
    config_get_bool enable "$section" "enable" 0
    
    # 输出：ip|enable
    echo "$ip|$enable"
}

# 解析设备配置（使用UCI函数）
parse_devices() {
    local config="$1"
    local output=""
    
    # 使用config_load加载配置
    config_load "$config" || {
        log "error" "Failed to load config: $config"
        return 1
    }
    
    # 遍历每个设备section
    config_foreach parse_device_section device "$config"
}

# 更新防火墙规则
update_nft_rules() {
    log "info" "Updating nft rules..."
    local fwmark=$(printf "0x%.8x" "$1")
    local fwmark_old=$(printf "0x%.8x" "$2")

    # 确保nft表和链存在
    ensure_nft_table_chain

     # 解析新旧配置
    local OLD_DEVICES=$(parse_devices "$CONFIG_FILE_TMP")
    local NEW_DEVICES=$(parse_devices "$CONFIG_FILE")

    log "debug" "fwmark: $1- $fwmark, fwmark_old: $2- $fwmark_old"
    log "debug" "OLD_DEVICES: $OLD_DEVICES"
    log "debug" "NEW_DEVICES: $NEW_DEVICES"
    
    # 1. 先判断fwmark是否修改,如果修改则重新添加规则. 优先级1
    if [ "$fwmark" != "$fwmark_old" ]; then
        log "info" "Firewall mark changed from $fwmark_old to $fwmark"
        
        # fwmark 变化，删除所有旧规则
        echo "$OLD_DEVICES" | while IFS='|' read -r old_ip _; do
            delete_nft_rule "$old_ip" "$fwmark_old"
        done

        # 用新 fwmark 重新添加所有启用的设备规则
        echo "$NEW_DEVICES" | while IFS='|' read -r new_ip new_enable; do
            if [ "$new_enable" = "1" ]; then
                add_or_update_nft_rule "$new_ip" "$fwmark"
            fi
        done
        return 0
    fi

    # 2. 处理配置和 fwmark 都未变   优先级2
    if [ "$NEW_DEVICES" = "$OLD_DEVICES" ] && [ "$fwmark" = "$fwmark_old" ]; then
        log "debug" "config not change, checking nft rules exists"
        echo "$NEW_DEVICES" | while IFS='|' read -r new_ip new_enable; do
            log "debug" "checking value: $new_ip $new_enable"
            if [ "$new_enable" = "1" ]; then
                #log "debug" "rule_exists: $rule_exists"
                if ! rule_exists "$(get_rule_expression "$new_ip" "$fwmark")"; then
                    log "debug" "device $new_ip not found in nft, adding"
                    add_or_update_nft_rule "$new_ip" "$fwmark"
                fi
            fi
        done
        return 0
    fi
    
    ############### 处理配置文件的变化  ###############
    # 3. 处理删除的设备和IP变化 
    echo "$OLD_DEVICES" | while IFS='|' read -r old_ip old_enable; do
        local new_line=$(echo "$NEW_DEVICES" | grep "^$old_ip|")
        if [ -z "$new_line" ]; then
            delete_nft_rule "$old_ip" "$fwmark_old"
        else
            IFS='|' read -r _ new_enable <<EOF
$new_line
EOF
            if [ "$new_enable" = "0" ]; then
                delete_nft_rule "$old_ip" "$fwmark_old"
            fi
        fi
    done

    # 4. 处理新增设备和IP变化
    echo "$NEW_DEVICES" | while IFS='|' read -r new_ip new_enable; do
        local old_line=$(echo "$OLD_DEVICES" | grep "^$new_ip|")
        if [ -z "$old_line" ]; then
            if [ "$new_enable" = "1" ]; then
                add_or_update_nft_rule "$new_ip" "$fwmark"
            fi
        else
            IFS='|' read -r _ old_enable <<EOF
$old_line
EOF
            if [ "$old_enable" = "0" ] && [ "$new_enable" = "1" ]; then
                add_or_update_nft_rule "$new_ip" "$fwmark"
            fi
        fi
    done
}

update_nft_rules "$1" "$2"