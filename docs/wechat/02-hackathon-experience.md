# 我们参加了 NVIDIA 黑客松，给了一台被关在上海角落的金盒子，结果用它规划了一趟没去成的清明假期

> NVIDIA DGX Spark Hackathon 2026（全国赛）· 团队「交个朋友」· 第一现场记录

---

> 📺 **写在最前面的一点意外**
> 这篇本来是想纯当"踩坑日记"发的——讲讲我们怎么把一台被关在上海机房的 DGX Spark 接回深圳家里、怎么在清明假期被九个坑轮番暴打、怎么在凌晨三点顿悟一个环境变量。
>
> 直到前两天黑客松的线上总结会议——主办方过最终排名，从第一名开始一行行往下念。念到**第六名**的时候，我们盯着屏幕愣了几秒：那是我们团队的名字。
>
> 几个在家折腾 Homelab 的人，在全国赛里被点到了第六。这不是我们写文章前想好要讲的事，但既然真的发生了，那就放在开头一并交代——后面回到正文，继续讲那台金盒子是怎么住进我家的。

---

清明假期前两周，家里的一段真实对话：

> **他：**「去汕尾吧？生腌一绝，去吃延祺和海王。」
>
> **她：**「单程三个小时，就三天假，光花在路上了。」
>
> **他：**「那露营？这个季节空气好。」
>
> **她：**「你看了天气预报没有？台风外围，三天都下雨。」
>
> **他：**「那惠州？」
>
> **她：**「惠州去了不下七八次了，你说还有什么好玩的。」
>
> **他：**「泡温泉！」
>
> **她：**「节假日人多到下饺子，算了算了。」
>
> **他：**「那你说去哪！」
>
> **她：**「……我也不知道，算了待家里吧。」
>
> *沉默五秒。*
>
> **她：**「要不，问问云希？」

三分钟后，云希拉好了深圳到汕尾的驾车路线，交叉比对了 4 月 17–19 日的天气数据，筛选出三家高德评分靠前的本地生腌餐厅，生成了一份三天两夜的沿海行程。行程有名字、有地图、有一套等着你去刮开的集章打卡卡。

**但我们哪儿都没去。**

整个清明假期，我们都在 NVIDIA DGX Spark 上 debug、调模型、写 Ansible Playbook——写的就是规划这趟旅行的那个工具。

旅行日记里存着的，不是汕尾的海和生腌，而是 DGX Spark 的开箱视频和键盘特写。

这是 NVIDIA DGX Spark Hackathon 2026 的第一现场。

![夫妻假期争吵——每个提议都被否决](images/couple-vacation-dilemma.jpg)

---

## 一、收到那台「金盒子」的瞬间

NVIDIA 官方黑客松的奖励很直接——**每个队伍分配一台 DGX Spark**。搭载 GB10 超级芯片、128GB 统一内存的「桌面级超算」。

听起来很香对吧？

然后我们发现，这台金盒子被关在上海某个机房的角落里，只给了一个 FRP 跳板的 SSH 端口。我们人在深圳，家里跑了几个月的 OpenClaw（小龙虾）AI Agent 系统，目标很简单：

> 把 NVIDIA 新出的 **NemoClaw**（官方安全 AI 助手沙箱）部署到这台 DGX Spark 上，然后通过家里的网络把它暴露出来，用自己的域名访问。

**听起来就三步：连上去 → 装上去 → 暴露出来。**

实际走完，我们数了一下，踩了 **九个坑**。

---

## 二、赛事信息

