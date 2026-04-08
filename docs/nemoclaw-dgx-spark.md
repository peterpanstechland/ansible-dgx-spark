# NemoClaw on DGX Spark — 运维手册

> 本文档记录 NemoClaw 在 NVIDIA DGX Spark（黑客松临时节点）上的完整部署架构、日常运维和故障排查。
>
> **地址占位符对照**（实际值见 `inventory/cloud/hosts.yml` 和 `playbooks/nemoclaw/vars/main.yml`）
>
> | 占位符 | 说明 |
> |--------|------|
> | `<DGX_PUBLIC_IP>` | DGX Spark 公网 IP（FRP SSH 入口） |
> | `<DGX_WG_IP>` | DGX WireGuard VPN 地址 |
> | `<DGX_LAN_IP>` | DGX 物理网口 IP（Ollama 监听地址） |
> | `<HOME_WG_IP>` | Home 端 WireGuard 地址（= OpenWrt wg0） |
> | `<UBUNTU_LAN_IP>` | Home Ubuntu 服务器 LAN IP |
> | `<OPENWRT_LAN_IP>` | OpenWrt 路由器 LAN IP |
> | `<K3S_CONTAINER_IP>` | K3s Docker 容器 bridge IP |
> | `<WG_SUBNET>` | WireGuard 子网 CIDR |
> | `<TEAM_WG_IP_N>` | 团队成员 VPN 地址 |

---

## 网络架构

```
浏览器 (任意设备)
  │  https://nemoclaw.your-domain.com
  ▼
OpenWrt dnsmasq (nemoclaw.your-domain.com → <UBUNTU_LAN_IP>)
  │
  ▼
Nginx Proxy Manager (Ubuntu <UBUNTU_LAN_IP>, HTTPS 终止)
  │  proxy_pass http://<DGX_WG_IP>:18789
  ▼
WireGuard 隧道 (Home <HOME_WG_IP> ↔ DGX <DGX_WG_IP>)
  │
  ▼
DGX iptables DNAT (wg0:18789 → <K3S_CONTAINER_IP>:30089)
  │
  ▼
K3s NodePort Service (nemoclaw-ui, 30089 → Pod:18789)
  │
  ▼
OpenClaw Gateway (沙箱 Pod 内, --bind lan, Landlock + seccomp + netns 隔离)
  │
  ├── https://inference.local/v1 (openshell inference 路由)
  │   ▼
  │   openshell provider: local-ollama → http://<DGX_LAN_IP>:11434/v1
  │   ▼
  │   Ollama (DGX 宿主机, snap, gpt-oss:120b-fast, 32K ctx, think:off, 100% GPU) ← 主模型
  │
  ├── inference/nvidia/nemotron-3-super-120b-a12b (inference.local 旧路由) ← fallback
  │
  └── wss://msg-frontier.feishu.cn (飞书 WebSocket)
```

> **架构变更 (2026-04):** 原方案使用 `openshell forward` (SSH 隧道) 做宿主机到
> Pod 的端口转发，但因 k3s-in-Docker 网络不稳定导致隧道频繁断裂。现改为
> K8s NodePort + iptables DNAT 直连，由 watchdog 脚本自动维护。

### Registry Mirror（Docker 镜像拉取加速）

```
DGX Docker ──WireGuard──→ Ubuntu:5001 (ghcr.io pull-through cache)
                          Ubuntu:5002 (docker.io pull-through cache)
                            │
                            ▼
                        OpenWrt 网络代理
                            │
                            ▼
                        ghcr.io / docker.io
```

---

## 设备清单

| 角色 | 地址 | 说明 |
|------|------|------|
| DGX Spark | `<DGX_PUBLIC_IP>:6090` (FRP SSH) / `<DGX_WG_IP>` (WireGuard) | NVIDIA GB10, 128GB, aarch64 |
| Home Ubuntu | `<UBUNTU_LAN_IP>` / `<HOME_WG_IP>` (WireGuard) | Docker Registry Mirror, NPM |
| OpenWrt | `<OPENWRT_LAN_IP>` | WireGuard Server, 网络代理, DNS |

---

## 关键配置文件

### DGX Spark 端

| 文件 | 用途 |
|------|------|
| `/etc/wireguard/wg0.conf` | WireGuard 客户端（→ 家里） |
| `/etc/networkd-dispatcher/routable.d/50-wg-ollama.sh` | WG 启动时自动添加 DNAT 规则 |
| `/etc/docker/daemon.json` | Docker registry mirror 配置 |
| `/home/xsuper/nemoclaw-watchdog.sh` | 5 分钟 cron 保活脚本（gateway + NodePort + iptables + SQLite 监控） |
| `/etc/sudoers.d/nemoclaw-watchdog` | watchdog 免密 sudo (iptables/sysctl) |

### Home Ubuntu 端

| 文件 | 用途 |
|------|------|
| `/opt/nginx-proxy-manager/` | NPM（含 nemoclaw.your-domain.com 代理规则） |
| Docker containers: `registry-ghcr`, `registry-dockerhub` | 端口 5001/5002 的 registry mirror |

### OpenWrt 端

| 文件 | 用途 |
|------|------|
| `/etc/config/network` (wireguard_wg0 部分) | WireGuard Server + DGX Peer |
| `/etc/firewall.dgx` | DGX 相关 iptables 规则（单向限制） |
| `dhcp.@dnsmasq[0].address` | nemoclaw.your-domain.com DNS 记录 |

---

## 日常运维

### 查看状态

```bash
# SSH 到 DGX
ssh -p 6090 xsuper@<DGX_PUBLIC_IP>

# 查看沙箱状态
source ~/.nvm/nvm.sh
nemoclaw my-assistant status

# 查看日志
nemoclaw my-assistant logs --tail 50
nemoclaw my-assistant logs --follow

# 检查 NodePort service
docker exec openshell-cluster-nemoclaw kubectl get svc nemoclaw-ui -n openshell

# 检查 socat 端口转发
ss -tlnp | grep 18789

# 检查 watchdog 日志
tail -20 /home/xsuper/nemoclaw-watchdog.log

# 检查 UI 可达性
curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18789/
```

### 检查端到端连通性（从 Home Ubuntu 执行）

```bash
# WireGuard 连通
ping -c 1 <DGX_WG_IP>

# NemoClaw 端口
curl -s -o /dev/null -w '%{http_code}' http://<DGX_WG_IP>:18789/

# 域名代理
curl -s -o /dev/null -w '%{http_code}' https://nemoclaw.your-domain.com/
```

### 查看 WireGuard 状态

```bash
# OpenWrt 端
ssh root@<OPENWRT_LAN_IP> 'wg show'

# DGX 端（需 sudo）
sudo wg show
```

---

## 故障排查

### 症状：域名返回 502

**排查路径：**

```
502 → NPM 连不到 <DGX_WG_IP>:18789
  → WireGuard 隧道是否通？ ping <DGX_WG_IP>
    → 是否 WG endpoint IP 变了？ (路由器 PPPoE 动态 IP)
      → DGX: sudo wg set wg0 peer <pubkey> endpoint <新IP>:51820
    → DGX 上 18789 是否在监听？ curl 127.0.0.1:18789
      → socat 进程是否在？ ss -tlnp | grep 18789
      → NodePort 是否在？ docker exec ... kubectl get svc nemoclaw-ui -n openshell
        → 沙箱内 gateway 是否在运行？ kubectl exec my-assistant -- ss -tlnp | grep 18789
```

**常见原因及修复：**

| 原因 | 修复 |
|------|------|
| WireGuard endpoint IP 过期（路由器重拨） | DGX: `sudo wg set wg0 peer <pubkey> endpoint <新IP>:51820` |
| socat 端口转发丢失 | `nohup socat TCP-LISTEN:18789,bind=0.0.0.0,reuseaddr,fork TCP:<K3S_CONTAINER_IP>:30089 &` |
| NodePort service 丢失 | watchdog 自动重建，或手动 `kubectl apply` |
| 沙箱内 gateway 挂了 | watchdog 自动重启（Patch 5 的 node wrapper 确保 env 正确），或手动: `nohup openclaw gateway run --bind lan --verbose > /sandbox/.openclaw-data/gateway.log 2>&1 &` |
| iptables DNAT 规则丢失 | watchdog 自动修复，或手动添加 DNAT + FORWARD + MASQUERADE |
| 沙箱 Pod 被重建，gateway 未启动 | 重新 onboard（见下方） |
| OpenWrt 防火墙规则丢失 | `ssh root@<OPENWRT_LAN_IP> '/etc/firewall.dgx'` |

> **注意：** 大部分故障由 `nemoclaw-watchdog.sh` (cron 每 5 分钟) 自动修复，
> 无需人工介入。查看 `/home/xsuper/nemoclaw-watchdog.log` 了解自动恢复历史。

### 症状：沙箱崩溃（sleep infinity / handshake verification failed）

NemoClaw 沙箱状态不持久化。Pod 重建后 gateway 不会自动恢复。

**唯一可靠的修复方式 — 重新 onboard：**

```bash
ssh -p 6090 xsuper@<DGX_PUBLIC_IP>
source ~/.nvm/nvm.sh

# 清理旧状态
openshell forward stop 18789 2>/dev/null
openshell sandbox delete my-assistant

# 重新部署
export NVIDIA_API_KEY='<YOUR_NVIDIA_API_KEY>'
export NEMOCLAW_PROVIDER=build
export NEMOCLAW_SANDBOX_NAME=my-assistant
export CHAT_UI_URL=https://nemoclaw.your-domain.com
nemoclaw onboard --non-interactive
```

Onboard 完成后会输出新的 token URL，注意保存。

### 症状：webchat 返回 "LLM request timed out"

**排查路径：**

```
LLM timeout → 沙箱内是否有多个 gateway 进程？
  → kubectl exec ... -- sh -c 'for p in $(ls /proc/ | grep -E "^[0-9]+$"); do
       cat /proc/$p/cmdline 2>/dev/null | grep -q openclaw-gateway && echo PID=$p
     done'
  → 多个 gateway？ → 检查哪个进程持有端口 18789
     → ss -tlnp | grep 18789  → 是否有 BOOTSTRAP=1？
       → 没有 → node wrapper 缺失（Patch 5），或 wrapper 后 gateway 还没重启
  → 只有一个 gateway？ → 检查 fetch() 是否能到 inference.local
     → node -e "fetch('https://inference.local/v1/models').then(r=>console.log(r.status))"
       → fetch failed → HTTPS_PROXY 未设置（旧版 bootstrap 删了它）
       → TLS error → NODE_EXTRA_CA_CERTS 未设置
```

