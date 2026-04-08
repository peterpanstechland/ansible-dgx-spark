#!/bin/bash
# 给黑客松队友生成 WireGuard 配置，用于访问 NemoClaw UI
#
# 用法:
#   ./add-team-member.sh <名字>
#   例: ./add-team-member.sh zhangsan
#
# 运行后会:
#   1. 在 OpenWrt 上添加 WireGuard Peer
#   2. 添加防火墙规则（仅允许访问 NPM 的 443 端口）
#   3. 生成客户端配置文件 + 二维码（手机扫码即用）
#
# 前提: 本机能 ssh root@<OPENWRT_IP>

set -euo pipefail

# ============================================
# 配置 — 请根据你的环境修改
# ============================================
OPENWRT_HOST="root@<YOUR_OPENWRT_IP>"
DGX_SSH_CMD="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 -p <DGX_SSH_PORT> <DGX_USER>@<DGX_HOST>"
WG_ENDPOINT="<YOUR_DOMAIN>:51820"
WG_SERVER_PUBKEY="<YOUR_WG_SERVER_PUBLIC_KEY>"
WG_DNS="10.10.10.1"
NPM_IP="<YOUR_NPM_SERVER_IP>"
BASE_IP_PREFIX="10.10.10"
NEMOCLAW_DOMAIN="nemoclaw.<YOUR_DOMAIN>"
OUTPUT_DIR="$(dirname "$0")/../team-configs"

# 已分配的 IP (不要动)
# .1=OpenWrt .2=Office .3=Mobile .4=PC .5=DGX
# 队友从 .10 开始分配
TEAM_IP_START=10

# ============================================
# 参数检查
# ============================================
if [ $# -lt 1 ]; then
    echo "用法: $0 <队友名字>"
    echo "例:   $0 zhangsan"
    exit 1
fi

MEMBER_NAME="$1"
MEMBER_NAME_LOWER=$(echo "$MEMBER_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
MEMBER_UCI_SAFE=$(echo "$MEMBER_NAME_LOWER" | tr '-' '_')

# ============================================
# 查找下一个可用 IP
# ============================================
echo ">>> 检查已分配的 IP..."
EXISTING_IPS=$(ssh "$OPENWRT_HOST" "uci show network | grep 'allowed_ips='" 2>/dev/null | sed "s/.*'\([0-9.]*\)\/.*/\1/" | grep "^${BASE_IP_PREFIX}\." || true)

NEXT_IP=""
for i in $(seq $TEAM_IP_START 254); do
    CANDIDATE="${BASE_IP_PREFIX}.${i}"
    if ! echo "$EXISTING_IPS" | grep -qx "$CANDIDATE"; then
        NEXT_IP="$CANDIDATE"
        break
    fi
done

if [ -z "$NEXT_IP" ]; then
    echo "错误: 没有可用的 IP 地址了"
    exit 1
fi

echo ">>> 分配 IP: $NEXT_IP"

# ============================================
# 生成密钥对
# ============================================
echo ">>> 生成 WireGuard 密钥对..."
PRIVATE_KEY=$(wg genkey)
PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)

# ============================================
# 在 OpenWrt 上添加 Peer
# ============================================
PEER_UCI_NAME="wg_team_${MEMBER_UCI_SAFE}"
echo ">>> 添加 Peer 到 OpenWrt (${PEER_UCI_NAME})..."

ssh "$OPENWRT_HOST" bash -s <<REMOTE_SCRIPT
set -e
uci set network.${PEER_UCI_NAME}=wireguard_wg0
uci set network.${PEER_UCI_NAME}.description='Hackathon-${MEMBER_NAME}'
uci set network.${PEER_UCI_NAME}.public_key='${PUBLIC_KEY}'
uci add_list network.${PEER_UCI_NAME}.allowed_ips='${NEXT_IP}/32'
uci commit network

# 防火墙规则: 仅允许访问 NPM (443)
while iptables -D FORWARD -i wg0 -s ${NEXT_IP} -d ${NPM_IP} -p tcp --dport 443 -j ACCEPT 2>/dev/null; do :; done
while iptables -D FORWARD -i wg0 -s ${NEXT_IP} -j DROP 2>/dev/null; do :; done
iptables -I FORWARD -i wg0 -s ${NEXT_IP} -j DROP
iptables -I FORWARD -i wg0 -s ${NEXT_IP} -d ${NPM_IP} -p tcp --dport 443 -j ACCEPT
/etc/init.d/network reload
REMOTE_SCRIPT

echo ">>> OpenWrt Peer 添加完成"

# ============================================
# 生成客户端配置
# ============================================
mkdir -p "$OUTPUT_DIR"
CONFIG_FILE="${OUTPUT_DIR}/${MEMBER_NAME_LOWER}.conf"

cat > "$CONFIG_FILE" <<WGCONF
[Interface]
# ${MEMBER_NAME} - 黑客松 NemoClaw 访问
Address = ${NEXT_IP}/32
PrivateKey = ${PRIVATE_KEY}
DNS = ${WG_DNS}

[Peer]
PublicKey = ${WG_SERVER_PUBKEY}
Endpoint = ${WG_ENDPOINT}
AllowedIPs = ${BASE_IP_PREFIX}.0/24, ${NPM_IP}/32
PersistentKeepalive = 25
WGCONF

chmod 600 "$CONFIG_FILE"
echo ">>> 配置文件已生成: $CONFIG_FILE"

# ============================================
# 生成二维码（如果有 qrencode）
# ============================================
QR_FILE="${OUTPUT_DIR}/${MEMBER_NAME_LOWER}.png"
if command -v qrencode &>/dev/null; then
    qrencode -t png -o "$QR_FILE" < "$CONFIG_FILE"
    echo ">>> 二维码已生成: $QR_FILE"
else
    echo ">>> 提示: 安装 qrencode 可生成二维码 (apt install qrencode)"
fi

# ============================================
# 生成使用说明文件
# ============================================
README_FILE="${OUTPUT_DIR}/${MEMBER_NAME_LOWER}-README.txt"
cat > "$README_FILE" <<README
黑客松 NemoClaw 接入指南 — ${MEMBER_NAME}
═══════════════════════════════════════════════════

步骤 1: 安装 WireGuard
  - Windows/Mac: https://www.wireguard.com/install/
  - iOS/Android: 应用商店搜索 "WireGuard"

步骤 2: 导入配置
  - 电脑: 打开 WireGuard → Import tunnel → 选择 ${MEMBER_NAME_LOWER}.conf
  - 手机: 扫描 ${MEMBER_NAME_LOWER}.png 二维码

步骤 3: 开启 VPN 连接

步骤 4: 浏览器打开以下链接

  NemoClaw AI 助手:
  https://${NEMOCLAW_DOMAIN}/#token=<见 nemoclaw status 输出>

═══════════════════════════════════════════════════
README
echo ">>> 使用说明已生成: $README_FILE"

# ============================================
# 输出摘要
# ============================================
cat <<SUMMARY

═══════════════════════════════════════════════════════
  队友 WireGuard 配置已生成!
═══════════════════════════════════════════════════════

  名称:       ${MEMBER_NAME}
  VPN IP:     ${NEXT_IP}

  发给队友的文件:
    ${CONFIG_FILE}           (WireGuard 配置)
    ${QR_FILE}               (手机扫码用)
    ${README_FILE}           (使用说明 + 链接)

  安全说明:
    - 此配置仅允许访问 NemoClaw 和 Open WebUI
    - 无法访问家里其他任何设备或服务
    - 黑客松结束后运行 cleanup-hackathon.sh 一键清理

═══════════════════════════════════════════════════════
SUMMARY