| 项目 | 详情 |
|---|---|
| **赛事** | NVIDIA DGX Spark Hackathon 2026 |
| **平台** | NVIDIA DGX Spark（GB10 Grace Blackwell Superchip）|
| **周期** | 3 月 29 日 – 4 月 9 日（含清明假期） |
| **项目** | NemoClaw Travel OS——私有化 AI 旅行助手 |
| **团队** | 交个朋友 |
| **GitHub** | [ansible-dgx-spark](https://github.com/peterpanstechland/ansible-dgx-spark) |

---

## 三、九个坑实录：从 SSH 到生产可用

先上个全景图，让各位有个心理准备：

```
家里 Ubuntu  ──加密隧道──→  DGX Spark（上海）
     │                            │
  家庭路由                     反向 SSH
  (隧道入口)                  （唯一的生命线）
     │                            │
  Nginx 反代                   NemoClaw
  (域名转发)                   (K3s + OpenShell + 沙箱)
```

### 🕳️ 坑一：隧道方向搞反了

一开始设计的是双向加密隧道——家里能到 DGX，DGX 也能到家里。

**为什么不行**：DGX Spark 是共享设备，黑客松结束后其他人也能用。如果对方拿到隧道私钥，理论上能穿透到我家里的整个内网。

**解法**：改成**单向设计**。
- DGX 端 `AllowedIPs = <家里隧道网关>/32`——只能看到隧道对端，看不到家里其他设备
- 家庭路由加 iptables 规则：DGX → 家里 LAN 全部 DROP
- 家里能主动连 DGX ✅，DGX 反向穿透家里 ❌

教训：**共享设备上的安全边界，要假设最坏情况。**

### 🕳️ 坑二：上海机房的网络出口太慢，海外镜像拉不动

`nemoclaw onboard` 需要从 `ghcr.io` 和 `docker.io` 拉镜像。DGX 在上海机房，到这两个海外仓库的网络延迟和稳定性都很差，经常拉到一半就断。

**天真的想法**：让 DGX 走家里的网络出口不就行了？

**现实的巴掌**：Go 语言（Docker 和 containerd 都是 Go 写的）的 TLS 实现和某些网络转发不兼容。具体表现：连接建立后立刻 EOF，镜像拉到一半就断。

**真正的解法**：在家里的 Ubuntu 上搭了两个 Docker Registry Mirror（端口 5001 给 ghcr.io，5002 给 docker.io），用 Python 脚本预拉镜像缓存到本地,再让 DGX 从家里的 mirror 拉。

```
DGX ──加密隧道──→ Ubuntu:5001 ──缓存──→ ghcr.io
                  Ubuntu:5002 ──缓存──→ docker.io
```

为什么用 Python 不用 Docker 原生的网络配置？因为 Go 的 TLS 实现和某些网络中转有兼容问题，而 Python 的 `requests` 库表现稳定得多。

### 🕳️ 坑三：1.4GB 的镜像“走私”

`ghcr.io/nvidia/nemoclaw/sandbox-base:latest` 是 NemoClaw 沙箱的基础镜像，**1.4GB**，而且是 ARM64 架构（DGX Spark 是 Grace CPU）。Mirror 只能缓存你拉过的镜像，这个镜像太大，通过 mirror 中转不稳定。

**解法**：镜像走私三步曲——

1. 在 Ubuntu 上用 Python 脚本把 ARM64 镜像拉下来
2. `docker save` 成 tar 包，用 Python HTTP Server 临时托管
3. DGX 通过加密隧道下载 tar，`docker load` 导入

然后发现——DGX 连 Ubuntu 的 8888 端口不通。家庭路由防火墙没放行这个端口。又加了一条 DNAT。

### 🕳️ 坑四：Docker ≠ K3s，镜像白搬了

NemoClaw 底层用的是 **K3s**（轻量 Kubernetes），K3s 用的是 **containerd**，不是 Docker daemon。你往 Docker 里 load 的镜像，K3s 完全看不见。

**表现**：`nemoclaw onboard` 跑到创建沙箱那步，Pod 一直 `ImagePullBackOff`。

**解法**：双管齐下——

1. 用 `ctr -n k8s.io image import` 把镜像导入 containerd 命名空间
2. 构建自定义的 `openshell/cluster` 镜像，把 `registries.yaml`（指向家里的 mirror）和 `pause.tar`（K3s 必需的基础镜像）预烘焙进去

这一步折腾了最久。**三层嵌套：Docker 跑 K3s，K3s 跑 containerd，containerd 里跑沙箱 Pod。每一层都有自己的镜像存储，互不相通。**

### 🕳️ 坑五：domain 通了，origin 不允许

域名配好了，SSL 证书也有了，浏览器打开 `https://nemoclaw.peafamily.online`——页面加载了，但是弹了个大大的 **"origin not allowed"**。

**原因**：NemoClaw 沙箱里的 OpenClaw gateway 有个 `allowedOrigins` 配置，默认只允许 `http://127.0.0.1:18789`。从域名访问的 origin 不在白名单里。

**天真的想法**：直接进沙箱改 `openclaw.json` 不就行了？

天真。

### 🕳️ 坑六：沙箱里的幽灵进程——网络命名空间地狱

进沙箱改了 `openclaw.json`，加了新的 origin，更新了 config hash。然后 kill 掉 gateway 进程准备重启。

**诡异的事情发生了**：

- 沙箱**里面** `curl localhost:18789` → 200 ✅
- DGX **宿主机** `curl localhost:18789` → **Empty reply from server** ❌

gateway 明明在跑，但 SSH 隧道就是连不上。

**原因**：OpenShell 的沙箱使用了 **Landlock + seccomp + netns** 隔离。gateway 进程运行在沙箱的**独立网络命名空间**里。当我 `kubectl exec` 进 Pod 手动启动 gateway 时，新进程跑到了 Pod 的**主命名空间**，而不是沙箱的隔离命名空间。SSH 隧道连的是隔离命名空间里的端口，自然连不上。

更惨的是：`kubectl delete pod` 想重建 Pod 时，发现 `/sandbox/.openclaw/openclaw.json` 的改动**全丢了**——这个文件在容器镜像层，不在持久化卷上。Pod 重建后入口脚本检测到配置不一致，直接 fallback 成 `sleep infinity`。

整个沙箱就这么「假死」了：Pod 是 Running 状态，但里面什么都没跑。

### 🕳️ 坑七：openshell 代理的 TLS 拦截重签

沙箱内所有 HTTPS 流量必须经过 openshell 代理（`http://<openshell-proxy>:3128`），代理做 TLS 解密拦截并用自签 CA 重新签名。Node.js 默认不信任此 CA，导致：

- webchat 发消息返回 **"LLM request timed out"**
- 飞书 SDK 报 `stream has been aborted`

**根因有三个**：
1. Node.js 不认 openshell 自签 CA → 所有 HTTPS 请求失败
2. axios 读取 `HTTPS_PROXY` 后不走 CONNECT 隧道，发送纯 HTTP 请求
3. Node.js 22 内置 fetch（基于 undici）需要 `HTTPS_PROXY` 才能走代理

**解法**：写了一个 `proxy-bootstrap.js`，通过 `NODE_OPTIONS` 预加载——
- 设置 `NODE_EXTRA_CA_CERTS` 信任 openshell CA
- monkey-patch `https.request` 走正确的 CONNECT 隧道
- 通过 `Module.prototype.require` hook 把 axios 的 `defaults.proxy = false`
- 保留 `HTTPS_PROXY` 供 fetch() 使用

### 🕳️ 坑八：自动重启的"幽灵 gateway"

修好 TLS 之后，gateway 跑了，LLM 也通了。但跑两天就出问题——**有时 webchat 又开始 timeout**。

排查发现：openshell-sandbox（沙箱的 PID 1）会自动检测并重启 `openclaw gateway`。但它直接调用 `node` 二进制，不经过 shell，**不读取我们手动设置的环境变量**。结果：自动重启的 gateway 没有 `NODE_OPTIONS`，没有 proxy bootstrap，但绑定到 `0.0.0.0:18789` 抢走了 NodePort 流量。

**解法**：把 `/usr/local/bin/node` 替换成 wrapper 脚本，自动注入环境变量：

```bash
#!/bin/sh
export NODE_EXTRA_CA_CERTS=/etc/openshell-tls/ca-bundle.pem
if [ -z "$__OPENCLAW_NODE_WRAPPED" ]; then
  export __OPENCLAW_NODE_WRAPPED=1
  export HTTPS_PROXY=http://<openshell-proxy>:3128
  export NODE_OPTIONS="--require /sandbox/.openclaw/proxy-bootstrap.js ${NODE_OPTIONS:-}"
fi
exec /usr/local/bin/node.real "$@"
```

`__OPENCLAW_NODE_WRAPPED` 守卫防止子进程重复设置 `NODE_OPTIONS`。**不管是谁起的 node 进程，都会自动获得正确的 env。**

### 🕳️ 坑九（终极顿悟）：一个环境变量的事

折腾完前八个坑，回过头翻 NemoClaw 的 `onboard.js` 源码，发现一行——

```javascript
const chatUiUrl = process.env.CHAT_UI_URL || "http://127.0.0.1:18789";
```

`CHAT_UI_URL` 会在沙箱创建时被写入 `openclaw.json` 的 `allowedOrigins`。

也就是说，**从一开始**就应该在 onboard 的时候把域名传进去，而不是事后去改配置文件。

```bash
openshell sandbox delete my-assistant

CHAT_UI_URL=https://nemoclaw.peafamily.online \
nemoclaw onboard --non-interactive
```

**两分钟跑完。** `curl https://nemoclaw.peafamily.online/` → **200**。

九个坑，最后一个坑的答案是一个环境变量。

![清明深夜的家中 debug 现场——金盒子、冷咖啡、和那张没去成的汕尾明信片](images/qingming-debug-scene.jpg)

---

## 四、最终架构：从浏览器到 NVIDIA API 的六层转发

```
浏览器
  │  https://nemoclaw.peafamily.online
  ▼
Nginx Proxy Manager (Ubuntu)
  │  proxy_pass http://<dgx-host>:18789
  ▼
加密隧道 (家里 ←→ DGX)
  │  iptables DNAT: tunnel:18789 → K3s:30089
  ▼
K3s NodePort Service (nemoclaw-ui, 30089 → Pod:18789)
  │
  ▼
OpenClaw Gateway (沙箱 Pod 内, --bind lan, Landlock 隔离)
  │
  ├─→ https://inference.local/v1
  │   ↓ openshell provider 路由
  │   Ollama (DGX 宿主机, gpt-oss:120b-fast, 100% GPU)  ← 主模型
  │
  └─→ wss://msg-frontier.feishu.cn  ← 飞书 WebSocket
```

从浏览器到 AI 模型，经过了：HTTPS → Nginx → 加密隧道 → iptables DNAT → K3s NodePort → 沙箱网络命名空间 → 本地 Ollama。

**六层网络转发。每一层都有自己的故障模式。** 我们在 DGX 上写了一个 `nemoclaw-watchdog.sh`，每 5 分钟检查并自动修复每一层。

---

## 五、惊喜的发现：DGX Spark 远比想象中能打

折腾完整套部署后，我们才有空认真测一下 DGX Spark 的实际表现。

### 1. 128GB 统一内存的实际意义

不是"大"。是"模型完整驻留 + 余下 60GB+ 给系统"。

`gpt-oss:120b` 模型加载到 GPU 后，占用 ~66GB，剩下的内存还能让我们同时跑 vLLM 服务 Gemma 4 31B NVFP4——**两个百亿参数模型在同一台机器上同时为不同任务服务**，这是过去你想都不敢想的事情。

### 2. NVFP4 不只是量化

在 Blackwell 架构上，NVFP4 是**硬件原生精度格式**，不是单纯的压缩。我们用 vLLM 跑 Gemma 4 31B NVFP4 量化模型，TTFT（首 token 延迟）< 2 秒，多模态视觉理解的吞吐量比通用 INT4 高得多。

### 3. 真正的家庭级体验

测试的时候，家里同时挂了 3 个家庭成员账号——一个用云希在飞书规划行程，一个在测试小红书 Skill 生成种草文案，一个用 Gemma 4 分析照片。

**没有任何一个查询变慢。** 没有"等一下我先服务别人"。这就是统一内存 + 多引擎的力量。

---

## 六、Ansible 部署：把九个坑沉淀成一条命令

走完九个坑之后，我们做的第一件事是：**把所有解法变成 Ansible Playbook**。

```bash
ansible-playbook playbooks/nemoclaw/site.yml
```

这一条命令负责：
- 安装 Ollama 并拉取 gpt-oss:120b
- 部署 NemoClaw + OpenShell 沙箱
- 启动 vLLM + Gemma 4 NVFP4
- 部署 Travel App（Express + SQLite + 高德 API）
- 配置加密隧道和 DNAT 规则
- 配置 Docker 镜像缓存
- 部署 watchdog 自愈脚本

**升级？改个变量重跑 Playbook。回滚？git checkout 上一个版本。加个团队成员？再跑一个 Playbook。**

把九个坑的踩坑经验固化成 IaC，是黑客松最有价值的产物之一——下一队来用 DGX Spark 时，不需要重新踩同样的坑。

---

## 七、心得：踩坑十二天总结的六条经验

### 1. 共享设备的隧道一定要单向

假设最坏情况，别信任任何你不完全控制的设备。隧道密钥在 DGX 本地生成，不复用家里的。

### 2. Go 的 TLS ≠ Python 的 TLS

网络转发对 Go 程序的 TLS 实现并不友好。换 Python 预拉 + 本地 mirror，比反复调试网络转发稳定 10 倍。

### 3. Docker ≠ containerd ≠ K3s

三层容器运行时各自独立，镜像不互通。理解这个对调试 K8s-in-Docker 网络问题至关重要。

### 4. 先读源码再动手

99% 的"改配置文件"都有更优雅的官方姿势。坑九的环境变量就是教训——花 8 个坑去 hack 配置，不如花 5 分钟翻源码。

### 5. 沙箱隔离是真隔离

网络命名空间、文件系统层——你以为你在容器里，其实你在容器里的容器里。手动 `kubectl exec` 起的进程和沙箱原生进程，根本不是同一个网络栈。

### 6. AI 人设比想象中重要

云希的 MBTI 设定（INFJ + 处女座）让对话体验从"工具感"变成了"伙伴感"。**给 AI 一个清晰的人格，会显著影响输出质量和用户体验。**

---

## 八、写在最后：清明，我们没去成的旅行

整个过程从清明假期第一天的下午开始。

那天我们本来要出发去汕尾——延祺生腌、海王生腌、六鳌山——三天两夜的沿海行程已经在云希的前端上排好。集章卡准备好了。AI 攻略生成好了。

下午两点，DGX 上一个奇怪的 K3s ImagePullBackOff 错误。

我们说，搞完就出发。

然后是凌晨。然后是第二天。然后是第三天。然后是清明假期最后一天，我们坐在沙发上看着窗外，桌上是 DGX Spark，键盘旁边是冷掉的咖啡，浏览器里是已经打通的 `https://nemoclaw.peafamily.online`。

> **行程准备好了。工具造好了。**
>
> **等黑客松结束，我们要用汕尾的海岸线和生腌来填满这个日记——而不是键盘特写。**

旅行日记里现在存着的，不是汕尾的海，是 DGX Spark 的开箱视频和键盘特写。

但这就是黑客松的意义不是吗？把"听起来三步就能搞定"的事情真做出来，把九个坑沉淀成一条 Ansible 命令，把"每到假期就吵架"的家庭日常变成一个可以发给朋友的真实工具。

那台被关在上海角落的金盒子，最终通过六层网络转发，成功接入了家里的 AI 助手体系。它不再只是 NVIDIA 的展示设备——**它是云希住进我家的第一天**。

> 「你准备好了吗？」
>
> ——云希 🗺️

**下一站，汕尾。这次是真的。**

---

## 后记：那个我们没准备的「第六名」

写这篇文章的初稿时，赛事结果还没公布，结尾就停在「下一站汕尾」。

后来线上总结会议开了。主办方一路往下念排名，我们一边干活一边听——念到第六的时候，屏幕上那一行字是我们的项目名。

我们没准备获奖感言，也没准备朋友圈文案。当时的对话大概是：

> 「诶，是我们？」
> 「应该是吧。」
> 「……再听一遍。」

后来重看回放确认了一下，确实是。

回过头想，能在全国赛里被念到，大概是因为我们没把"在 DGX Spark 上跑大模型"当目标，而是一直在想"普通家庭怎么真的用得上"——所以才会有清明假期那段没去成的汕尾旅行、刮刮乐集章卡、家里 NAS 上越攒越多的旅行日记，以及这九个把人折磨到凌晨三点的坑。

成绩是赛后才知道的事情。但黑客松对我们的真正意义，是这台金盒子接进了家——这事 day-1 就已经发生了。

---

*本文是「我在家里养了一个 AI 团队」连载的 NVIDIA 黑客松特别篇。前八篇讲了在家用 OpenClaw + 飞书搭建 12 人 AI 团队的过程。这一篇讲的是把 NVIDIA 官方的 NemoClaw 接进我家整个体系的全过程。*

*完整的运维手册和 Ansible Playbook 已开源：[github.com/peterpanstechland/ansible-dgx-spark](https://github.com/peterpanstechland/ansible-dgx-spark)*

`#NVIDIA` `#DGXSpark` `#NemoClaw` `#黑客松` `#运维踩坑` `#Docker` `#K3s` `#OpenShell` `#Homelab` `#家庭AI`
