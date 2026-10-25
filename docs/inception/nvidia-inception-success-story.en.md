# NemoClaw Travel OS: A Production-Grade Private Family AI on NVIDIA DGX Spark

> NVIDIA Inception Success Story · 2026-04
> Submitted by: "Be Friends" Team / Shenzhen Mecha Spirit Technology Co., Ltd.

---

## 1. Case Introduction / 案例简介

### English (~50 words)

- In this case, the **"Be Friends" Team / Shenzhen Mecha Spirit Technology Co., Ltd.** built **NemoClaw Travel OS** **for their own household** — a private family AI travel assistant running 120-billion-parameter LLMs on living-room hardware with zero cloud dependency — on **NVIDIA DGX Spark** with native **NVFP4** precision. The team is both the developer and the first customer; the entire stack is open-sourced to the community.
- The major NVIDIA products utilized are **NVIDIA DGX Spark (GB10 Grace Blackwell Superchip)**, the **NemoClaw safe-sandbox**, and **NVFP4 quantization**.

### 中文（约 50 字）

- 本案例中，「交个朋友」团队 / 深圳市机甲之灵科技有限公司 团队基于 **NVIDIA DGX Spark + NVFP4 原生精度**，**为自家**构建了在客厅运行 1200 亿参数大模型的私有化 AI 旅行助手 **NemoClaw Travel OS**——客户即团队本身，自研自用并开源给社区。
- 本案例主要应用 **NVIDIA DGX Spark（GB10 Grace Blackwell）**、**NemoClaw 安全 AI 沙箱** 和 **NVFP4 量化精度**。

![NemoClaw Travel OS cover: NVIDIA DGX Spark on a living-room wood table, surrounded by NVIDIA-green neural-network nodes](images/nemoclaw-2026-04.jpg)

> **Cover image spec**: 1278 × 680, JPG, no embedded text ｜ Filename per NVIDIA Inception template: `companyname-year-month.jpg`

---

## 2. Customer Profile and Application Background

> **The customer in this case is the team itself** — "Be Friends" is an OPC paired with a cluster of home servers, a hands-on homelab team using **NVIDIA DGX Spark** to solve real pain points in their own household first, then open-sourcing the entire stack to the community. This is a textbook **"build-for-self + open-source"** pattern within NVIDIA Inception.

The "Be Friends" Team is composed of homelab and AI-Agent practitioners. They have long run their multi-agent automation framework **OpenClaw** on a home server cluster, and publish the ongoing technical column *I Built an AI Team at Home*. The team's mission: **make enterprise-grade AI compute work in real household scenarios with production-grade engineering**.

The story did not begin with market research. It began with a **real conversation in the living room two weeks before the 2026 Qingming holiday in China**:

> "Shanwei?" "Three hours each way for three days off — pass."
> "Camping?" "Typhoon fringe, raining all three days."
> "Huizhou?" "We've been seven, eight times already."
> "Then where do you want to go?" "...Forget it, let's just stay home."

That recurring "where do we go?" script, replayed every long weekend, is what truly catalyzed NemoClaw Travel OS for this household. What the family needed was not yet another cloud travel app — **the family's itinerary, home address, spending habits, and restaurant preferences are all private data they refuse to upload anywhere** — but a long-term private AI travel assistant running locally in the family's own living room, tuned to family preferences over time.

![The recurring "where do we go?" scene at home — every suggestion gets shot down](images/couple-vacation-dilemma.jpg)

But making this work surfaced a very specific set of household engineering constraints:

- A model that genuinely understands "what my partner is asking and what my spouse will accept" needs **at least 100B+ parameters** — and this simply could not run inside a living room before DGX Spark.
- Three family accounts in concurrent use, plus integrations with Feishu / Xiaohongshu / Amap maps — single-card consumer GPU memory fills up after just one model.
- The home network egress, home NAS, and home router need to integrate seamlessly — no one will manually maintain this every day.

**NVIDIA DGX Spark brought consumer-grade AI compute down to the living room** — 128GB unified memory + GB10 Grace Blackwell Superchip + native NVFP4 precision means a 120-billion-parameter model finally runs at conversational speed on a living-room desk. Built on this gold box, the "Be Friends" Team developed NemoClaw Travel OS for the **NVIDIA DGX Spark Hackathon 2026**, validated it across three family accounts at home, and placed **6th in the national finals** — making this stack reproducible by any homelab enthusiast with the same "private family AI" need.

---

## 3. Customer Challenges

The "Be Friends" Team, as the customer and first user of NemoClaw Travel OS, encountered five interlocking real challenges in their own household scenario:

1. **Family privacy cannot go to the cloud** — The household's travel preferences, home address, spending habits, restaurant tastes, and family-member participation in trips are highly sensitive data. Conventional travel apps and cloud LLM APIs all require uploading this data to third-party servers — a non-starter for the team.