**常见原因及修复：**

| 原因 | 修复 |
|------|------|
| openshell-sandbox 自动重启了一个不带 env 的 gateway（"ghost gateway"） | 部署 node wrapper（Patch 5）然后杀掉所有 gateway 让它重新启动 |
| 旧版 bootstrap 删除了 `HTTPS_PROXY`，`fetch()` 无代理 | 更新 bootstrap 为新版（保留 `HTTPS_PROXY`，用 `axios.defaults.proxy=false`） |
| watchdog 重启了无 env 的 gateway | 更新 watchdog 脚本加上环境变量 |
| `NODE_EXTRA_CA_CERTS` 未设置 | 设置为 `/etc/openshell-tls/ca-bundle.pem` |

> **关键经验：** 手动通过 `openclaw agent --agent main --message "hi"` 测试 LLM 时，
> CLI 会回退到 "embedded" 模式（直接调 LLM，不经 gateway），可能成功但不代表 webchat 正常。
> webchat 流量走 NodePort → `0.0.0.0:18789`（可能被 ghost gateway 接管），
> 而 CLI 走 `ws://127.0.0.1:18789`（可能连到不同的 gateway）。

### 症状：DNS 不生效（NXDOMAIN）

代理服务劫持了 53 端口。添加/修改 dnsmasq 记录后需要重启代理服务：

```bash
ssh root@<OPENWRT_LAN_IP> '/etc/init.d/<proxy-service> restart'
```

### 症状：Docker 镜像拉取失败（Registry 不可达）

DGX 通过 WireGuard 使用 Ubuntu 上的 registry mirror 加速 Registry 访问。

确认 mirror 容器在运行：
```bash
# 在 Ubuntu 上
docker ps | grep registry
# 应看到 registry-ghcr (5001) 和 registry-dockerhub (5002)
```

确认 DGX Docker daemon 配置：
```bash
# 在 DGX 上
cat /etc/docker/daemon.json
# 应有 "registry-mirrors": ["http://<HOME_WG_IP>:5001"]
```

### 症状：服务频繁卡死（database is locked）

**根因：** k3s 跑在 Docker 容器内，Kubernetes watch 长连接不稳定 → 重连风暴 →
SQLite 并发写入冲突 → 数据库锁死 → 服务僵死（进程在、端口通、功能挂）。

**已实施的缓解措施：**

1. **SQLite WAL 模式**（持久化，已生效）— 读写不互斥，大幅降低锁死概率
2. **Docker restart policy = unless-stopped** — 主机重启后容器自动恢复
3. **Watchdog cron** (`/home/xsuper/nemoclaw-watchdog.sh`, 每 5 分钟) — 自动检测并修复:
   - openclaw gateway 进程（带 `NODE_EXTRA_CA_CERTS` + `NODE_OPTIONS` 启动，见 Patch 5）
   - K8s NodePort service
   - socat 端口转发
   - iptables DNAT 规则
   - SQLite 锁死监控
   - 健康检查使用 `--noproxy '*'` 避免 DGX host 的代理环境变量干扰

**根治方案（如仍频繁卡死）：** 将 k3s 从 Docker 容器搬到 DGX 主机直接运行，
消除中间的虚拟网络层。需重新部署 Helm chart、TLS 证书和 NVIDIA device plugin。

---

## 飞书 Bot 接入

NemoClaw 沙箱内运行的 OpenClaw 支持飞书频道。但由于沙箱的网络策略和文件权限限制，
配置过程不能像普通 OpenClaw 那样直接改文件重启，需要从 k8s 层面操作。

### 前提条件

1. 飞书开放平台已创建企业自建应用（获得 App ID / App Secret）
2. 应用已启用机器人能力
3. 事件订阅已配置为**长连接（WebSocket）**模式，并添加 `im.message.receive_v1`
4. 应用已发布

### 第一步：修改 openclaw.json（通过 kubectl exec）

沙箱内的 `openclaw.json` 文件权限为 `root:root 444`，sandbox 用户无法直接写入。
必须通过 kubectl exec（以 root 身份）修改：

```bash
ssh -p 6090 xsuper@<DGX_PUBLIC_IP>

docker exec openshell-cluster-nemoclaw kubectl exec -n openshell my-assistant -- python3 -c "
import json, os

path = '/sandbox/.openclaw/openclaw.json'
with open(path) as f:
    d = json.load(f)

# 添加飞书频道
d['channels']['feishu'] = {
    'enabled': True,
    'dmPolicy': 'pairing',
    'accounts': {
        'main': {
            'appId': '<YOUR_APP_ID>',
            'appSecret': '<YOUR_APP_SECRET>'
        }
    }
}

# 添加 binding：飞书 main 账号 → main agent
d['bindings'] = d.get('bindings', [])
d['bindings'].append({
    'agentId': 'main',
    'match': {'channel': 'feishu', 'accountId': 'main'}
})

# 修复 trustedProxies（k8s 内网必须加入，否则反向代理的请求会被拒绝）
d['gateway']['trustedProxies'] = ['127.0.0.1', '::1', '10.42.0.0/16', '172.18.0.0/16']

os.chmod(path, 0o644)
with open(path, 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
os.chmod(path, 0o444)
print('OK')
"
```

### 第二步：修复文件权限

OpenClaw 进程在沙箱内以 uid 998（`sandbox` 用户）运行，需要确保文件 ownership 正确：

```bash
docker exec openshell-cluster-nemoclaw kubectl exec -n openshell my-assistant -- sh -c '
chown -R 998:998 /sandbox/.openclaw/ /sandbox/.openclaw-data/
chmod 700 /sandbox/.openclaw
chmod 600 /sandbox/.openclaw/openclaw.json
mkdir -p /sandbox/.openclaw-data/credentials
chown 998:998 /sandbox/.openclaw-data/credentials
chmod 700 /sandbox/.openclaw-data/credentials
'
```

### 第三步：运行 openclaw doctor

Doctor 会自动修复配置格式问题（如把 `dmPolicy` 移入正确层级）：

```bash
# SSH 进沙箱
source ~/.nvm/nvm.sh
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o 'ProxyCommand=openshell ssh-proxy --gateway-name nemoclaw --name my-assistant' \
  sandbox@openshell-my-assistant

# 在沙箱内执行
openclaw doctor --fix
```

### 第四步：添加飞书网络策略

NemoClaw 沙箱通过 openshell 代理强制执行网络策略，默认不允许访问 `open.feishu.cn`。
需要把飞书域名加入网络白名单。

在 DGX 宿主机上导出当前策略并追加 feishu：

```bash
source ~/.nvm/nvm.sh

# 查看当前策略
nemoclaw my-assistant policy-list

# 创建包含飞书域名的新策略文件
cat > /tmp/policy-with-feishu.yaml << 'YAML'
version: 1
filesystem_policy:
  include_workdir: true
  read_only:
    - /usr
    - /lib
    - /proc
    - /dev/urandom
    - /app
    - /etc
    - /var/log
    - /sandbox/.openclaw
  read_write:
    - /sandbox
    - /tmp
    - /dev/null
    - /sandbox/.openclaw-data
landlock:
  compatibility: best_effort
process:
  run_as_user: sandbox
  run_as_group: sandbox
network_policies:
  # ... 保留所有原有策略（claude_code, clawhub, discord, github 等）...
  feishu:
    name: feishu
    endpoints:
      - host: open.feishu.cn
        port: 443
        access: full
      - host: open.larksuite.com
        port: 443
        access: full
      - host: msg-frontier.feishu.cn
        port: 443
        access: full
      - host: msg-frontier.larksuite.com
        port: 443
        access: full
    binaries:
      - path: /usr/local/bin/node
      - path: /usr/local/bin/node.real
      - path: /usr/local/bin/openclaw
YAML

# 应用策略
openshell policy set my-assistant --policy /tmp/policy-with-feishu.yaml --wait
```

> **重要：** 策略文件必须包含所有原有的 `network_policies`（`claude_code`, `nvidia` 等），
> 不能只写 feishu，否则会覆盖掉其他策略。用 `nemoclaw my-assistant status` 查看完整策略再追加。

### 第五步：创建 proxy-bootstrap.js

沙箱的 openshell 代理做 TLS MITM，且 axios 的代理实现有 bug。需要创建 bootstrap
脚本修复（详见 Patch 4）。

### 第六步：重启 Gateway 并验证

```bash
# SSH 进沙箱后
pkill -f "openclaw gateway" 2>/dev/null
sleep 2
NODE_EXTRA_CA_CERTS=/etc/openshell-tls/ca-bundle.pem \
NODE_OPTIONS="--require /sandbox/.openclaw/proxy-bootstrap.js" \
nohup openclaw gateway run --verbose > /sandbox/.openclaw-data/gateway.log 2>&1 &
sleep 8

# 验证 gateway
openclaw gateway probe

# 验证飞书频道状态
openclaw status | grep -A3 Feishu
# 预期输出：Feishu │ ON │ OK │ configured · accounts 1/2
```

### 飞书 Bot 故障排查

