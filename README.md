# Ansible DGX Spark — NemoClaw 本地大模型基础设施自动化

> NVIDIA DGX Spark Hackathon 参赛作品

使用 Ansible 自动化管理 NVIDIA DGX Spark 上的完整本地大模型 + AI 助手基础设施，
包括 WireGuard VPN 组网、Ollama 本地大模型、vLLM 推理服务、NemoClaw AI 沙箱、
旅行规划助手（云希）等全套服务的一键部署和运维。

## 项目亮点

- **一键部署**: 从裸机到可用的 AI 助手，全自动化 Ansible 编排
- **本地大模型**: Ollama (gpt-oss:120b) + vLLM (Gemma 4 NVFP4) 双引擎并行
- **安全组网**: WireGuard VPN 隧道 + iptables DNAT + Nginx 反代 HTTPS 终止
- **自动运维**: Watchdog 5 分钟巡检 + 自动修复 Gateway/NodePort/网络规则
- **Travel App**: 基于高德地图 API 的旅行规划助手，深度游戏化前端体验
- **团队协作**: 一键为队友生成 WireGuard 配置，安全访问控制
- **全面文档**: 1800+ 行运维手册，覆盖所有故障排查场景

## 架构概览

```
浏览器 (任意设备)
  │  https://nemoclaw.your-domain.com
  ▼
Nginx Proxy Manager (Home Server, HTTPS 终止)
  │  proxy_pass http://<DGX_WG_IP>:18789
  ▼
WireGuard 隧道 (Home ↔ DGX Spark)
  │
  ▼
DGX iptables DNAT → K3s NodePort → OpenClaw Gateway (沙箱内)
  │
  ├── Ollama (gpt-oss:120b-fast, 32K ctx, ~66GB GPU)
  │     via openshell inference 路由 → inference.local
  │
  ├── vLLM (Gemma 4 31B NVFP4, 32K ctx, 40% GPU)
  │     OpenAI 兼容 API :8888
  │
  └── Travel App (Node.js + 高德地图 + SQLite)
        旅行规划 + 出行打卡 + 旅行日记
```

## 目录结构

```
.
├── ansible.cfg                        # Ansible 配置
├── collections/requirements.yml       # Ansible Galaxy 依赖
├── inventory/hosts.yml.example        # 主机清单模板
├── group_vars/
│   ├── all.yml                        # 全局变量
│   └── secrets.yml.example            # 敏感信息模板
├── playbooks/
│   ├── nemoclaw/
│   │   ├── site.yml                   # 一键全量部署编排
│   │   ├── deploy.yml                 # WireGuard + Docker + NemoClaw Onboard
│   │   ├── ollama.yml                 # Ollama 安装 + 模型 + Inference 路由
│   │   ├── travel.yml                 # 旅行助手 Travel App + Skill
│   │   ├── configure.yml              # Sandbox Patches + Feishu + Watchdog
│   │   ├── repair.yml                 # 一键修复沙箱
│   │   ├── vars/main.yml              # 配置变量
│   │   ├── templates/                 # Jinja2 模板
│   │   │   ├── wg0.conf.j2           # WireGuard 客户端配置
│   │   │   ├── 50-wg-dnat.sh.j2      # DNAT 规则脚本
│   │   │   ├── docker-daemon.json.j2  # Docker registry mirror
│   │   │   ├── ollama-*.conf.j2       # Ollama systemd overrides
│   │   │   ├── openclaw.json.j2       # OpenClaw Gateway 配置
│   │   │   ├── proxy-bootstrap.js.j2  # TLS/代理 bootstrap
│   │   │   ├── node-wrapper.sh.j2     # Node.js 环境注入 wrapper
│   │   │   └── nemoclaw-watchdog.sh.j2 # 自动运维脚本
│   │   ├── skills/local-llm/          # A2A 本地模型调用 Skill
│   │   └── scripts/                   # 运维脚本
│   │       ├── add-team-member.sh     # 添加队友 VPN
│   │       ├── health-check.sh        # 健康检查
│   │       └── cleanup-hackathon.sh   # 一键清理
│   └── vllm/
│       ├── deploy.yml                 # vLLM Gemma 4 NVFP4 部署
│       ├── vars/main.yml              # vLLM 配置变量
│       └── templates/docker-compose.yml.j2
└── docs/
    └── nemoclaw-dgx-spark.md          # 完整运维手册 (1800+ 行)
```

## 快速开始

### 前提条件