2. **More than one model has to run at home** — A travel assistant that can truly "understand the partner's nuanced requests" needs at least a 100B+ parameter primary conversation model (Yunxi), plus a multimodal vision model for organizing photos and extracting travel-guide screenshots, plus a small low-latency response model. **The team's prior RTX-class consumer GPU could only fit one model at a time** — making the household's multi-task scenario infeasible.

3. **Three family accounts must run concurrently** — husband, wife, and a shared account simultaneously planning trips through Feishu, drafting Xiaohongshu seed content with the social-media skill, and analyzing photos with Gemma 4. Any single "model is queueing, conversation slowing down" event would cause the family to abandon the tool immediately.

4. **The home networking stack explodes in complexity** — getting DGX Spark integrated into the home stack involves: encrypted tunnels back to the home router, the home NAS as long-term storage, domain reverse-proxying to Feishu / Xiaohongshu / Amap, Docker registry caching (the home-to-overseas registry pull experience is poor), TLS interception with re-signing, K3s multi-model serving, NodePort forwarding... the entire Qingming holiday was consumed by nine different layers of operational pain.

![Qingming holiday debug scene at home: three days that should have been spent traveling were instead spent on the DGX Spark, debugging encrypted tunnels, registry caches, and concurrent multi-model serving](images/qingming-debug-scene.jpg)

5. **"Usable at home" is a higher bar than "demo runs"** — Most NVIDIA hardware demos stop at "the model runs." Reaching the bar of **"my partner actually wants to use this every day, and the family keeps using it long term"** requires at least an order-of-magnitude more engineering: one-command deployment, auto-restart, health monitoring, data backup, sustainable daily home operation. This is the gap between a hardware demo and a long-term household production tool.

---

## 4. Application Solution

When building NemoClaw Travel OS for their own household, the "Be Friends" Team **directly adopted NVIDIA DGX Spark hardware + NVIDIA's official [build.nvidia.com/spark](https://build.nvidia.com/spark) Playbook stack as the foundation**, then layered in a self-developed engineering layer to close the last mile. The full solution structure is as follows:

### 4.1 Hardware Platform: NVIDIA DGX Spark

| Configuration | Specification |
| --- | --- |
| Superchip | **GB10 Grace Blackwell Superchip** |
| Unified Memory | **128GB** (CPU + GPU shared, single address space) |
| Native Precision | **NVFP4** (Blackwell hardware-level acceleration, not software compression) |
| Form Factor | Desktop-class — no datacenter required, fits in a living room |
| Software Stack | Ubuntu 24.04 ARM64 + NVIDIA drivers + containerd + K3s |

### 4.2 Multi-Model Concurrent Inference (Core Technical Highlight)

DGX Spark's **128GB unified memory** lets NemoClaw Travel OS achieve something previously possible only inside datacenters — **a single desktop-class machine simultaneously providing OpenAI-compatible APIs for multiple models serving different tasks**.

| Model | Parameter Scale | Quantization | GPU Memory | Inference Engine | Role |
| --- | --- | --- | --- | --- | --- |
| **gpt-oss:120b-fast** (Nemotron-compatible) | 116.8B | MXFP4 | ~66GB | Ollama | Primary conversation & itinerary planning |
| **Gemma-4-31B-IT-NVFP4** | 31B | **NVFP4 (W4A4)** | ~31GB | vLLM | Multimodal vision understanding |
| **gpt-oss:20b** | 20B | MXFP4 | ~12GB | Ollama | Low-latency real-time feedback |

**Measured Comparison:**

| Metric | Conventional Consumer Solution | DGX Spark + NemoClaw Solution | Improvement |
| --- | --- | --- | --- |
| Concurrent 100B+ parameter models | **1** (single-card memory ceiling) | **2 + 1×20B coexist** | **3×** |
| 120B model first-token latency (default reasoning enabled) | / | ~20s | Baseline |
| 120B model first-token latency (`gpt-oss:120b-fast`, reasoning off) | / | **< 2s** | **~10× user-perceived response speed** |
| 32K context-window sustained dialogue stability | Not feasible | **Stable** | Now usable |
| Cold start (default keep_alive 5-min expiry reload) | ~20s+ cold load | **`keep_alive=-1`, GPU-resident** | Near-zero cold start |
| Vision-model quantization precision | INT4 (lossy) | **NVFP4 hardware-native** | Blackwell-native acceleration |

### 4.3 NemoClaw Safe-Sandbox + OpenShell