| 症状 | 原因 | 修复 |
|------|------|------|
| `stream has been aborted` (axios) | axios 内建代理不走 CONNECT 隧道 | 部署 proxy-bootstrap.js（Patch 4） |
| `getaddrinfo EAI_AGAIN open.feishu.cn` | node wrapper 未设置 `HTTPS_PROXY` 或 bootstrap 错误清除了代理变量 | 确认 wrapper 设置 `HTTPS_PROXY=http://10.200.0.1:3128` |
| `ws connect failed` (WebSocket) | `msg-frontier.feishu.cn` 不在网络策略白名单 | 策略中添加 `msg-frontier.feishu.cn:443`（见第四步） |
| `SSL certificate problem: self-signed certificate` | Node.js 不信任 openshell 自签 CA | 设置 `NODE_EXTRA_CA_CERTS=/etc/openshell-tls/ca-bundle.pem` |
| `LLM request timed out` | inference.local 的 HTTPS 被 TLS 验证拒绝 | 同上，设置 `NODE_EXTRA_CA_CERTS` |
| `LLM request timed out` + `fetch failed` | 旧版 bootstrap 删除了 `HTTPS_PROXY`，导致 `fetch()`（undici）无代理 | 更新 bootstrap：保留 `HTTPS_PROXY`，改用 `axios.defaults.proxy=false` 禁用 axios 代理 |
| `EACCES: permission denied, open openclaw.json` | 文件 ownership 不是 sandbox(998) | 第二步修复权限 |
| `feishu[main]: bot open_id resolved: unknown` | bootstrap 未生效，HTTP API 调用失败 | 确认 gateway 启动时带了 `NODE_OPTIONS` |
| WebSocket 一直重连 | 飞书应用未启用长连接或未发布 | 飞书开放平台检查事件订阅和发布状态 |
| `Failed to establish tunnel...403 Forbidden` | openshell 代理拒绝 CONNECT 到未白名单的域名 | 将目标域名加入 network_policies |
| `bot info probe timed out` (GET hang) | HTTP keep-alive 在透明代理上复用连接时 hang | bootstrap 中设 `https.globalAgent.keepAlive = false` |
| `Proxy headers detected from untrusted address` | `trustedProxies` 未包含 k8s 网络 | 第一步中已修复 |
| `FORWARD blocked: internal IP without allowed_ips` | openclaw.json 直连 Ollama (`host.openshell.internal`) 被拦截 | **正确做法：** 用 `openshell provider` + `inference set` 路由（Patch 8），不直连内部 IP |
| `CONNECT blocked: internal address` | 同上，HTTPS CONNECT 隧道到内部 IP 被拒 | 同上 |
| `landlock policy cannot be changed on a live sandbox` | 试图修改 network_policies 放行 Ollama | **不需要改策略：** 用 `openshell inference set` 路由到 Ollama（Patch 8） |
| `LLM request failed: network connection error` + fallback 到 Nemotron | Ollama 模型启用 reasoning，first-token ~20s 超过 gateway 超时 | 创建 `gpt-oss:120b-fast` (think:off) + `openshell inference set` 路由 |
| `FailoverError: LLM request timed out` (web UI 专属, 135s) | Ollama 模型 keep_alive 到期后被卸载（默认 5 分钟），65GB 冷加载 20s+ 超过 gateway 超时 | `sudo snap set ollama keep-alive=-1` + systemd override `OLLAMA_KEEP_ALIVE=-1`；NPM 添加 `proxy_buffering off` |
| Web UI 正常但流式响应延迟或中断 | NPM 默认开启 proxy_buffering，SSE/WebSocket 流式数据被缓冲 | `/data/nginx/custom/server_proxy.conf` 中设 `proxy_buffering off; proxy_cache off;` |

---

## 沙箱内 OpenClaw 配置 Patch 记录

以下是在 NemoClaw 沙箱中对 OpenClaw 做过的配置修改，沙箱重建后需要重新应用。

### Patch 1: trustedProxies（解决 "device identity required"）

**问题：** 通过 HTTPS 域名访问 OpenClaw 控制台时报 "device identity required"，
Gateway 日志显示 "Proxy headers detected from untrusted address"。

**根因：** 请求经过 NPM → WireGuard → iptables DNAT → K3s NodePort → Pod，
到达 gateway 时源 IP 是 k8s pod 网络 `10.42.0.1`，
但 `trustedProxies` 只有 `127.0.0.1` 和 `::1`，代理头被忽略。

**修复：** 在 `gateway.trustedProxies` 中加入 k8s 和 Docker 内网：

```json
"trustedProxies": ["127.0.0.1", "::1", "10.42.0.0/16", "172.18.0.0/16"]
```

### Patch 2: 设备配对（approve device pairing）

**问题：** Gateway 运行后 probe 报 "pairing required"。

**修复：** 在沙箱内运行：

```bash
openclaw devices list
openclaw devices approve --latest
```

之后 `openclaw gateway probe` 应显示 `Reachable: yes`。

### Patch 3: Gateway 启动方式（无 systemd 环境）

**问题：** 沙箱容器内没有 systemd，`openclaw gateway` / `openclaw gateway restart` 都无法工作。

**修复：** 使用前台运行命令（通过 nohup 放后台），**必须带上 TLS 修复的环境变量**（见 Patch 4），
且用 `--bind lan` 监听 `0.0.0.0`（NodePort 流量不经过 loopback）：

```bash
NODE_EXTRA_CA_CERTS=/etc/openshell-tls/ca-bundle.pem \
NODE_OPTIONS="--require /sandbox/.openclaw/proxy-bootstrap.js" \
nohup openclaw gateway run --bind lan --verbose > /sandbox/.openclaw-data/gateway.log 2>&1 &
```

> **注意：**
> - `openclaw gateway run` 是前台命令，需要用 nohup 放到后台
> - `--bind lan` 让 gateway 监听 `0.0.0.0:18789`，否则 NodePort 的流量（来自 pod IP `10.42.0.25`）无法到达 loopback-only 的 gateway
> - Pod 重建后 gateway 进程会丢失，需要重新启动
> - 不带 `NODE_EXTRA_CA_CERTS` 和 `NODE_OPTIONS` 启动会导致 LLM timeout 和飞书连接失败
> - 部署了 node wrapper（Patch 5）后，手动启动时可以省略环境变量（wrapper 自动注入）

### Patch 4: openshell 代理 TLS 修复（解决 LLM timeout + 飞书连接失败）

**问题：** 沙箱内所有 HTTPS 流量必须经过 openshell 代理 (`http://10.200.0.1:3128`)，
代理做 TLS MITM 拦截并用自签 CA (`/etc/openshell-tls/openshell-ca.pem`) 重新签名。
Node.js 默认不信任此 CA，导致：
- webchat 发消息返回 "LLM request timed out"（到 `inference.local` 的 HTTPS 被拒）
- 飞书 SDK 报 `stream has been aborted`（axios 的内建代理处理有 bug）

**根因分析：**

```
沙箱 Node.js 进程
  ↓ HTTPS 请求
openshell HTTP 代理 (10.200.0.1:3128)
  ↓ CONNECT 隧道 → TLS MITM → 用 openshell-ca.pem 签名
目标服务器 (inference.local / open.feishu.cn)
```

三个独立问题：
1. **TLS 证书不信任**：Node.js 不认 openshell 自签 CA → 所有 HTTPS 请求失败
2. **axios 代理 bug**：axios 读取 `HTTPS_PROXY` 环境变量后不走 CONNECT 隧道，
   而是发送纯 HTTP 请求，导致 `stream has been aborted`
3. **fetch() 代理缺失**：OpenClaw 的 LLM 客户端使用 Node.js 22 内置 `fetch()`（基于 undici），
   如果删除 `HTTPS_PROXY` 则 `fetch()` 无法走代理，导致 "LLM request timed out"

**修复：** 创建 proxy-bootstrap.js，通过 `NODE_OPTIONS` 预加载：

1. 设置 `NODE_EXTRA_CA_CERTS=/etc/openshell-tls/ca-bundle.pem` 信任 openshell CA
2. monkey-patch `https.request`，用 `https-proxy-agent` 走正确的 CONNECT 隧道
3. **保留** `HTTPS_PROXY` 环境变量供 `fetch()` 使用（配合 `NODE_USE_ENV_PROXY=1`）
4. 通过 `Module.prototype.require` hook 设置 `axios.defaults.proxy = false`，阻止 axios 使用其有 bug 的内建代理
5. 删除 ws 库注入的 `createConnection`，让 proxy agent 接管连接建立

```bash
# 在 DGX 宿主机创建 bootstrap 脚本
docker exec openshell-cluster-nemoclaw kubectl -n openshell exec my-assistant -- sh -c 'cat > /sandbox/.openclaw/proxy-bootstrap.js << '\''ENDSCRIPT'\''
const { HttpsProxyAgent } = require("/usr/local/lib/node_modules/openclaw/node_modules/pac-proxy-agent/node_modules/https-proxy-agent");
const https = require("https");

const proxyUrl = process.env.__OPENCLAW_PROXY_URL
  || process.env.HTTPS_PROXY || process.env.HTTP_PROXY
  || process.env.https_proxy || process.env.http_proxy;
const noProxyStr = process.env.NO_PROXY || process.env.no_proxy || "";
const noProxyList = noProxyStr.split(",").map(s => s.trim().toLowerCase()).filter(Boolean);

function shouldBypassProxy(hostname) {
  const h = (hostname || "").toLowerCase();
  return noProxyList.some(np => h === np || h.endsWith("." + np) || np === "*");
}

if (proxyUrl) {
  const proxyAgent = new HttpsProxyAgent(proxyUrl);

  // 1) patch https.request — 处理 axios / ws / 其他直接调用
  const origHttpsRequest = https.request;
  https.request = function patchedHttpsRequest(urlOrOpts, optsOrCb, cb) {
    let opts, callback;
    if (typeof urlOrOpts === "string" || urlOrOpts instanceof URL) {
      const parsed = typeof urlOrOpts === "string" ? new URL(urlOrOpts) : urlOrOpts;
      opts = typeof optsOrCb === "object" ? { ...optsOrCb } : {};
      opts.hostname = opts.hostname || parsed.hostname;
      opts.port = opts.port || parsed.port;
      opts.path = opts.path || parsed.pathname + parsed.search;
      opts.protocol = opts.protocol || parsed.protocol;
      opts.method = opts.method || "GET";
      callback = typeof optsOrCb === "function" ? optsOrCb : cb;
    } else {
      opts = { ...urlOrOpts };
      callback = optsOrCb;
    }
    if (!shouldBypassProxy(opts.hostname || opts.host)) {
      if (!opts.agent || opts.agent === https.globalAgent) {
        opts.agent = proxyAgent;
      }
      delete opts.createConnection;
    }
    return origHttpsRequest.call(https, opts, callback);
  };
  https.get = function patchedHttpsGet(urlOrOpts, optsOrCb, cb) {
    const req = https.request(urlOrOpts, optsOrCb, cb);
    req.end();
    return req;
  };

  // 2) 禁用 axios 内建代理（它生成错误的 HTTP 请求而非 CONNECT 隧道）
  const Module = require("module");
  const origRequire = Module.prototype.require;
  Module.prototype.require = function patchedRequire(id) {
    const result = origRequire.call(this, id);
    if (id === "axios" || (typeof id === "string" && id.endsWith("/axios"))) {
      const ax = result.default || result;
      if (ax && ax.defaults && ax.defaults.proxy !== false) {
        ax.defaults.proxy = false;
      }
    }
    return result;
  };

  // 3) 保留 HTTPS_PROXY 供 fetch() 使用（undici 通过 NODE_USE_ENV_PROXY=1 读取）
  process.env.__OPENCLAW_PROXY_URL = proxyUrl;
  process.env.__OPENCLAW_PROXY_BOOTSTRAP = "1";
}
ENDSCRIPT
chown 998:998 /sandbox/.openclaw/proxy-bootstrap.js
chmod 644 /sandbox/.openclaw/proxy-bootstrap.js'
```

