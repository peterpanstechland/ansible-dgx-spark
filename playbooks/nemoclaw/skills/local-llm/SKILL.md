---
name: local-llm
description: |
  通过 A2A 协议调用 DGX 本地 LLM（Ollama / vLLM）执行推理任务。
  适用场景：翻译、摘要、代码生成、简单问答等不需要 tool calling 的纯文本生成。
  优势：零成本、低延迟、数据不出本地。
  Use when asked about: 本地模型, local model, 用 ollama, 用 vllm, 翻译, translate,
  摘要, summarize, 代码生成, code generation, 简单问答, 免费模型, free model.
---

# Local LLM (本地大模型调用)

通过 A2A (Agent-to-Agent) 协议调用 DGX Spark 上的本地 LLM 后端。

## 何时使用

- 用户明确要求使用本地模型
- 翻译任务（中英、多语言）
- 文本摘要 / 改写
- 代码生成 / 补全（不需要 tool calling 的场景）
- 简单问答（节省云端 API 额度）
- 用户提到 "免费" / "本地" / "ollama" / "vllm" / "gemma"

## 何时不使用

- 需要 tool calling 的复杂任务（用主模型 Nemotron）
- 多轮推理、规划类任务
- 需要联网搜索或调用其他工具的任务

## 可用后端

| 后端 | 模型 | 特点 |
|------|------|------|
| `ollama-fast` | gpt-oss:120b-fast | 通用对话，速度快 |
| `ollama` | gpt-oss:120b | 高质量生成，适合代码 |
| `vllm` | gemma-4-nvfp4 | 快速推理，适合翻译/摘要 |

## 命令

### ask — 向本地模型提问

```bash
node {baseDir}/local-llm.mjs ask --prompt "你的问题"
```

### ask with skill routing — 按任务类型自动选择最佳后端

```bash
node {baseDir}/local-llm.mjs ask --prompt "Translate to English: 今天天气不错" --skill translate
```

### ask with explicit backend — 指定后端

```bash
node {baseDir}/local-llm.mjs ask --prompt "写一个快速排序" --backend ollama
```

参数:
- `--prompt` 提问内容 (必填)
- `--skill` 任务类型: chat, code-gen, summarize, translate (可选, 自动路由)
- `--backend` 显式指定后端: ollama, ollama-fast, vllm (可选, 覆盖 skill 路由)
- `--system` 系统提示词 (可选)
- `--temperature` 温度 0-2 (可选, 默认 0.7)
- `--max-tokens` 最大输出 token 数 (可选, 默认 2048)

### health — 检查后端健康状态

```bash
node {baseDir}/local-llm.mjs health
```

### discover — 查看 A2A Agent Card

```bash
node {baseDir}/local-llm.mjs discover
```

## 配置

- A2A 端点: `http://172.18.0.1:18071` (DGX host)
- 无需 API key（本地服务）

## 注意事项

- 本地模型不支持 tool calling，仅用于纯文本生成
- vLLM (gemma-4-nvfp4) 上下文窗口较小 (16-32K)，不适合超长输入
- 回复内容会标注使用了哪个模型，方便用户了解