NemoClaw is NVIDIA's official **safe AI-assistant sandbox** for DGX Spark, providing Linux-namespace–level tool-call isolation built on K3s + OpenShell. The "Be Friends" Team's OpenClaw multi-agent framework (**Yunxi** — INFJ Virgo travel-planner persona) runs on top of NemoClaw — every model tool call, file operation, and external API communication is forced through OpenShell-proxy with TLS interception and re-signing — **enterprise-grade security without sacrificing development velocity**.

> NemoClaw is the **#1 recommended quickstart** under "First Time Here?" on [build.nvidia.com/spark](https://build.nvidia.com/spark). This case is built on top of and extends the official Playbook.

### 4.4 One-Command Deployment: Ansible Playbook

The "Be Friends" Team encapsulated the entire kernel-to-application complexity into **a single Ansible command**:

```bash
ansible-playbook playbooks/nemoclaw/site.yml
```

**This one command handles:**

- Installing Ollama and pulling `gpt-oss:120b-fast`
- Deploying NemoClaw + OpenShell sandbox
- Starting vLLM + Gemma 4 NVFP4
- Deploying Travel App (Express + SQLite + Amap MCP)
- Configuring encrypted tunnels and DNAT rules
- Configuring Docker registry caches (resolving overseas-registry egress issues)
- Setting up auto-update and health monitoring

**Deployment Efficiency:**

| Stage | Time | Description |
| --- | --- | --- |
| Manual deployment before hackathon (9 production-grade ops issues) | ~ **3 full days** (entire Qingming holiday) | Containers, encrypted tunnels, TLS re-sign, registry mirrors, multi-model coexistence — debugged one by one |
| Re-deployment via Ansible | ~ **2 minutes** | `curl https://nemoclaw.peafamily.online/` → **200** |
| Engineering efficiency lift | **~1000×** | Nine debug sessions distilled into one command |

---

## 5. Outcomes and Impact

### 5.1 Household Validation

- **For the first time, the "where do we go?" Qingming script had an answer** — Yunxi (the travel persona on NemoClaw) produced a full 3-day-2-night Shenzhen-to-Shanwei itinerary in 3 minutes — including weather cross-validation, typhoon-fringe risk for April 17–19, locally-rated raw seafood restaurants, scratch-card stamp collection, and daily guides. After dozens of "let's just stay home" outcomes, this was the first plan both partners actually agreed on.

