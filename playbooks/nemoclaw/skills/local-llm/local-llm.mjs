#!/usr/bin/env node
/**
 * local-llm.mjs — A2A client for local LLM backends (Ollama / vLLM)
 *
 * Commands:
 *   ask        Send a prompt to a local LLM via A2A protocol
 *   health     Check backend health status
 *   discover   Print the A2A Agent Card
 */

const A2A_BASE = process.env.A2A_LOCAL_LLM_URL || 'http://172.18.0.1:18071';

function flag(args, name) {
  const i = args.indexOf(`--${name}`);
  if (i === -1 || i + 1 >= args.length) return undefined;
  return args[i + 1];
}

async function a2aSend(prompt, opts = {}) {
  const body = {
    jsonrpc: '2.0',
    id: `req-${Date.now()}`,
    method: 'message/send',
    params: {
      message: { parts: [{ kind: 'text', text: prompt }] },
      ...(opts.skill ? { skill: opts.skill } : {}),
      metadata: {
        ...(opts.backend ? { backend: opts.backend } : {}),
        ...(opts.systemPrompt ? { systemPrompt: opts.systemPrompt } : {}),
        ...(opts.temperature !== undefined ? { temperature: parseFloat(opts.temperature) } : {}),
        ...(opts.maxTokens !== undefined ? { maxTokens: parseInt(opts.maxTokens) } : {}),
      },
    },
  };

  const resp = await fetch(`${A2A_BASE}/a2a`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(120_000),
  });

  if (!resp.ok) {
    throw new Error(`A2A request failed: HTTP ${resp.status} ${await resp.text()}`);
  }

  const data = await resp.json();

  if (data.error) {
    throw new Error(`A2A error ${data.error.code}: ${data.error.message}`);
  }

  const text = data.result?.artifacts?.[0]?.parts?.[0]?.text;
  if (!text) throw new Error('No text in A2A response');
  return text;
}

async function cmdAsk(args) {
  const prompt = flag(args, 'prompt');
  if (!prompt) {
    console.error('Usage: local-llm.mjs ask --prompt "..." [--skill chat|code-gen|summarize|translate] [--backend ollama|ollama-fast|vllm]');
    process.exit(1);
  }

  const result = await a2aSend(prompt, {
    skill: flag(args, 'skill'),
    backend: flag(args, 'backend'),
    systemPrompt: flag(args, 'system'),
    temperature: flag(args, 'temperature'),
    maxTokens: flag(args, 'max-tokens'),
  });

  console.log(result);
}

async function cmdHealth() {
  const resp = await fetch(`${A2A_BASE}/health`, { signal: AbortSignal.timeout(10_000) });
  const data = await resp.json();
  console.log(JSON.stringify(data, null, 2));
}

async function cmdDiscover() {
  const resp = await fetch(`${A2A_BASE}/.well-known/agent.json`, { signal: AbortSignal.timeout(10_000) });
  const card = await resp.json();
  console.log(JSON.stringify(card, null, 2));
}

async function main() {
  const args = process.argv.slice(2);
  const cmd = args[0];

  switch (cmd) {
    case 'ask': return cmdAsk(args);
    case 'health': return cmdHealth();
    case 'discover': return cmdDiscover();
    default:
      console.log(`local-llm — A2A client for local LLM backends

Commands:
  ask        Send a prompt to a local LLM
    --prompt     The prompt text (required)
    --skill      Task type: chat, code-gen, summarize, translate
    --backend    Explicit backend: ollama, ollama-fast, vllm
    --system     System prompt
    --temperature  Temperature (0-2, default 0.7)
    --max-tokens   Max output tokens (default 2048)
  health     Check backend health
  discover   Print A2A Agent Card`);
  }
}

main().catch(e => {
  console.error(`Error: ${e.message}`);
  process.exit(1);
});
