#!/bin/sh
# 加载OpenWrt标准函数
. /lib/functions.sh

set -u

CONFIG_FILE="/etc/config/side-route"
CONFIG_FILE_TMP="/tmp/side-route"

# 日志记录函数（必须从外部传入）
log() {
    local level="$1"
    local message="$2"
    logger -t "SIDE_ROUTE_FIREWALL" -p "user.$level" "$message"
}

# 确保 nft 表和链存在
ensure_nft_table_chain() {
    local table_name="side_route_nft"
    local chain_name="prerouting_mangle"

    if ! nft list tables inet | grep -q "$table_name"; then
        log "info" "Creating nft table: $table_name"
        nft add table inet "$table_name"
    fi

    if ! nft list chains inet "$table_name" | grep -q "$chain_name"; then
        log "info" "Creating nft chain: $chain_name"
        nft add chain inet "$table_name" "$chain_name" { type filter hook prerouting priority mangle\; }
    fi
}

# 判断规则是否存在
rule_exists() {
    local expr="$1"
    nft list ruleset | grep -A1 -B1 "$expr" | grep -q "$expr" 2>/dev/null
}

# 获取规则表达式
get_rule_expression() {
    local ip="$1"
    local fwmark="$2"
    log "info" "ip saddr $ip meta mark set $fwmark"
}

# 添加或更新规则
add_or_update_nft_rule() {
    local ip="$1"
    local fwmark="$2"
    local expr=$(get_rule_expression "$ip" "$fwmark")
    if ! rule_exists "$expr"; then
        log "info" "Adding nft rule: $expr"
        nft add rule inet side_route_nft prerouting_mangle "$expr"
    fi
}

# 删除规则
delete_nft_rule() {
    local ip="$1"
    local fwmark="$2"
    local expr=$(get_rule_expression "$ip" "$fwmark")
    if rule_exists "$expr"; then
        log "info" "Deleting nft rule: $expr"
        nft delete rule inet side_route_nft prerouting_mangle "$expr"
    fi
}

# 解析设备配置（使用UCI函数）
parse_devices() {
    local config="$1"
    local output=""
    
    # 使用config_load加载配置
    config_load "$config"
    
    # 遍历每个设备section
    config_foreach parse_device_section device "$config"
}
parse_device_section() {
    local section="$1"
    local config="$2"
    local name ip enable
    
    # 获取section的配置项
    config_get name "$section" "name"
    config_get ip "$section" "ip"
    config_get_bool enable "$section" "enable" 0  # 默认为0
    
    # 输出：section|ip|enable
    echo "$section|$ip|$enable"
}

# 同步设备规则
sync_device_nft_rules() {
    ensure_nft_table_chain
    
    local fwmark="$1"
    local fwmark_old="$2"

    # 解析新旧配置
    local OLD_DEVICES=$(parse_devices "$OLD_CONFIG")
    local NEW_DEVICES=$(parse_devices "$NEW_CONFIG")
    
    # 处理删除的设备
    echo "$OLD_DEVICES" | while IFS='|' read -r section ip enable; do
        if ! echo "$NEW_DEVICES" | grep -q "^$section|"; then
            # 设备被删除
            if [ "$enable" = "1" ]; then
                delete_nft_rule "$ip" $fwmark_old
            fi
        fi
    done
    
    # 处理新增或修改的设备
    echo "$NEW_DEVICES" | while IFS='|' read -r section new_ip new_enable; do
        # 查找旧配置中的设备
        local old_line=$(echo "$OLD_DEVICES" | grep "^$section|")
        
        if [ -z "$old_line" ]; then
            # 新增设备
            if [ "$new_enable" = "1" ]; then
                add_or_update_rule "$new_ip"
            fi
        else
            # 现有设备，检查变化
            IFS='|' read -r _ old_ip old_enable <<EOF
$old_line
EOF
            
            # 检查IP是否变化
            if [ "$old_ip" != "$new_ip" ]; then
                # IP变化，删除旧规则（如果启用）
                if [ "$old_enable" = "1" ]; then
                    delete_nft_rule "$old_ip"
                fi
                # 添加新规则（如果启用）
                if [ "$new_enable" = "1" ]; then
                    add_or_update_rule "$new_ip"
                fi
            else
                # IP未变，检查启用状态变化
                if [ "$old_enable" != "$new_enable" ]; then
                    if [ "$new_enable" = "1" ]; then
                        add_or_update_rule "$new_ip"
                    else
                        delete_nft_rule "$new_ip"
                    fi
                fi
            fi
        fi
    done
}