> **关键变化**：旧版本删除了 `HTTPS_PROXY` 环境变量以绕过 axios bug，但这同时导致
> `fetch()`（Node.js 22 的 undici 实现）无法走代理，LLM 请求直接报 "fetch failed"。
> 新版本保留 `HTTPS_PROXY` 供 `fetch()` 使用，改为通过 `Module.prototype.require` hook
> 将 `axios.defaults.proxy = false` 来阻止 axios 使用其有 bug 的代理逻辑。

Gateway 启动时必须带上这两个环境变量：

```bash
NODE_EXTRA_CA_CERTS=/etc/openshell-tls/ca-bundle.pem \
NODE_OPTIONS="--require /sandbox/.openclaw/proxy-bootstrap.js" \
nohup openclaw gateway run --verbose > /sandbox/.openclaw-data/gateway.log 2>&1 &
```

**验证（三种 HTTP 客户端都必须通过）：**

```bash
ENV_OPTS='NODE_EXTRA_CA_CERTS=/etc/openshell-tls/ca-bundle.pem NODE_OPTIONS="--require /sandbox/.openclaw/proxy-bootstrap.js"'

# 1) fetch() — LLM 推理（OpenClaw 的 LLM 客户端用 fetch）
eval $ENV_OPTS node -e "
fetch('https://inference.local/v1/chat/completions',{method:'POST',
  headers:{'Content-Type':'application/json','Authorization':'Bearer unused'},
  body:JSON.stringify({model:'nvidia/nemotron-3-super-120b-a12b',
    messages:[{role:'user',content:'say ok'}],max_tokens:5})})
.then(r=>{console.log('FETCH:',r.status);return r.text()})
.then(t=>console.log(t.substring(0,100)))
.catch(e=>console.log('ERR:',e.message,e.cause?.message));
setTimeout(()=>process.exit(2),30000);
"

# 2) axios — 飞书 SDK
eval $ENV_OPTS node -e "
const ax=require('/usr/local/lib/node_modules/openclaw/node_modules/axios');
(ax.default||ax).post('https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal',
  {app_id:'<YOUR_FEISHU_APP_ID>',app_secret:'YOUR_SECRET'})
.then(r=>console.log('AXIOS:',r.status))
.catch(e=>console.log('ERR:',e.message));
"

# 3) 端到端 — 通过 openclaw CLI 发送消息
openclaw agent --agent main --message "say hi" --timeout 60000
```

### Patch 5: node wrapper（解决 openshell-sandbox 自动重启的 gateway 缺失环境变量）

**问题：** openshell-sandbox（沙箱的 PID 1 init 进程）会自动检测并重启 `openclaw gateway`。
但它直接调用 `node` 二进制而非 `openclaw` CLI，因此不继承我们手动设置的
`NODE_EXTRA_CA_CERTS`、`NODE_OPTIONS`、`HTTPS_PROXY` 等环境变量。
结果：自动重启的 gateway 绑定到 `0.0.0.0:18789`，抢走 NodePort 流量，
但没有 proxy bootstrap，导致 LLM timeout 和飞书连接失败。

**根因分析：**

```
openshell-sandbox (PID 1)
  ↓ exec("/usr/local/bin/node", ["openclaw.mjs", "gateway", "run", "--bind", "lan"])
  ↓ 不经过 shell，不读取 .profile/.bashrc，不继承 SSH 会话的环境变量
openclaw-gateway (无 NODE_OPTIONS / HTTPS_PROXY)
  ↓ fetch("https://inference.local/v1/...") → DNS 失败 / TLS 拒绝
"LLM request timed out"
```

**补充问题：** DGX 宿主机上的 `nemoclaw-watchdog.sh`（cron 每 5 分钟）也会通过
`kubectl exec` 重启 gateway，同样不带环境变量。

**修复：** 将 `/usr/local/bin/node` 替换为 wrapper 脚本，让所有 Node.js 进程自动继承正确的环境变量：

```bash
docker exec openshell-cluster-nemoclaw kubectl -n openshell exec my-assistant -- sh -c '
# 备份真实 node 二进制
cp /usr/local/bin/node /usr/local/bin/node.real

# 创建 wrapper
cat > /usr/local/bin/node << '\''NODEWRAP'\''
#!/bin/sh
export NODE_EXTRA_CA_CERTS=/etc/openshell-tls/ca-bundle.pem
if [ -z "$__OPENCLAW_NODE_WRAPPED" ]; then
  export __OPENCLAW_NODE_WRAPPED=1
  export HTTPS_PROXY=http://10.200.0.1:3128
  export HTTP_PROXY=http://10.200.0.1:3128
  export NO_PROXY=127.0.0.1,localhost,::1,host.openshell.internal
  export NODE_OPTIONS="--require /sandbox/.openclaw/proxy-bootstrap.js ${NODE_OPTIONS:-}"
fi
exec /usr/local/bin/node.real "$@"
NODEWRAP
chmod +x /usr/local/bin/node
'
```

**`__OPENCLAW_NODE_WRAPPED` 守卫**：防止子进程重复设置 `NODE_OPTIONS`（避免双重 `--require`）。

**watchdog 更新：** 同时需要更新 DGX 宿主机上的 `/home/xsuper/nemoclaw-watchdog.sh`，
将 step 4 的 gateway 启动命令改为带环境变量版本：

```bash
# watchdog step 4 (旧)
$KUBECTL exec my-assistant -n openshell -- sh -c \
  'export HOME=/sandbox && nohup openclaw gateway run --bind lan --port 18789 > /tmp/openclaw-gateway.log 2>&1 &'

# watchdog step 4 (新 — 有了 node wrapper 后实际上不需要显式设置，但作为双保险)
$KUBECTL exec my-assistant -n openshell -- sh -c '
  export HOME=/sandbox
  export NODE_EXTRA_CA_CERTS=/etc/openshell-tls/ca-bundle.pem
  export NODE_OPTIONS="--require /sandbox/.openclaw/proxy-bootstrap.js"
  nohup openclaw gateway run --bind lan --port 18789 > /sandbox/.openclaw-data/gateway.log 2>&1 &
'
```

**验证 node wrapper 生效：**

```bash
# 在沙箱内运行
node -e "console.log({
  bootstrap: process.env.__OPENCLAW_PROXY_BOOTSTRAP,
  ca: process.env.NODE_EXTRA_CA_CERTS,
  proxy: process.env.HTTPS_PROXY,
  wrapped: process.env.__OPENCLAW_NODE_WRAPPED
})"
# 期望输出: { bootstrap: '1', ca: '/etc/openshell-tls/ca-bundle.pem', proxy: 'http://10.200.0.1:3128', wrapped: '1' }
```

> **注意：** 沙箱 Pod 重建后，node wrapper 会丢失（/usr/local/bin/node 恢复为原始二进制）。
> 必须在恢复流程中重新执行 wrapper 部署步骤。

### Patch 6: 飞书 WebSocket 域名白名单（解决 "ws connect failed"）

**问题：** 飞书 WS 连接一直报 `ws connect failed`。飞书 SDK 先调
`open.feishu.cn/callback/ws/endpoint` 获取 WS URL（成功），但返回的 WebSocket
地址是 `wss://msg-frontier.feishu.cn/...`，该域名不在 openshell 网络策略中被拒绝。

**根因链：**
1. `Lark.WSClient` 内部 `pullConnectConfig()` 调用 `open.feishu.cn`（已白名单）→ 200
2. 返回的 WS URL 指向 `msg-frontier.feishu.cn`（未白名单）
3. `ws` 库通过 `HttpsProxyAgent` 发 CONNECT 隧道 → openshell 代理返回 403

**修复：** 将 `msg-frontier.feishu.cn` 和 `msg-frontier.larksuite.com` 添加到
feishu 网络策略（见第四步）。更新后的策略版本为 v6。

### Patch 7: 文件 ownership 修复（原 Patch 4）

**问题：** 通过 kubectl exec (root) 修改 `openclaw.json` 后，文件变成 `root:root`，
OpenClaw 进程 (uid 998/sandbox) 无法读取，报 `EACCES`。

**修复：**

```bash
docker exec openshell-cluster-nemoclaw kubectl exec -n openshell my-assistant -- sh -c '
chown -R 998:998 /sandbox/.openclaw/ /sandbox/.openclaw-data/
chmod 700 /sandbox/.openclaw
chmod 600 /sandbox/.openclaw/openclaw.json
'
```

### Patch 8: 接入本地 Ollama 推理（gpt-oss:120b）

> **参考：** [NVIDIA Build — OpenShell on DGX Spark](https://build.nvidia.com/spark/openshell/instructions)

**问题：** DGX Spark 上通过 snap 安装了 Ollama，运行着 `gpt-oss:120b` 模型（116.8B 参数，MXFP4 量化，~65GB）。
需要让 NemoClaw 沙箱能调用该模型。

**正确方案（官方推荐）：** 通过 OpenShell 的 `provider` + `inference set` 机制，
将 `inference.local` 路由到本地 Ollama。**不需要**修改 openshell 网络策略或 `allowed_ips`，
因为 inference 路由由 gateway 容器外部处理，再注入沙箱。

> **⚠️ 之前的错误方案：** 直接在 `openclaw.json` 中配置 `ollama` provider 指向
> `http://host.openshell.internal:11434/v1`，然后试图通过修改 `network_policies`
> 添加 `allowed_ips` 来放行内部 IP。这条路行不通，因为 `landlock policy cannot be
> changed on a live sandbox`，且内部 IP 连接会被 openshell 代理的安全检查拦截。

**修复步骤：**

**1) 让 Ollama 监听所有接口**

