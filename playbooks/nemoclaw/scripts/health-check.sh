#!/bin/bash
# NemoClaw 健康检查 + 自动恢复
#
# 检查链路: DGX localhost → WireGuard → 域名代理
# 如果不健康，自动修复 openshell forward 或重新 onboard
#
# 部署为 cron:
#   */5 * * * * /home/ubuntu/ansible-infra/playbooks/nemoclaw/scripts/health-check.sh >> /var/log/nemoclaw-health.log 2>&1

set -euo pipefail

LOGPREFIX="[$(date '+%Y-%m-%d %H:%M:%S')]"
DGX_CMD="sshpass -p 'V3gbfi&E' ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o ServerAliveInterval=15 -p 6090 xsuper@106.13.186.155"

NVIDIA_API_KEY="${NVIDIA_API_KEY:-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}"
CHAT_UI_URL="https://nemoclaw.peafamily.online"
SANDBOX_NAME="my-assistant"

log()  { echo "$LOGPREFIX [INFO] $*"; }
warn() { echo "$LOGPREFIX [WARN] $*"; }
err()  { echo "$LOGPREFIX [ERROR] $*"; }

# ============================================
# 1. 检查 WireGuard 隧道
# ============================================
if ! ping -c 1 -W 3 10.10.10.5 &>/dev/null; then
    err "WireGuard 隧道断开 (ping 10.10.10.5 失败)"
    warn "尝试远程重启 DGX WireGuard..."
    eval "$DGX_CMD" "echo 'V3gbfi&E' | sudo -S systemctl restart wg-quick@wg0" 2>/dev/null || true
    sleep 5
    if ! ping -c 1 -W 3 10.10.10.5 &>/dev/null; then
        err "WireGuard 恢复失败，无法继续"
        exit 1
    fi
    log "WireGuard 已恢复"
fi

# ============================================
# 2. 检查 DGX localhost:18789 (openshell forward)
# ============================================
DGX_STATUS=$(eval "$DGX_CMD" "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 http://127.0.0.1:18789/" 2>/dev/null || echo "000")

if [ "$DGX_STATUS" = "200" ]; then
    # ============================================
    # 3. 检查域名代理 (端到端)
    # ============================================
    PROXY_STATUS=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 10 "$CHAT_UI_URL/" 2>/dev/null || echo "000")
    if [ "$PROXY_STATUS" = "200" ]; then
        log "全链路健康 (DGX=$DGX_STATUS, Proxy=$PROXY_STATUS)"
        exit 0
    else
        warn "域名代理异常 ($PROXY_STATUS)，但 DGX 本地正常。检查 NPM/DNS"
        exit 0
    fi
fi

# ============================================
# DGX localhost 不通，尝试修复
# ============================================
warn "DGX localhost:18789 返回 $DGX_STATUS，开始修复..."

# 4a. 尝试重启 openshell forward
log "修复步骤 1: 重启 openshell forward..."
eval "$DGX_CMD" "source ~/.nvm/nvm.sh && \
    openshell forward stop 18789 2>/dev/null; \
    kill \$(lsof -ti :18789) 2>/dev/null; \
    sleep 2; \
    openshell forward start 18789 ${SANDBOX_NAME} --background" 2>/dev/null || true

sleep 10

DGX_STATUS2=$(eval "$DGX_CMD" "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 http://127.0.0.1:18789/" 2>/dev/null || echo "000")
if [ "$DGX_STATUS2" = "200" ]; then
    log "openshell forward 重启成功"
    exit 0
fi

# 4b. Forward 重启没用，可能沙箱崩了，需要重新 onboard
warn "修复步骤 2: 沙箱可能崩溃，执行重新 onboard..."
eval "$DGX_CMD" "source ~/.nvm/nvm.sh && \
    openshell forward stop 18789 2>/dev/null; \
    openshell sandbox delete ${SANDBOX_NAME} 2>/dev/null; \
    sleep 3; \
    export NVIDIA_API_KEY='${NVIDIA_API_KEY}' && \
    export NEMOCLAW_PROVIDER=build && \
    export NEMOCLAW_SANDBOX_NAME=${SANDBOX_NAME} && \
    export CHAT_UI_URL=${CHAT_UI_URL} && \
    nemoclaw onboard --non-interactive" 2>/dev/null

sleep 15

DGX_STATUS3=$(eval "$DGX_CMD" "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 http://127.0.0.1:18789/" 2>/dev/null || echo "000")
if [ "$DGX_STATUS3" = "200" ]; then
    log "重新 onboard 成功 (注意: token 可能已变更)"
    # 提取新 token
    NEW_TOKEN=$(eval "$DGX_CMD" "source ~/.nvm/nvm.sh && openshell sandbox ssh-config my-assistant > /tmp/ssh-sandbox.conf && ssh -F /tmp/ssh-sandbox.conf openshell-my-assistant 'python3 -c \"import json; c=json.load(open(chr(47)+chr(115)+chr(97)+chr(110)+chr(100)+chr(98)+chr(111)+chr(120)+chr(47)+chr(46)+chr(111)+chr(112)+chr(101)+chr(110)+chr(99)+chr(108)+chr(97)+chr(119)+chr(47)+chr(111)+chr(112)+chr(101)+chr(110)+chr(99)+chr(108)+chr(97)+chr(119)+chr(46)+chr(106)+chr(115)+chr(111)+chr(110))); print(c.get(chr(103)+chr(97)+chr(116)+chr(101)+chr(119)+chr(97)+chr(121),{}).get(chr(97)+chr(117)+chr(116)+chr(104),{}).get(chr(116)+chr(111)+chr(107)+chr(101)+chr(110),chr(63)))\"'" 2>/dev/null | tr -d '[:space:]')
    warn "新 Token URL: ${CHAT_UI_URL}/#token=${NEW_TOKEN}"
else
    err "重新 onboard 失败 (status=$DGX_STATUS3)，需要人工介入"
    exit 1
fi
