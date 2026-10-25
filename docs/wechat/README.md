# DGX Spark 黑客松微信公众号推文

> NVIDIA DGX Spark Hackathon 2026 · 团队「交个朋友」· NemoClaw Travel OS

本目录存放黑客松配套的两篇微信公众号推文，参考 Dify 那篇 [《Dify 开箱 NVIDIA DGX Spark》](https://mp.weixin.qq.com/s/C76KJHftSxFT5hiX4N2anA) 的格式 + NVIDIA Inception 成功故事模板的结构。

---

## 文件结构

| 文件 | 用途 | 字数 | 受众 |
|------|------|------|------|
| `01-project-intro.md` | 项目介绍推文（NemoClaw Travel OS 是什么） | ~3500 字 | 想了解产品 / 想部署私有 AI 的开发者 |
| `02-hackathon-experience.md` | 赛事体验推文（黑客松踩坑 + 心得） | ~4000 字 | 关注 Homelab / 想看真实折腾过程的读者 |

两篇文章可独立阅读，也可作为系列推送（建议先发**项目介绍**，再发**赛事体验**，形成"先认识产品，再看背后故事"的阅读节奏）。

---

## 配图清单

> 微信公众号编辑器需要手动上传图片。下面列出每篇推文需要的配图位置，建议从 `personalblog/static/img/hackathons/2026/` 复制原图。

### 01-project-intro.md 配图清单

| 位置 | 文件名（已存在） | 描述 | 备选 |
|------|------------------|------|------|
| 第一段后 | `dgx-spark-hardware.jpg`（需补拍） | DGX Spark 硬件特写——黑色金属外壳，宣示"桌面级超算"质感 | 用 NVIDIA 官方产品图代替 |
| 第二节末 | `shanwei-trip-map.png` | 云希为夫妻规划的汕尾三天两夜行程地图 | — |
| 第三节末 | `nemoclaw-ui.png`（需截图） | NemoClaw 沙箱内 OpenClaw Gateway UI 截图 | 用 [travel-spark.peafamily.online](https://travel-spark.peafamily.online) 截图代替 |
| 第六节 · 第一步 | `feishu-conversation.png`（需截图） | 飞书对话截图——用户告诉云希要去汕尾 | — |
| 第六节 · 第二步 | `ai-guide.png` | travel-spark 前端 AI 攻略截图 | — |
| 第六节 · 第三步 | `stamp-card.png` | 刮刮乐集章卡 + 成就徽章系统 | — |
| 第六节 · 第四步 | `travel-diary.png` | 旅行日记界面——含 DGX Spark meta 入镜 | — |

### 02-hackathon-experience.md 配图清单

| 位置 | 文件名 | 描述 | 备选 |
|------|--------|------|------|
| 开篇对话后 | `couple-vacation-dilemma.png` | 夫妻假期争吵插画 | — |
| 第三节末（坑九后） | `nemoclaw-success.png`（需截图） | NemoClaw 沙箱在域名下成功跑通的截图 | NPM dashboard 显示 200 OK 也行 |
| 第五节中（多模型） | `htop-or-nvidia-smi.png`（建议补） | DGX Spark 上同时跑 Ollama + vLLM 的 nvidia-smi 截图 | 可以用 `ollama ps` 输出 |
| 结尾段 | `couch-with-dgx.jpg`（建议补拍） | 沙发 + DGX Spark + 冷咖啡的"清明现场"照片 | 用 DGX Spark 与键盘特写代替 |

---

## 微信公众号格式调整建议

由于原文是 Markdown，发布到微信公众号时需要做几处适配：

### 1. 代码块

微信公众号原生不支持 Markdown 代码块高亮。建议：

- **方案 A**：用 [Markdown Nice](https://editor.mdnice.com/) 编辑器粘贴，自动转换。
- **方案 B**：截图代码（用 Carbon 或 Ray.so）替代纯文本代码块，视觉效果更好。

### 2. 表格

微信公众号支持基本的 HTML 表格。Markdown Nice 可以正确渲染。如果手动调整：
- 表格不要超过 4 列（手机端易溢出）
- 列宽分配可用 `<colgroup>` 控制

### 3. 引用块

`> 引用` 在 Markdown Nice 默认主题下会变成左侧绿色竖线 + 浅灰背景，已经很 OK。云希的台词可以用引用块单独高亮。

### 4. 标题层级

- 一级标题 (`#`)：仅作文章标题，公众号编辑器自动作为标题
- 二级标题 (`##`)：章节标题，建议用粗体大字 + 颜色区分
- 三级标题 (`###`)：小节标题
- 四级标题 (`####`)：尽量避免，公众号视觉上层级太多容易乱

### 5. emoji

微信公众号对 emoji 支持完整。**建议保留所有 emoji**，对中文读者的视觉引导效果好。

### 6. 链接处理

微信公众号原文链接会被转换成"阅读原文"或丢弃。建议：

- 关键链接（GitHub、build.nvidia.com）放在文末"相关资源"区块
- 域名（如 `travel-spark.peafamily.online`）作为纯文本展示，配上二维码图片

---

## 发布前 Checklist

- [ ] 确认所有 `[图片：xxx]` 占位符已替换为实际图片
- [ ] GitHub 链接、build.nvidia.com 链接全部可点击
- [ ] 团队介绍部分核对成员名字 / 角色无误
- [ ] 文末加上"原文阅读跳转博客"或"扫码关注"二维码（个人博客 [peterpanstechland.github.io](https://peterpanstechland.github.io)）
- [ ] 标题党 / 摘要 / 封面图三件套备齐：
  - 推文 1 标题：`NemoClaw Travel OS 开箱 NVIDIA DGX Spark：把 1200 亿参数搬进客厅，造一个有灵魂的旅行 AI`
  - 推文 1 摘要：`一台 DGX Spark + Ansible 一条命令 = 全家共享的私有化 AI 旅行 OS。Nemotron 120B + Gemma 4 NVFP4 + vLLM 多模型本地编排。`
  - 推文 1 封面：建议用 DGX Spark 硬件 + 汕尾行程地图的拼图
  - 推文 2 标题：`我们参加了 NVIDIA 黑客松，给了一台被关在上海角落的金盒子，结果用它规划了一趟没去成的清明假期`
  - 推文 2 摘要：`九个坑、六层网络转发、十二天清明 debug——一份从 SSH 到生产可用的 DGX Spark 部署实录。最后一个坑的答案，是一个环境变量。`
  - 推文 2 封面：建议用 DGX Spark + 键盘特写 + "清明假期" 文字的现场照

---

## 推送节奏建议

### 方案 A：双连发（适合赛后推广）

- **Day 1**（建议周二/周四晚 8 点）：发**项目介绍推文**——先让读者认识产品
- **Day 3**：发**赛事体验推文**——讲背后故事，制造连续性话题

### 方案 B：单发主推（适合时间紧）

- 只发**项目介绍推文**，把赛事体验作为博客原文链接附在文末。
- 优势：单条阅读量更集中
- 劣势：赛事踩坑那部分内容很有传播力，单发可能浪费

### 方案 C：合并成长文（适合一次说完）

把两篇按"先经历，再产品"的顺序合并：
1. 用赛事体验前半段（清明对话 + 接到金盒子）开场
2. 切到项目介绍（NemoClaw Travel OS 是什么）
3. 中间穿插"我们怎么搭出来的"（赛事体验九个坑摘要）
4. 用赛事体验结尾（清明没去成）收尾

适合做"年终总结"或"项目复盘"型长文，约 5500-6000 字。

---

## 与个人博客的关系

两篇推文的内容大量参考了：
- [`personalblog/peterpanstechland.github.io/i18n/zh-Hans/.../hackathons/2026/nvidia-dgx-spark.md`](../../../../personalblog/peterpanstechland.github.io/i18n/zh-Hans/docusaurus-plugin-content-docs/current/hackathons/2026/nvidia-dgx-spark.md)（项目介绍博客原文）
- [`playbooks/openclaw/blog-posts/10-nemoclaw-on-dgx-spark.md`](../../../../playbooks/openclaw/blog-posts/10-nemoclaw-on-dgx-spark.md)（连载第十篇——黑客松踩坑实录）
- [`hackathon/nvidia/ansible-dgx-spark/docs/nemoclaw-dgx-spark.md`](../nemoclaw-dgx-spark.md)（运维手册）

公众号推文是**面向更广泛读者的二次创作**，删除了大量运维细节、保留情感叙事和核心技术点。读者如果想深入，可以通过文末链接跳转到博客和 GitHub 仓库。

---

## NVIDIA Inception 成功故事模板对照

> 由于本地无法访问用户提供的 Windows 路径下的 docx 模板（`c:\Users\Twink\OneDrive\xwechat_files\...\NVIDIA Inception- Success Story Template for partner_2023.docx`），本目录的项目介绍推文按照 NVIDIA Inception 公开使用的成功故事结构编写：

| Inception 成功故事章节 | 对应推文 1 章节 |
|------------------------|------------------|
| Company Overview / 公司介绍 | 第九章「关于交个朋友团队和 NemoClaw Travel OS」 |
| Business Challenge / 业务挑战 | 开头夫妻对话（家庭旅行规划痛点） |
| The Solution / 解决方案 | 第二章「产品介绍」 + 第三章「部署架构」 |
| NVIDIA Technologies Used | 第一章 DGX Spark 硬件 + 第五章多模型 A2A |
| Implementation Details | 第四章「关键实施步骤」 |
| Business Results / 业务成果 | 第六章「应用场景」 + 第八章「成本对比」 |
| Future Outlook / 未来展望 | 第十章「写在最后」 |

如果用户后续能提供 docx 原文内容，可以再做精细化调整。