snap 安装的 Ollama 有自己的配置机制，需要通过 systemd override 设置：

```bash
# systemd override 确保环境变量生效
sudo mkdir -p /etc/systemd/system/snap.ollama.ollama.service.d

# OLLAMA_HOST 让 Ollama 监听所有接口
sudo tee /etc/systemd/system/snap.ollama.ollama.service.d/override.conf << 'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
EOF

# OLLAMA_KEEP_ALIVE 让模型永不卸载，避免冷加载超时
sudo tee /etc/systemd/system/snap.ollama.ollama.service.d/keep-alive.conf << 'EOF'
[Service]
Environment=OLLAMA_KEEP_ALIVE=-1
EOF

sudo systemctl daemon-reload
sudo snap restart ollama

# 验证
ss -tlnp | grep 11434
# 应显示 *:11434（而非 127.0.0.1:11434）
```

**2) 预加载模型并设置 context window**

NVIDIA 官方指南推荐 32768 tokens context window。预加载模型到 GPU 并设为永不卸载：

```bash
# 创建无 thinking 变体（避免 gateway 超时）
# 原版模型默认启用 reasoning，first-token 延迟 ~20s，超过 gateway 的内部超时
curl -s http://localhost:11434/api/create -d '{
  "model": "gpt-oss:120b-fast",
  "from": "gpt-oss:120b",
  "params": {"num_ctx": 32768, "think": "off"}
}'

# 预加载模型（32K context, 永不卸载）
curl -s http://localhost:11434/api/generate -d '{
  "model": "gpt-oss:120b-fast",
  "prompt": "",
  "keep_alive": -1,
  "options": {"num_ctx": 32768}
}'

# 验证
ollama ps
# 期望: gpt-oss:120b-fast  66 GB  100% GPU  32768  Forever
```

> **Context window 选择：** 128GB 统一内存的 DGX Spark 上，`gpt-oss:120b` (~65GB) 配 32K context
> 约占 66GB，剩余 ~62GB 供系统和其他进程使用。如需更长上下文可增大 `num_ctx`，
> 但注意用 `nvidia-smi` 监控内存，避免 OOM。

**3) 创建 OpenShell inference provider**

找到 DGX Spark 的本机 IP（**不能用** `localhost`/`127.0.0.1`，gateway 在 Docker 容器内）：

```bash
MACHINE_IP=$(hostname -I | awk '{print $1}')  # e.g. <DGX_LAN_IP>
echo "Machine IP: $MACHINE_IP"

openshell provider create --gateway nemoclaw \
    --name local-ollama \
    --type openai \
    --credential OPENAI_API_KEY=not-needed \
    --config OPENAI_BASE_URL=http://${MACHINE_IP}:11434/v1

# 验证
openshell provider list --gateway nemoclaw
```

**4) 配置 inference 路由**

将 `inference.local` 指向本地 Ollama：

```bash
openshell inference set --gateway nemoclaw \
    --provider local-ollama \
    --model gpt-oss:120b-fast

# 验证
openshell inference get --gateway nemoclaw
# 期望输出:
#   Provider: local-ollama
#   Model: gpt-oss:120b-fast
#   Validated Endpoints: http://<DGX_LAN_IP>:11434/v1/chat/completions (openai_chat_completions)
```

> **注意：** 如果验证失败报 `failed to verify inference endpoint`，加 `--no-verify` 跳过。
> 确保 Ollama 在运行且监听所有接口。

**5) 更新 openclaw.json — 使用 inference.local（不再直连 Ollama）**

`openclaw.json` 中的 `inference` provider 指向 `https://inference.local/v1`，
OpenShell 自动将 `inference.local` 路由到步骤 4 设置的 `local-ollama` provider。
不需要（也不应该）在 `openclaw.json` 中添加单独的 `ollama` provider。

```json
{
  "models": {
    "mode": "merge",
    "providers": {
      "inference": {
        "baseUrl": "https://inference.local/v1",
        "apiKey": "unused",
        "api": "openai-completions",
        "models": [
          {
            "id": "gpt-oss:120b-fast",
            "name": "inference/gpt-oss:120b-fast",
            "contextWindow": 32768,
            "maxTokens": 8192
          },
          {
            "id": "nvidia/nemotron-3-super-120b-a12b",
            "name": "inference/nvidia/nemotron-3-super-120b-a12b",
            "contextWindow": 131072,
            "maxTokens": 4096
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "inference/gpt-oss:120b-fast",
        "fallbacks": ["inference/nvidia/nemotron-3-super-120b-a12b"]
      }
    }
  }
}
```

> **关键区别：** 之前的方案在 `openclaw.json` 中配置了 `ollama` provider 直连
> `http://host.openshell.internal:11434/v1`，这需要修改 openshell 网络策略添加
> `allowed_ips`，但策略变更在运行中的沙箱上受限于 `landlock`。
> 新方案通过 `inference.local` 路由，完全绕过了网络策略限制。

**6) 重启 gateway 并验证**

```bash
# 杀掉旧进程
pkill -f "openclaw gateway" 2>/dev/null; pkill -f "openclaw-gateway" 2>/dev/null
sleep 2 && rm -rf /tmp/jiti

# 启动新 gateway
cd /sandbox/.openclaw
nohup openclaw gateway > /tmp/gateway.log 2>&1 &
sleep 5

# 验证 inference.local 到 Ollama 的路由
curl -s --max-time 30 https://inference.local/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-oss:120b-fast","messages":[{"role":"user","content":"say hi"}],"max_tokens":10}' | head -1
# 期望: 200 + JSON 响应，model 字段为 gpt-oss:120b-fast
```

**切换 inference 模型：**

```bash
# 切回 NVIDIA 云端模型
openshell inference set --gateway nemoclaw \
    --provider nvidia-prod \
    --model nvidia/nemotron-3-super-120b-a12b

# 切回本地 Ollama
openshell inference set --gateway nemoclaw \
    --provider local-ollama \
    --model gpt-oss:120b-fast
```

**Ollama 模型管理：**

| 模型 | GPU 内存 | 用途 | 命令 |
|------|----------|------|------|
| gpt-oss:120b-fast | ~66GB | 默认（think:off, 低延迟） | 基于 gpt-oss:120b 创建，参数 `think off` |
| gpt-oss:120b | ~70GB (131K ctx) | 启用 reasoning，first-token ~20s | `ollama pull gpt-oss:120b` |
| gpt-oss:20b | ~12GB | 低延迟交互 | `ollama pull gpt-oss:20b` |
| Nemotron-3-Nano-30B-A3B | ~20GB | NVIDIA 优化 | `ollama pull nemotron-3-nano-30b-a3b` |

> **切换模型：** 用 `openshell inference set` 切换 provider 和 model（推荐），
> 或在 `openclaw.json` 的 `inference` provider 中修改 model id 并重启 gateway。

### 当前 openclaw.json 配置摘要

```json
{
  "models": {
    "mode": "merge",
    "providers": {
      "inference": {
        "baseUrl": "https://inference.local/v1",
        "apiKey": "unused",
        "api": "openai-completions",
        "models": [
          { "id": "gpt-oss:120b-fast", "name": "inference/gpt-oss:120b-fast", "contextWindow": 32768, "maxTokens": 8192 },
          { "id": "nvidia/nemotron-3-super-120b-a12b", "name": "inference/nvidia/nemotron-3-super-120b-a12b", "contextWindow": 131072 }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "inference/gpt-oss:120b-fast",
        "fallbacks": ["inference/nvidia/nemotron-3-super-120b-a12b"]
      }
    }
  },
  "channels": {
    "feishu": {
      "enabled": true,
      "accounts": {
        "main": { "appId": "<YOUR_FEISHU_APP_ID>", "appSecret": "***" }
      }
    }
  },
  "gateway": {
    "controlUi": {
      "allowedOrigins": ["http://127.0.0.1:18789", "https://nemoclaw.your-domain.com"],
      "dangerouslyDisableDeviceAuth": true
    },
    "auth": { "token": "<YOUR_GATEWAY_TOKEN>" },
    "trustedProxies": ["127.0.0.1", "::1", "10.42.0.0/16", "172.18.0.0/16"]
  },
  "bindings": [
    { "agentId": "main", "match": { "channel": "feishu", "accountId": "main" } }
  ],
  "plugins": { "entries": { "feishu": { "enabled": true } } }
}
```

### OpenShell inference 路由配置

LLM 模型通过 `openshell provider` + `openshell inference set` 在 gateway 层面配置，
而非直接在 `openclaw.json` 中添加 provider。`openclaw.json` 中只保留 `inference` provider
指向 `https://inference.local/v1`。

```bash
# 查看当前 inference 路由
openshell inference get --gateway nemoclaw

# 查看所有 provider
openshell provider list --gateway nemoclaw

# 当前 provider 列表:
# NAME          TYPE    CREDENTIAL_KEYS  CONFIG_KEYS
# nvidia-prod   nvidia  1                0          ← NVIDIA 云端 API
# ollama-local  openai  1                1          ← 旧的直连 provider（已弃用）
# local-ollama  openai  1                1          ← 当前使用，指向 <DGX_LAN_IP>:11434/v1
```

### 沙箱重建后的完整恢复流程

沙箱重建（`openshell sandbox delete` + 重新 onboard）后，所有 Patch 丢失。按顺序执行：