![Yunxi's 3-minute itinerary, Shenzhen → Shanwei, 3 days / 2 nights — with weather cross-validation, restaurants, attractions, and one-tap navigation](images/shanwei-trip-map.png)

- **3 family accounts, concurrent operation for a week with no slowdown** — During household testing: the husband's account using Yunxi in Feishu for itinerary planning, the wife's account drafting Xiaohongshu seed content, and the shared account using Gemma 4 NVFP4 vision to organize travel photos. Three concurrent paths sustained over a full week — **no query slowed down**. This is unattainable on any prior single-card consumer GPU at home.
- **Zero long-term operational cost at home** — The first manual deployment took the full 3-day Qingming holiday; encapsulated as an Ansible Playbook, the next deploy ran in ~2 minutes — and every subsequent upgrade, rollback, and migration is one command.

### 5.2 Industry-Level Impact

While NemoClaw Travel OS originated from household needs, the project also earned NVIDIA's official recognition and community amplification at the industry level:

- **Placed 6th in the NVIDIA DGX Spark Hackathon 2026 national finals** — singled out by NVIDIA officials into TOP 6 from 40+ participating teams
- We hope to be **enrolled into the NVIDIA DGX Spark Official Project Case Library** — so any homelab enthusiast with the same "private family AI" need can directly reproduce this from open-source repositories
- **The full kernel-to-application deployment Playbook is fully open-sourced** — providing a reproducible engineering pattern for consumer-grade NVIDIA hardware in family AI applications

### 5.3 Customer Quote

> **"This isn't a product built for someone else — this is the tool our household uses every day. The day my partner asked 'where should we go this year' two weeks before Qingming, was the day I decided to do something on this NVIDIA DGX Spark.**
>
> **128GB unified memory let me run two 100B+ models simultaneously — one understanding my partner's needs, one organizing photo memories — something genuinely impossible on the family's prior RTX 4090 single card. NVFP4 is not just compression — it's a precision format natively supported by the Blackwell architecture, letting a 120B-parameter model run at conversational speed in the living room.**
>
> **The moment I really understood what DGX Spark changes — was the day my partner spontaneously asked, 'let's have Yunxi plan a Dragon Boat Festival trip too.' A household tool being voluntarily invoked by a family member tells you more than any benchmark.**
>
> **NVIDIA DGX Spark didn't help us produce yet another 'AI travel app' — it gave our household its first AI assistant that truly belongs to us."**
>
> **— PeterPan, "Be Friends" Team Lead / Co-user of NemoClaw Travel OS**
> *NVIDIA Inception candidate member; author of the OpenClaw multi-agent framework; column author of *I Built an AI Team at Home**

---

## 6. NVIDIA Inception Program

The "Be Friends" Team is a candidate member of **NVIDIA Inception**. NVIDIA Inception is a free membership program designed to nurture startups disrupting their industries. It partners with leading domestic and global VC firms, incubators, accelerators, industry partners, and tech media to build a startup-acceleration ecosystem, providing benefits including product discounts, technical support, marketing exposure, financing introductions, and business referrals — all to accelerate startup growth.

> Want help from the NVIDIA Inception ecosystem? Scan the official NVIDIA QR code below and complete the one-minute interest application form for fast follow-up.

---

## 7. Authorization Statement

**"Be Friends" Team / Shenzhen Mecha Spirit Technology Co., Ltd.** (please fill in the company name to confirm) authorizes NVIDIA to use this case content for marketing purposes, including channels such as the NVIDIA and partner official websites, Chinese social platforms (WeChat / Weibo / Toutiao), and media outlets (you may strike this through if you have media-channel concerns). Any modifications to the substantive content of the case must be sent back for client confirmation.

---

## 8. Partner Information (for NVIDIA partner-channel marketing only)

> **About the special nature of this case**: This case follows a "build-for-self + open-source" model — the customer, developer, and partner are the same entity ("Be Friends" Team / Shenzhen Mecha Spirit Technology Co., Ltd.). The team is both the end user of NVIDIA DGX Spark and the provider of the NemoClaw Travel OS solution. The "partner" fields below are filled with the same entity, presented from the self-developed perspective.
>
> The following content is for NVIDIA partner-channel marketing only.

| Field | Content |
| --- | --- |
| **Partner Company Name** | "Be Friends" Team / Shenzhen Mecha Spirit Technology Co., Ltd. |
| **Partner Company Profile** (~50 words) | NVIDIA Inception candidate member, a hands-on team focused on Homelab + AI-Agent private deployment. Self-developed OpenClaw multi-agent framework and OpenShell safe sandbox; long-term operation of family-grade AI automation ecosystems on NVIDIA GPUs and edge devices. |
| **Partner-Provided Solution and Role in This Case** (≤ 300 words) | The "Be Friends" Team — as both developer and first user of NemoClaw Travel OS (customer = developer) — built a complete private AI travel operating system on NVIDIA DGX Spark, using the official [build.nvidia.com/spark](https://build.nvidia.com/spark) Playbook as the foundation **for their own household**, and then open-sourced the full stack to communities of families and homelab enthusiasts with the same need. The team designed the OpenClaw-based multi-agent architecture (Yunxi — INFJ Virgo travel-planner persona) and authored a complete Ansible one-command deployment Playbook, distilling 9 production-grade ops challenges (encrypted tunnels, Docker registry caching, TLS interception/re-sign, multi-model coexistence, K3s NodePort forwarding, Nginx domain reverse proxy, etc.) into one command. The 5-step travel loop (Understand → Plan → Travel → Record → Publish) was built on top of the NemoClaw sandbox, and integrated with Amap MCP for real-world navigation. After in-house validation across three family accounts followed by open-sourcing, the project demonstrates that DGX Spark can simultaneously serve multiple 100B-parameter models, that NVFP4 native precision can substantially boost multimodal inference throughput, and that Ansible-ized deployment can make it ready-to-run for households — providing a reproducible engineering pattern for family AI on consumer-grade NVIDIA hardware. |

---

## Appendix: Open-Source Repositories and References

| Resource | Link |
| --- | --- |
| Ansible Playbook Repository | [github.com/peterpanstechland/ansible-dgx-spark](https://github.com/peterpanstechland/ansible-dgx-spark) |
| Travel App + Skill Repository | [github.com/peterpanstechland/nemoclaw-travel-planner](https://github.com/peterpanstechland/nemoclaw-travel-planner) |
| NVIDIA Official DGX Spark Playbooks | [build.nvidia.com/spark](https://build.nvidia.com/spark) |
| Project Blog (Chinese) | [peterpanstechland.github.io/zh-Hans/docs/hackathons/2026/nvidia-dgx-spark](https://peterpanstechland.github.io/zh-Hans/docs/hackathons/2026/nvidia-dgx-spark) |
| Project Blog (English) | [peterpanstechland.github.io/docs/hackathons/2026/nvidia-dgx-spark/](https://peterpanstechland.github.io/docs/hackathons/2026/nvidia-dgx-spark/) |

---

*Document version: v1.0 · 2026-04*
*File location: `hackathon/nvidia/ansible-dgx-spark/docs/inception/nvidia-inception-success-story.en.md`*
*Chinese counterpart: `nvidia-inception-success-story.md`*
