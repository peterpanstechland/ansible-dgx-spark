#!/bin/bash
# 黑客松结束清理脚本
#
# 一键清理所有黑客松相关的临时配置:
#   - WireGuard 队友 Peers
#   - DGX Spark Peer
#   - 防火墙规则
#   - NemoClaw 沙箱
#   - Registry Mirror 容器
#   - DNS 记录
#
# 用法:
#   ./cleanup-hackathon.sh          # 预览模式（只显示会做什么）
#   ./cleanup-hackathon.sh --force  # 实际执行清理

set -euo pipefail

# ============================================
# 配置 — 请根据你的环境修改
# ============================================
OPENWRT_HOST="root@<YOUR_OPENWRT_IP>"
DGX_SSH="ssh -o StrictHostKeyChecking=no -p <DGX_SSH_PORT> <DGX_USER>@<DGX_HOST>"
NEMOCLAW_DOMAIN="nemoclaw.<YOUR_DOMAIN>"
NPM_SERVER_IP="<YOUR_NPM_SERVER_IP>"
FORCE=false

if [ "${1:-}" = "--force" ]; then
    FORCE=true
fi

log()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
run()  {
    if $FORCE; then
        eval "$@"
    else
        echo "  (dry-run) $*"
    fi
}

echo ""
echo "═══════════════════════════════════════════════════"
echo "  黑客松清理脚本"
if $FORCE; then
    echo "  模式: ⚠️  实际执行"
else
    echo "  模式: 预览 (加 --force 实际执行)"
fi
echo "═══════════════════════════════════════════════════"
echo ""

# 1. DGX Spark: 停止 NemoClaw + WireGuard
log "1/5 DGX Spark: 停止 NemoClaw 和 WireGuard"
run "$DGX_SSH 'source ~/.nvm/nvm.sh && \
    openshell forward stop 18789 2>/dev/null; \
    openshell sandbox delete my-assistant 2>/dev/null; \
    sudo systemctl stop wg-quick@wg0; \
    sudo systemctl disable wg-quick@wg0; \
    sudo rm -f /etc/wireguard/wg0.conf; \
    echo DGX cleanup done' 2>&1"

# 2. OpenWrt: 删除队友 WireGuard Peers
log "2/5 OpenWrt: 删除队友 WireGuard Peers"
TEAM_PEERS=$(ssh "$OPENWRT_HOST" "uci show network | grep -oE 'wg_team_[a-z_]+(?==wireguard)'" 2>/dev/null | sed 's/=wireguard//' || true)
if [ -n "$TEAM_PEERS" ]; then
    for peer in $TEAM_PEERS; do
        log "  删除 Peer: $peer"
        run "ssh $OPENWRT_HOST 'uci delete network.${peer}'"
    done
else
    log "  没有队友 Peers"
fi

# 3. OpenWrt: 删除 DGX Spark Peer + 防火墙
log "3/5 OpenWrt: 删除 DGX Spark Peer + 防火墙"
run "ssh $OPENWRT_HOST 'uci delete network.wg_dgx 2>/dev/null; echo done'"
run "ssh $OPENWRT_HOST 'rm -f /etc/firewall.dgx'"
run "ssh $OPENWRT_HOST 'uci commit network && /etc/init.d/network restart'"

# 4. OpenWrt: 删除 DNS 记录
log "4/5 OpenWrt: 删除 hackathon DNS 记录"
run "ssh $OPENWRT_HOST \"uci del_list dhcp.@dnsmasq[0].address='/${NEMOCLAW_DOMAIN}/${NPM_SERVER_IP}' 2>/dev/null; uci commit dhcp; /etc/init.d/dnsmasq restart\""

# 5. Ubuntu: 停止 Registry Mirror 容器
log "5/5 Ubuntu: 停止 Registry Mirror 容器"
run "docker stop registry-ghcr registry-dockerhub 2>/dev/null; docker rm registry-ghcr registry-dockerhub 2>/dev/null; echo 'Registry mirrors removed'"

echo ""
echo "═══════════════════════════════════════════════════"
if $FORCE; then
    echo "  清理完成"
    echo ""
    echo "  还需手动处理:"
    echo "    - Ansible inventory: 删除 hosts.yml 中的 hackathon 组"
    echo "    - team-configs/: 删除队友配置文件"
else
    echo "  以上为预览，确认无误后执行:"
    echo "    ./cleanup-hackathon.sh --force"
fi
echo "═══════════════════════════════════════════════════"