```bash
# 1. 重新 onboard（见「故障排查 — 沙箱崩溃」章节）

# 2. 修改 openclaw.json（飞书频道 + trustedProxies）
docker exec openshell-cluster-nemoclaw kubectl exec -n openshell my-assistant -- python3 -c "
# ... 见第一步的脚本 ...
"

# 3. 修复文件权限
docker exec openshell-cluster-nemoclaw kubectl exec -n openshell my-assistant -- sh -c '
chown -R 998:998 /sandbox/.openclaw/ /sandbox/.openclaw-data/
chmod 700 /sandbox/.openclaw && chmod 600 /sandbox/.openclaw/openclaw.json
mkdir -p /sandbox/.openclaw-data/credentials
chown 998:998 /sandbox/.openclaw-data/credentials
'

# 4. SSH 进沙箱运行 doctor
openclaw doctor --fix

# 5. 应用飞书网络策略
openshell policy set my-assistant --policy /tmp/policy-with-feishu.yaml --wait

# 6. 创建 proxy-bootstrap.js（见 Patch 4 的完整脚本）
docker exec openshell-cluster-nemoclaw kubectl -n openshell exec my-assistant -- sh -c '
cat > /sandbox/.openclaw/proxy-bootstrap.js << ... # 见 Patch 4
chown 998:998 /sandbox/.openclaw/proxy-bootstrap.js
'

# 7. 部署 node wrapper（见 Patch 5 — 确保自动重启的 gateway 也有正确 env）
docker exec openshell-cluster-nemoclaw kubectl -n openshell exec my-assistant -- sh -c '
cp /usr/local/bin/node /usr/local/bin/node.real
cat > /usr/local/bin/node << '\''NODEWRAP'\''
#!/bin/sh
export NODE_EXTRA_CA_CERTS=/etc/openshell-tls/ca-bundle.pem
if [ -z "$__OPENCLAW_NODE_WRAPPED" ]; then
  export __OPENCLAW_NODE_WRAPPED=1
  export HTTPS_PROXY=http://10.200.0.1:3128
  export HTTP_PROXY=http://10.200.0.1:3128
  export NO_PROXY=127.0.0.1,localhost,::1,host.openshell.internal
  export NODE_OPTIONS="--require /sandbox/.openclaw/proxy-bootstrap.js ${NODE_OPTIONS:-}"
fi
exec /usr/local/bin/node.real "$@"
NODEWRAP
chmod +x /usr/local/bin/node
'

# 8. 杀掉旧 gateway，让 openshell-sandbox 用新 wrapper 自动重启
# （或手动启动）
nohup openclaw gateway run --bind lan --verbose > /sandbox/.openclaw-data/gateway.log 2>&1 &

# 9. 批准设备配对
openclaw devices approve --latest

# 10. 验证
openclaw gateway probe         # Reachable: yes
openclaw status | grep Feishu  # ON / OK

# 验证 node wrapper 生效
node -e "console.log({bootstrap:process.env.__OPENCLAW_PROXY_BOOTSTRAP, wrapped:process.env.__OPENCLAW_NODE_WRAPPED})"

# 验证三种 HTTP 客户端（fetch / axios / CLI）
node -e "
fetch('https://inference.local/v1/chat/completions',{method:'POST',
  headers:{'Content-Type':'application/json','Authorization':'Bearer unused'},
  body:JSON.stringify({model:'nvidia/nemotron-3-super-120b-a12b',
    messages:[{role:'user',content:'say ok'}],max_tokens:5})})
.then(r=>console.log('fetch LLM:',r.status))
.catch(e=>console.log('ERR:',e.message));
setTimeout(()=>process.exit(2),30000);"

node -e "const a=require('/usr/local/lib/node_modules/openclaw/node_modules/axios');
(a.default||a).post('https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal',
{app_id:'<YOUR_FEISHU_APP_ID>',app_secret:'YOUR_SECRET'}).then(r=>console.log('axios Feishu:',r.status));"

openclaw agent --agent main --message "say hi" --timeout 60000  # 端到端 LLM 测试

# 11. NPM streaming 优化（Ubuntu 服务器上执行）
docker exec nginx-proxy-manager sh -c '
mkdir -p /data/nginx/custom
cat > /data/nginx/custom/server_proxy.conf << NGINX
proxy_buffering off;
proxy_cache off;
proxy_request_buffering off;
add_header X-Accel-Buffering no;
proxy_buffer_size 16k;
proxy_buffers 4 16k;
NGINX
nginx -t && nginx -s reload
'
```

---

## 故障修复实录

### 2026-04-05：级联故障（内存溢出 → 运行时损坏 → 镜像拉取 → 端口配置）

**初始症状**：`https://nemoclaw.your-domain.com` 返回 502，SSH 到 DGX 后发现
`openshell-cluster-nemoclaw` 容器已退出 14 小时。

**故障链**：DGX 内存耗尽 → Docker/containerd 状态损坏 → K3s 容器无法启动 →
强制清理后重新 onboard → 镜像拉取失败（Registry Mirror 未正确配置）→
Gateway 绑定错误 → NodePort/socat/DNAT 缺失 → trustedProxies 不全

**修复耗时**：约 3 小时

#### Layer 1: 宿主机资源（内存耗尽）

**诊断**：

```bash
free -h
docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}"
```

本次 109GB/119GB 已用，`vllm-nvfp4` 容器占 ~38GB。

**修复**（任选一个 Option）：

- **Option A**：停止非关键容器释放内存

  ```bash
  docker stop vllm-nvfp4
  ```

- **Option B**：无容器可停时，清理系统缓存或增加 swap

  ```bash
  sudo sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches'
  ```

#### Layer 2: Docker/Containerd 运行时损坏

**诊断**：`docker ps` 报 "error during connect"，`docker start` 无限 hang。

**修复**（逐级升级）：

- **Option A**：简单重启 Docker

  ```bash
  sudo systemctl restart docker
  ```

- **Option B**：Docker 重启无效，清理运行时状态

  ```bash
  sudo kill -9 $(pgrep -f dockerd) $(pgrep -f containerd-shim) 2>/dev/null
  sudo rm -rf /run/containerd/io.containerd.runtime.v2.task/moby/*
  sudo rm -rf /run/docker/runtime-runc/moby/*
  sudo systemctl restart containerd
  sudo systemctl restart docker
  ```

- **Option C**：仍然无效，强制删除问题容器后重建

  ```bash
  docker rm -f openshell-cluster-nemoclaw
  ```

#### Layer 3: K3s 集群容器无法启动

**诊断**：

```bash
docker ps -a --filter name=openshell-cluster-nemoclaw
# 状态 Exited → 需要恢复
```

**修复**：

- **Option A**：尝试直接重启

  ```bash
  docker start openshell-cluster-nemoclaw
  ```

- **Option B**：重启失败 → 强制删除后重新 onboard

  ```bash
  docker rm -f openshell-cluster-nemoclaw
  source ~/.nvm/nvm.sh
  # 清理可能残留的锁文件和端口占用
  rm -f ~/.nemoclaw/onboard.lock
  pkill -f 'socat.*18789' 2>/dev/null
  # 禁用 watchdog 避免干扰 onboard
  crontab -l | grep -v nemoclaw-watchdog | crontab -
  nemoclaw onboard --non-interactive
  ```

> **注意**：`nemoclaw onboard` 会重新拉取镜像并创建 K3s 集群。
> 如果 Registry 不可达，会在 Layer 4 卡住。

#### Layer 4: 镜像拉取失败（Registry Mirror）

**诊断**：`nemoclaw onboard` 卡在 "Waiting for cluster to be ready"，或 Pod 处于
`ImagePullBackOff`。

```bash
docker exec openshell-cluster-nemoclaw kubectl get pods -A
docker exec openshell-cluster-nemoclaw kubectl describe pod <pod> -n <ns> | grep -A5 Events
```

**修复分 4 步**：

**Step 1 — 确认 Ubuntu 上的 Registry Mirror 正常**

```bash
# 在 Ubuntu 上检查
curl -s http://<UBUNTU_LAN_IP>:5001/v2/_catalog   # ghcr.io mirror
curl -s http://<UBUNTU_LAN_IP>:5002/v2/_catalog   # docker.io mirror
ss -tlnp | grep -E '5001|5002'

# 确认 ghcr mirror 配置了 pull-through cache（本次故障根因之一）
# config.yml 中必须有: proxy.remoteurl: https://ghcr.io
```

**Step 2 — 确认 DGX → Mirror 网络通**

```bash
# 从 DGX 测试
curl -s --connect-timeout 5 http://<HOME_WG_IP>:5001/v2/_catalog
curl -s --connect-timeout 5 http://<HOME_WG_IP>:5002/v2/_catalog

# 超时？→ 检查 Ubuntu 防火墙
sudo ufw status
sudo ufw allow 5001/tcp
sudo ufw allow 5002/tcp
```

**Step 3 — Hot-patch K3s containerd 镜像配置**

`nemoclaw onboard` 动态生成 `registries.yaml`，可能端口映射不对。
直接写 `certs.d` 配置绕过：

```bash
C=openshell-cluster-nemoclaw

# docker.io → Ubuntu:5002 (docker.io pull-through cache)
docker exec $C sh -c '
  mkdir -p /var/lib/rancher/k3s/agent/etc/containerd/certs.d/docker.io
  cat > /var/lib/rancher/k3s/agent/etc/containerd/certs.d/docker.io/hosts.toml << EOF
server = "https://registry-1.docker.io"
[host."http://<HOME_WG_IP>:5002"]
  capabilities = ["pull", "resolve"]
  skip_verify = true
EOF'

# ghcr.io → Ubuntu:5001 (ghcr.io pull-through cache)
docker exec $C sh -c '
  mkdir -p /var/lib/rancher/k3s/agent/etc/containerd/certs.d/ghcr.io
  cat > /var/lib/rancher/k3s/agent/etc/containerd/certs.d/ghcr.io/hosts.toml << EOF
server = "https://ghcr.io"
[host."http://<HOME_WG_IP>:5001"]
  capabilities = ["pull", "resolve"]
  skip_verify = true
EOF'

# registry.k8s.io → 同走 docker.io mirror
docker exec $C sh -c '
  mkdir -p /var/lib/rancher/k3s/agent/etc/containerd/certs.d/registry.k8s.io
  cat > /var/lib/rancher/k3s/agent/etc/containerd/certs.d/registry.k8s.io/hosts.toml << EOF
server = "https://registry.k8s.io"
[host."http://<HOME_WG_IP>:5002"]
  capabilities = ["pull", "resolve"]
  skip_verify = true
EOF'
```

> **端口映射约定**：Ubuntu 5001 = ghcr.io，5002 = docker.io。
> 注意这和某些默认配置是反的，以实际 registry config 为准。

**Step 4 — 手动导入拉不下来的镜像**

