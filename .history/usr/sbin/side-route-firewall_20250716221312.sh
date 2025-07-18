#!/bin/sh
# 加载OpenWrt标准函数
. /lib/functions.sh

set -u

CONFIG_FILE="/etc/config/side-route"
CONFIG_FILE_TMP="/tmp/side-route"

table_name="side_route_nft"
chain_name="prerouting_mangle"

# 日志记录函数（必须从外部传入）
log() {
    local level="$1"
    local message="$2"
    logger -t "SIDE_ROUTE_FIREWALL" -p "user.$level" "$message"
}

# 确保 nft 表和链存在
ensure_nft_table_chain() {
    if ! nft list tables inet | grep -q "table inet $table_name"; then
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
    # nft list ruleset | grep -A1 -B1 "$expr" | grep -q "$expr" 2>/dev/null
    nft list chain inet "$table_name" "$chain_name" 2>/dev/null | awk -v expr="$expr" '
    $0 ~ expr {
        found = 1
    }
    END {
        exit !found
    }'
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
        nft delete rule inet"$table_name" "$chain_name" "$expr"
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
    config_load "$config"
    
    # 遍历每个设备section
    config_foreach parse_device_section device "$config"
}

# 更新防火墙规则
update_nft_rules() {
    local fwmark="$1"
    local fwmark_old="$2"

    # 确保nft表和链存在
    ensure_nft_table_chain
    
    # 1. 先判断fwmark是否修改,如果修改则重新添加规则. 优先级1
    if [ "$fwmark" != "$fwmark_old" ]; then
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

    # 解析新旧配置
    local OLD_DEVICES=$(parse_devices "$OLD_CONFIG")
    local NEW_DEVICES=$(parse_devices "$NEW_CONFIG")

    # 2. 处理配置和 fwmark 都未变   优先级2
    if [ "$NEW_DEVICES" = "$OLD_DEVICES" ] && [ "$fwmark" = "$fwmark_old" ]; then
        echo "$NEW_DEVICES" | while IFS='|' read -r new_ip new_enable; do
            if [ "$new_enable" = "1" ]; then
                if ! rule_exists "$(get_rule_expression "$new_ip" "$fwmark")"; then
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