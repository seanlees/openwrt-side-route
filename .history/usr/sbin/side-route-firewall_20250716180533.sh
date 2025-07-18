#!/bin/sh
set -u

local CONFIG_FILE="/etc/config/side-route"
local CONFIG_FILE_TMP="/tmp/side-route"

# 日志记录函数（必须从外部传入）
log() {
    local level="$1"
    local message="$2"
    logger -t "SIDE_ROUTE_FIREWALL" -p "user.$level" "$message"
}

# 解析设备配置
parse_devices() {
    local config="$1"
    local section_type="$2"
    uci -c "$config" foreach "$section_type" <<'EOF'
        name=$(uci_get "$config" "$SECT" "name")
        ip=$(uci_get "$config" "$SECT" "ip")
        enable=$(uci_get "$config" "$SECT" "enable")
        echo "$SECT|$name|$ip|$enable"
EOF
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

# 同步设备规则
sync_device_nft_rules() {
    local fwmark="$1"

    local old_devs=$(parse_devices "$CONFIG_FILE_TMP" "device")
    local new_devs=$(parse_devices "$CONFIG_FILE" "device")

    local all_old=$(echo "$old_devs" | cut -d '|' -f1)
    local all_new=$(echo "$new_devs" | cut -d '|' -f1)

    local added removed modified

    for dev in $all_new; do
        if ! echo "$all_old" | grep -q "^$dev\$"; then
            added="$added $dev"
        fi
    done

    for dev in $all_old; do
        if ! echo "$all_new" | grep -q "^$dev\$"; then
            removed="$removed $dev"
        fi
    done

    for dev in $all_new; do
        if echo "$all_old" | grep -q "^$dev\$"; then
            local old_line=$(echo "$old_devs" | grep "^$dev|")
            local new_line=$(echo "$new_devs" | grep "^$dev|")
            if [ "$old_line" != "$new_line" ]; then
                modified="$modified $dev"
            fi
        fi
    done

    # 删除被移除的设备规则
    for dev in $removed; do
        local ip=$(echo "$old_devs" | grep "^$dev|" | cut -d '|' -f3)
        delete_nft_rule "$ip" "$fwmark"
    done

    # 添加/更新新增或修改的设备规则
    for dev in $added $modified; do
        local ip=$(echo "$new_devs" | grep "^$dev|" | cut -d '|' -f3)
        local enable=$(echo "$new_devs" | grep "^$dev|" | cut -d '|' -f4)
        if [ "$enable" = "1" ]; then
            add_or_update_nft_rule "$ip" "$fwmark"
        else
            delete_nft_rule "$ip" "$fwmark"
        fi
    done
}