```bash
# 从 DGX 宿主机 Docker 导入到 K3s containerd
docker save <image:tag> | \
  docker exec -i $C ctr --address /run/k3s/containerd/containerd.sock \
    -n k8s.io images import -

# 删除失败的 Pod 让 K8s 重新调度
docker exec $C kubectl delete pod <pod-name> -n <ns>
```

#### Layer 5: Gateway + 端口转发 + 网络配置

**诊断**：K3s 和 Pod 都在运行，但外部访问不到。

```bash
KUBECTL="docker exec openshell-cluster-nemoclaw kubectl"

# 沙箱内 gateway 是否在监听？
$KUBECTL exec my-assistant -n openshell -- ss -tlnp | grep 18789

# 绑定在 127.0.0.1？→ 需要改为 0.0.0.0
# 完全没监听？→ 需要启动 gateway
```

**Step 1 — 启动 Gateway（必须 `--bind lan`）**

- **Option A**：`nemoclaw onboard` 刚完成，用 `nemoclaw-start` 启动

  ```bash
  # nemoclaw-start 默认绑定 127.0.0.1，后续用 Option B 重启
  ssh -o "ProxyCommand=openshell ssh-proxy --gateway-name nemoclaw --name my-assistant" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR -T -o RequestTTY=no \
    sandbox nemoclaw-start &
  ```

- **Option B**：通过 `kubectl exec` 启动（推荐，直接绑定 `0.0.0.0`）

  ```bash
  # 先杀掉可能存在的旧 gateway（sandbox 内无 kill，用 python）
  $KUBECTL exec my-assistant -n openshell -- python3 -c "
  import os, signal, subprocess
  r = subprocess.run(['ss','-tlnp'], capture_output=True, text=True)
  for line in r.stdout.splitlines():
      if ':18789' in line and 'pid=' in line:
          pid = int(line.split('pid=')[1].split(',')[0])
          os.kill(pid, signal.SIGTERM)
          print(f'Killed gateway PID {pid}')
  " 2>/dev/null
  sleep 3

  # 启动新 gateway
  $KUBECTL exec my-assistant -n openshell -- sh -c '
    export HOME=/sandbox
    export NODE_EXTRA_CA_CERTS=/etc/openshell-tls/ca-bundle.pem
    nohup openclaw gateway run --bind lan --port 18789 \
      > /sandbox/.openclaw-data/gateway.log 2>&1 &
  '
  ```

  > 也可以用 `openclaw gateway stop` 停止旧 gateway，但部分版本下该命令
  > 因缺少 `lsof` 不能正常工作。

**Step 2 — 创建 NodePort Service**

```bash
echo 'apiVersion: v1
kind: Service
metadata:
  name: nemoclaw-ui
  namespace: openshell
spec:
  ports:
  - port: 18789
    protocol: TCP
    targetPort: 18789
    nodePort: 30089
  selector:
    agents.x-k8s.io/sandbox-name-hash: b1c746e6
  type: NodePort' | docker exec -i openshell-cluster-nemoclaw kubectl apply -f -
```

**Step 3 — socat 端口转发**

```bash
pkill -f 'socat.*18789' 2>/dev/null
nohup socat TCP-LISTEN:18789,bind=0.0.0.0,reuseaddr,fork \
  TCP:<K3S_CONTAINER_IP>:30089 > /tmp/socat-nemoclaw.log 2>&1 &
```

**Step 4 — iptables DNAT**

```bash
# 清理旧规则
sudo iptables -t nat -D PREROUTING -i wg0 -p tcp --dport 18789 \
  -j DNAT --to-destination 127.0.0.1:18789 2>/dev/null
sudo iptables -t nat -D PREROUTING -i wg0 -p tcp --dport 18789 \
  -j DNAT --to-destination <K3S_CONTAINER_IP>:30089 2>/dev/null

# 添加新规则
sudo iptables -t nat -A PREROUTING -i wg0 -p tcp --dport 18789 \
  -j DNAT --to-destination <K3S_CONTAINER_IP>:30089
sudo iptables -I FORWARD -i wg0 -d <K3S_CONTAINER_IP> -p tcp --dport 30089 -j ACCEPT
sudo iptables -t nat -C POSTROUTING -s <WG_SUBNET> -d <K3S_CONTAINER_IP> \
  -p tcp --dport 30089 -j MASQUERADE 2>/dev/null || \
sudo iptables -t nat -A POSTROUTING -s <WG_SUBNET> -d <K3S_CONTAINER_IP> \
  -p tcp --dport 30089 -j MASQUERADE
```

**Step 5 — 更新 trustedProxies**

```bash
$KUBECTL exec my-assistant -n openshell -- python3 -c "
import json, hashlib
path = '/sandbox/.openclaw/openclaw.json'
cfg = json.load(open(path))
cfg['gateway']['trustedProxies'] = [
    '127.0.0.1', '::1', '10.42.0.0/16', '172.18.0.0/16'
]
json.dump(cfg, open(path, 'w'), indent=2)
h = hashlib.sha256(open(path, 'rb').read()).hexdigest()
with open('/sandbox/.openclaw/.config-hash', 'w') as f:
    f.write(f'{h}  openclaw.json\n')
print('Updated trustedProxies + config hash')
"
# 更新后需重启 gateway（见 Step 1 Option B）
```

#### Layer 6: Inference 路由

**诊断**：

```bash
source ~/.nvm/nvm.sh
openshell inference get -g nemoclaw
# 如果显示 nvidia-prod 而非 local-ollama → 需要重新配置
```

**修复**：

```bash
# 创建 Ollama provider（如果不存在）
openshell provider create -g nemoclaw \
  --name local-ollama \
  --type openai \
  --credential OPENAI_API_KEY=ollama \
  --config baseUrl=http://<DGX_LAN_IP>:11434/v1

# 设置 inference 路由（--no-verify 跳过对外部 API 的验证）
openshell inference set -g nemoclaw \
  --provider local-ollama \
  --model gpt-oss:120b-fast \
  --no-verify
```

#### 恢复 Watchdog

```bash
# 确认 watchdog 脚本存在
ls -la ~/nemoclaw-watchdog.sh

# 重新添加到 crontab（onboard 前可能被临时移除）
(crontab -l 2>/dev/null; echo '*/5 * * * * /home/xsuper/nemoclaw-watchdog.sh 2>/dev/null') \
  | sort -u | crontab -
```

#### 验证清单

```bash
# DGX 本地
curl -s -o /dev/null -w '%{http_code}' --noproxy '*' http://127.0.0.1:18789/

# Home Ubuntu → DGX (WireGuard)
curl -s -o /dev/null -w '%{http_code}' http://<DGX_WG_IP>:18789/

# 域名 (HTTPS via NPM)
curl -s -o /dev/null -w '%{http_code}' https://nemoclaw.your-domain.com/

# 三项都应返回 200
```

#### 经验总结

| 发现 | 影响 | 预防 |
|------|------|------|
| vLLM + Ollama 共存时 DGX 内存接近上限 | 任何额外内存申请都可能触发 OOM → 容器退出 → Docker 状态损坏 | 控制 `gpu-memory-utilization`，监控 `free -h` |
| GHCR mirror 未配置 `proxy.remoteurl` | 不是真正的 pull-through cache，containerd 拉取全部失败 | 部署后用 `curl /v2/_catalog` 验证 mirror 能代理上游 |
| `nemoclaw onboard` 动态生成 `registries.yaml` | 端口映射可能与实际 mirror 不一致 | 用 hot-patch `certs.d` 方式覆盖，不依赖自动生成 |
| `nemoclaw-start` 默认绑定 `127.0.0.1` | NodePort 流量来自 pod 网络，到不了 loopback | 必须用 `--bind lan` 或 `kubectl exec` 方式启动 |
| sandbox 内无 `kill`/`ps`/`lsof` 命令 | 无法用常规方式管理进程 | 用 `python3 os.kill()` 或 `openclaw gateway stop` |
| `openshell forward` (SSH 隧道) | 端口仅绑定 `127.0.0.1`，且隧道不稳定 | 使用 NodePort + socat + iptables DNAT 方案 |

---

### 2026-04-05（同日）：DDNS IP 变更导致 WireGuard 断连

**症状**：NemoClaw 刚修好又不可用，`ping <DGX_WG_IP>` 100% 丢包。

**诊断**：

```bash
# 从 Ubuntu 检查
dig +short your-domain.com                   # 当前公网 IP
ssh root@<OPENWRT_LAN_IP> 'wg show wg0'           # 查看 DGX peer
# latest handshake 超过几分钟 + endpoint IP ≠ 当前公网 IP → 确认是 DDNS 变更
```

**修复**：

```bash
# SSH 到 DGX（通过公网 FRP，不依赖 WireGuard）
ssh -p 6090 xsuper@<DGX_PUBLIC_HOST>

# 获取当前正确的公网 IP
NEW_IP=$(dig +short your-domain.com)

# 更新 WireGuard peer endpoint
sudo wg set wg0 peer <HOME_WG_PUBKEY> endpoint ${NEW_IP}:51820

# 等待 ~10 秒让 keepalive 重建隧道
sleep 10
ping -c 3 <HOME_WG_IP>  # 应恢复
```

**根因**：路由器 PPPoE 重拨后公网 IP 变更，DGX WireGuard 缓存了旧 endpoint。
`wg-reresolve.sh` (cron 每 2 分钟) 应自动修复但本次未生效。

**预防**：确保 reresolve 脚本正常运行：

```bash
cat ~/wg-reresolve.sh            # 确认脚本内容
crontab -l | grep reresolve      # 确认 cron 存在
bash ~/wg-reresolve.sh           # 手动测试
sudo wg show wg0 | grep endpoint # 确认 endpoint 已更新
```

---

## 安全注意事项

1. **WireGuard 单向设计**：DGX `AllowedIPs = <HOME_WG_IP>/32`，只能到 VPN 对端，不能穿透到家里 LAN
2. **OpenWrt 防火墙**：`/etc/firewall.dgx` 限制 DGX 只能访问特定端口（代理端口, 5001, 5002, 18222）
3. **Token 即密码**：NemoClaw UI 的 `#token=xxx` URL 等同于认证凭证，不要泄露
4. **共享设备**：DGX Spark 是黑客松共享设备，WireGuard 密钥在 DGX 本地生成，假设最坏情况

