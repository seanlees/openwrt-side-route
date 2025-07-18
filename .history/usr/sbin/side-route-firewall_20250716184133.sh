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



# 同步设备规则
sync_device_nft_rules() {
    ensure_nft_table_chain
    
    local fwmark="$1"

    local old_devs=$(parse_devices "$CONFIG_FILE_TMP" "device")
    local new_devs=$(parse_devices "$CONFIG_FILE" "device")

     # 处理每个设备
    local processed_ips=""

    echo "$new_devs" | while IFS='|' read -r dev_name _ ip enable; do
        # 跳过空行
        [ -z "$ip" ] && continue

        # 标记已处理 IP
        processed_ips="$processed_ips $ip"

        # 查找旧配置中的对应设备（按 ip 匹配）
        local old_line=$(echo "$old_devs" | awk -F'|' -v ip="$ip" '$3 == ip')

        if [ -z "$old_line" ]; then
            # 新增：旧配置中没有这个 IP
            if [ "$enable" = "1" ]; then
                add_or_update_nft_rule "$ip" "$fwmark"
            fi
        else
            # 修改或保持：旧配置中有这个 IP
            local old_enable=$(echo "$old_line" | cut -d '|' -f4)

            if [ "$enable" = "1" ] && [ "$old_enable" != "1" ]; then
                # enable 从 0 → 1，添加规则
                add_or_update_nft_rule "$ip" "$fwmark"
            elif [ "$enable" != "1" ] && [ "$old_enable" = "1" ]; then
                # enable 从 1 → 0，删除规则
                delete_nft_rule "$ip" "$fwmark"
            elif [ "$enable" = "1" ] && [ "$old_enable" = "1" ]; then
                # enable 都为 1，检查是否需要更新规则
                local old_ip=$(echo "$old_line" | cut -d '|' -f3)
                if [ "$ip" != "$old_ip" ]; then
                    delete_nft_rule "$old_ip" "$fwmark"
                    add_or_update_nft_rule "$ip" "$fwmark"
                fi
            fi
        fi
    done

    # 处理删除的设备（旧配置中有，新配置中没有）
    echo "$old_devs" | while IFS='|' read -r dev_name _ old_ip old_enable; do
        # 跳过空行
        [ -z "$old_ip" ] && continue

        if ! echo "$processed_ips" | grep -wq "$old_ip"; then
            if [ "$old_enable" = "1" ]; then
                delete_nft_rule "$old_ip" "$fwmark"
            fi
        fi
    done
}