| 组件 | 要求 |
|------|------|
| DGX Spark | NVIDIA GB10, 128GB 统一内存, aarch64 |
| Home Server | Ubuntu 22.04+, Docker, Nginx Proxy Manager |
| 路由器 | OpenWrt (WireGuard Server) |
| 软件 | Ansible 2.15+, Python 3.10+ |
| API Key | NVIDIA Build (https://build.nvidia.com) |

### 1. 安装依赖

```bash
# 安装 Ansible
pip install ansible

# 安装 Ansible Galaxy Collections
ansible-galaxy collection install -r collections/requirements.yml
```

### 2. 配置环境

```bash
# 复制并编辑 inventory
cp inventory/hosts.yml.example inventory/hosts.yml
# 修改 DGX IP、用户名、端口等

# 复制并编辑 secrets（建议用 ansible-vault 加密）
cp group_vars/secrets.yml.example group_vars/secrets.yml
ansible-vault encrypt group_vars/secrets.yml
# 填入 NVIDIA API Key、WireGuard 密钥等

# 修改 playbooks/nemoclaw/vars/main.yml
# 设置你的域名、WireGuard 公钥等
```

### 3. 一键部署

```bash
# 全新完整部署（WireGuard + Ollama + Travel App + 配置）
ansible-playbook playbooks/nemoclaw/site.yml \
  -e nvidia_api_key=nvapi-xxx \
  -e wg_dgx_private_key=xxx

# 带飞书 Bot 集成
ansible-playbook playbooks/nemoclaw/site.yml \
  -e nvidia_api_key=nvapi-xxx \
  -e wg_dgx_private_key=xxx \
  -e feishu_enabled=true \
  -e feishu_app_id=cli_xxx \
  -e feishu_app_secret=xxx
```

### 4. 单独运行特定模块

```bash
# 仅 Ollama 模型管理
ansible-playbook playbooks/nemoclaw/ollama.yml --tags model

# 仅 Travel App
ansible-playbook playbooks/nemoclaw/travel.yml

# 仅 vLLM
ansible-playbook playbooks/vllm/deploy.yml --tags start

# 修复沙箱
ansible-playbook playbooks/nemoclaw/repair.yml -e nvidia_api_key=nvapi-xxx
```

## 技术创新点

### 1. Ansible 编排本地大模型基础设施

将传统的手动运维流程转化为可重复的 Ansible Playbook，实现：
- **声明式部署**: 定义目标状态，Ansible 自动处理差异
- **幂等操作**: 多次运行结果一致，安全可靠
- **模块化设计**: 6 个独立 Playbook 可单独运行或组合编排

### 2. OpenShell Sandbox 深度集成

解决了 NemoClaw 沙箱环境中的多个技术难题：
- **TLS MITM 处理**: `proxy-bootstrap.js` 处理 openshell 透明代理的证书链
- **Node Wrapper**: 自动注入环境变量到所有 Node.js 进程（包括自动重启的 gateway）
- **Inference 路由**: 通过 `openshell provider` + `inference set` 绕过沙箱网络策略限制

### 3. 高可用自动运维

`nemoclaw-watchdog.sh` 每 5 分钟巡检 6 个关键组件：
- K8s NodePort Service 存在性
- socat 端口转发进程
- iptables DNAT 规则
- OpenClaw Gateway 进程
- SQLite 数据库锁监控
- HTTP 健康检查

### 4. WireGuard VPN 安全组网

- 单向网络设计: DGX 仅能访问 VPN 对端，无法穿透到家庭 LAN
- 防火墙隔离: OpenWrt `firewall.dgx` 限制 DGX 可访问的端口
- 一键添加队友: `add-team-member.sh` 自动生成配置 + 二维码 + 使用说明
- DDNS 自适应: `wg-reresolve.sh` 自动更新 WireGuard endpoint

## NVIDIA 工具/平台/SDK/模型

| 工具 | 用途 |
|------|------|
| **DGX Spark (GB10)** | 128GB 统一内存 aarch64 边缘 AI 平台 |
| **Ollama + gpt-oss:120b** | 120B 参数本地大模型 (MXFP4 量化, ~66GB) |
| **vLLM + Gemma 4 31B NVFP4** | NVIDIA ModelOpt FP4 量化推理 (Marlin GEMM) |
| **NemoClaw CLI** | AI 沙箱助手管理工具 |
| **OpenShell** | 安全沙箱 + K3s 容器编排 |
| **NVIDIA NIM API** | Nemotron-3 Super 120B 云端推理 (Fallback) |

## 文档

完整运维手册见 [docs/nemoclaw-dgx-spark.md](docs/nemoclaw-dgx-spark.md)，包含：

- 网络架构详解
- 所有 Patch 记录 (Patch 1-8)
- 故障排查决策树
- 级联故障修复实录
- 沙箱重建完整恢复流程
- 飞书 Bot 接入指南
- vLLM Gemma 4 部署指南
- 黑客松结束清理流程

## 团队

| 成员 | 分工 |
|------|------|
| [填写] | 基础设施 / Ansible / 网络架构 |
| [填写] | Travel App 前端 / 游戏化设计 |
| [填写] | 模型调优 / Skill 开发 |

## License

MIT