---

## 软件版本

| 组件 | 版本 | 安装方式 |
|------|------|----------|
| OpenClaw | v2026.4.2 | npm global (沙箱内) |
| NemoClaw CLI | v0.1.0 | npm global (宿主机) |
| OpenShell CLI | v0.0.16 | npm global (宿主机) |
| Node.js | v22.22.2 | nvm |
| Docker | 28.5.1 | apt |
| Ollama | v0.18.0 | snap |
| WireGuard | 内核模块 | systemd (wg-quick@wg0) |

### OpenClaw 更新方法

沙箱内更新 OpenClaw 需要 root 权限和正确的 binary path（绕过 openshell 代理策略）：

```bash
# 1. 修复 npm 缓存和 node_modules 权限
docker exec openshell-cluster-nemoclaw kubectl -n openshell exec my-assistant -- sh -c '
mkdir -p /sandbox/.npm/_cacache && chown -R 998:998 /sandbox/.npm /usr/local/lib/node_modules
'

# 2. 用 node.real 执行 npm（node.real 在 npm_registry 策略的 allowed binaries 中）
docker exec openshell-cluster-nemoclaw kubectl -n openshell exec my-assistant -- sh -c '
export HOME=/sandbox NODE_EXTRA_CA_CERTS=/etc/openshell-tls/ca-bundle.pem
/usr/local/bin/node.real /usr/local/bin/npm i -g openclaw@latest
'

# 3. 重新安装飞书 SDK（npm update 会移除 optional deps）
docker exec openshell-cluster-nemoclaw kubectl -n openshell exec my-assistant -- sh -c '
export HOME=/sandbox NODE_EXTRA_CA_CERTS=/etc/openshell-tls/ca-bundle.pem
cd /usr/local/lib/node_modules/openclaw
/usr/local/bin/node.real /usr/local/bin/npm install @larksuiteoapi/node-sdk
'

# 4. 修复 ownership
docker exec openshell-cluster-nemoclaw kubectl -n openshell exec my-assistant -- sh -c '
chown -R 998:998 /usr/local/lib/node_modules/openclaw /sandbox/.openclaw/openclaw.json
'

# 5. 重启 gateway（SSH 进沙箱后）
kill -9 $(ps aux | grep openclaw-gate | grep -v grep | awk '{print $2}') 2>/dev/null
sleep 3 && rm -rf /tmp/jiti /tmp/openclaw-gateway.lock
nohup openclaw gateway run --bind lan > /tmp/gateway.log 2>&1 &

# 6. 验证
openclaw --version
```

> **注意：** 直接用 `npm i -g openclaw@latest` 或 `openclaw update` 会因 npm_registry
> 策略只允许 `node.real`/`npm`/`openclaw` binary 而报 403。必须用 `node.real` 执行 npm。

---

## 团队成员 VPN 访问

队友通过 WireGuard VPN 连入，访问 NemoClaw UI 和 Open WebUI。

### 当前成员

| 姓名 | VPN IP | 配置文件 | 防火墙权限 |
|------|--------|----------|------------|
| haixu | <TEAM_WG_IP_1> | `playbooks/nemoclaw/team-configs/haixu.conf` | NPM 443 only |
| herong | <TEAM_WG_IP_2> | `playbooks/nemoclaw/team-configs/herong.conf` | NPM 443 only |

### 添加新成员

```bash
cd ansible-infra
bash playbooks/nemoclaw/scripts/add-team-member.sh <名字>
```

生成 `.conf`（配置文件）和 `.png`（二维码），发给队友导入 WireGuard 客户端即可。

### 队友可访问的服务

| 域名 | 服务 |
|------|------|
| `https://nemoclaw.your-domain.com/#token=<TOKEN>` | NemoClaw AI 助手 |
| `https://chat.your-domain.com` | Open WebUI (Ollama) |
| `https://claw.your-domain.com` | OpenClaw 网关 |

### 安全限制

- 防火墙仅放行到 NPM (<UBUNTU_LAN_IP>) 的 443 端口
- 无法访问家里 LAN 的其他设备
- 队友无法反向穿透到内网
- 删除 OpenWrt 上的 Peer 即刻断开访问（即使队友保留配置文件）

---

## vLLM Gemma 4 NVFP4 部署

在 DGX Spark 上部署 Gemma 4 31B NVFP4 量化模型，通过 vLLM 提供 OpenAI 兼容 API，与 Ollama 共存。

### 验证信息（2026-04-05）

| 项目 | 值 |
|------|------|
| 模型 | nvidia/Gemma-4-31B-IT-NVFP4 (W4A4, ~31GB) |
| 量化 | modelopt_fp4 + Marlin GEMM + fp8_e4m3 KV Cache |
| 镜像 | vllm/vllm-openai:gemma4-cu130 |
| 端口 | 8888 |
| GPU 内存限制 | 40%（`gpu-memory-utilization 0.40`，与 Ollama 共存可调） |
| 最大上下文 | 32768 tokens（NemoClaw 需要；低于 16k 会在 agent 首轮溢出） |
| Tool calling | `--enable-auto-tool-choice --tool-call-parser hermes`（OpenClaw 会发 `tool_choice: auto`） |
| Ollama 共存 | ✓（视显存/统一内存调整 utilization） |

### NemoClaw 里出现「Context overflow」时

`/reset` 或 `/new` **不会**去掉系统提示、工具列表和 Session Startup 读入的文件，所以首轮 prompt 仍然可能接近上万 token。若 vLLM 的 `--max-model-len` 只有 16384，再叠加 OpenClaw 里为该模型配置的 `maxTokens`（输出预留），很容易触发 `input_tokens + max_tokens > max_model_len`。

处理顺序：

1. 确认 vLLM 实际上限：`curl -s http://127.0.0.1:8888/v1/models | jq '.data[0].max_model_len'`（应与 OpenClaw 里 `contextWindow` 一致，建议 32768）。
2. 重新部署 vLLM（见下方命令或 `playbooks/vllm/deploy.yml`），然后同步 sandbox 内 `openclaw.json` 与 `agents/main/agent/models.json` 里 vLLM 条目的 `contextWindow`，并重启 gateway。
3. 适当降低 vLLM 模型的 `maxTokens`（例如 1024），为长系统 prompt 留出输出余量。

### 手动启停

```bash
ssh -p 6090 xsuper@<DGX_PUBLIC_IP>

# 启动 vLLM
sudo docker run -d --runtime=nvidia --gpus all \
  --name vllm-nvfp4 --network host --shm-size=16g \
  -e VLLM_LOGGING_LEVEL=INFO \
  -e VLLM_NVFP4_GEMM_BACKEND=marlin \
  -v /home/xsuper/models/Gemma-4-31B-IT-NVFP4:/models/Gemma-4-31B-IT-NVFP4 \
  vllm/vllm-openai:gemma4-cu130 \
  --model /models/Gemma-4-31B-IT-NVFP4 \
  --served-model-name gemma-4-nvfp4 \
  --port 8888 --max-model-len 32768 \
  --quantization modelopt --gpu-memory-utilization 0.40 \
  --trust-remote-code \
  --enable-auto-tool-choice --tool-call-parser hermes

# 停止
sudo docker rm -f vllm-nvfp4

# 测试推理
curl http://localhost:8888/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"gemma-4-nvfp4","messages":[{"role":"user","content":"Hi"}],"max_tokens":64}'
```

### Ansible 部署

```bash
ansible-playbook -i inventory/cloud playbooks/vllm/deploy.yml --tags start
```

### 关键注意事项

1. **镜像传输**: DGX 无直连互联网，需先在 Ubuntu 上 `skopeo copy` 提取 arm64 镜像，再 `rsync` 到 DGX
2. **模型传输**: 从 HuggingFace 下载到 Ubuntu 后用 `rsync --partial` 通过 FRP 隧道传到 DGX
3. **NVIDIA Runtime**: 首次需运行 `nvidia-ctk runtime configure --runtime=docker` 并重启 Docker
4. **内存管理**: Ollama 120b 与 vLLM 共用 GPU/统一内存；提高 `max-model-len` 时需同步提高 `gpu-memory-utilization` 并观察 `nvidia-smi`

---

## 黑客松结束清理

**一键清理脚本：**

```bash
# 预览模式（只看不做）
bash playbooks/nemoclaw/scripts/cleanup-hackathon.sh

# 确认后实际执行
bash playbooks/nemoclaw/scripts/cleanup-hackathon.sh --force
```

清理内容包括：
1. DGX Spark: 停止 NemoClaw 沙箱 + 禁用 WireGuard
2. OpenWrt: 删除所有队友 Peers (`wg_team_*`)
3. OpenWrt: 删除 DGX Peer (`wg_dgx`) + 防火墙脚本 (`/etc/firewall.dgx`)
4. OpenWrt: 删除 hackathon DNS 记录
5. Ubuntu: 停止 Registry Mirror 容器
6. NPM: 删除 nemoclaw 代理规则

**手动清理（如脚本不可用）：**

```bash
# 1. DGX 端
ssh -p 6090 xsuper@<DGX_PUBLIC_IP>
source ~/.nvm/nvm.sh
openshell forward stop 18789
openshell sandbox delete my-assistant
sudo systemctl stop wg-quick@wg0 && sudo systemctl disable wg-quick@wg0
sudo rm /etc/wireguard/wg0.conf /etc/networkd-dispatcher/routable.d/50-wg-dnat.sh

# 2. OpenWrt 端
ssh root@<OPENWRT_LAN_IP>
uci delete network.wg_team_haixu
uci delete network.wg_team_herong
uci delete network.wg_dgx
uci commit network
rm /etc/firewall.dgx
/etc/init.d/network restart
uci del_list dhcp.@dnsmasq[0].address='/nemoclaw.your-domain.com/<UBUNTU_LAN_IP>'
uci commit dhcp && /etc/init.d/dnsmasq restart

# 3. Ubuntu 端
docker stop registry-ghcr registry-dockerhub 2>/dev/null
docker rm registry-ghcr registry-dockerhub 2>/dev/null

# 4. Ansible inventory
# 编辑 inventory/cloud/hosts.yml 移除 hackathon 部分
```
