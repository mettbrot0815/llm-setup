# Model Guide

## Choosing a model

The installer auto-recommends based on your VRAM. Here's the full picture:

### By VRAM

| VRAM | Model | Speed | Quality | Best for |
|------|-------|-------|---------|----------|
| 4 GB | `qwen3:0.6b` | ⚡⚡⚡ | ★★☆ | Testing, very fast replies |
| 6 GB | `qwen3:4b` | ⚡⚡⚡ | ★★★ | Daily use, coding |
| 8 GB | `qwen3:8b` | ⚡⚡ | ★★★★ | Good balance |
| 12 GB | `qwen3:14b` | ⚡⚡ | ★★★★ | Recommended — excellent coding |
| 16 GB | `qwen3:30b` | ⚡ | ★★★★★ | Near GPT-4 quality |
| 24 GB+ | `qwen3:32b` | ⚡ | ★★★★★ | Top tier local |

### Specialized models

| Model | Tag | Best for |
|-------|-----|----------|
| Qwen3 Coder | `qwen3-coder:14b` | Pure coding tasks |
| Qwen3 Coder | `qwen3-coder:32b` | Best local coding model |
| Mistral | `mistral:7b` | Fast, general purpose |
| Llama 3 | `llama3.1:8b` | Strong reasoning |
| Phi-4 | `phi4:14b` | Microsoft, great at math |
| DeepSeek | `deepseek-r1:14b` | Reasoning / thinking |
| Gemma 3 | `gemma3:12b` | Google, multimodal |

---

## Managing models

### Switch active model
```bash
llm-switch
```
Interactive picker — shows VRAM fit for each model, marks the current one.

### Download more models
```bash
llm-add
```
Browse the top Ollama models with VRAM requirements shown.

### Pull directly
```bash
ollama pull qwen3:14b
ollama pull qwen3-coder:14b
```

### List installed models
```bash
ollama list
```

### Remove a model
```bash
ollama rm modelname:tag
```

### Check what's currently loaded (and on which device)
```bash
ollama ps
```

---

## Quantization

Ollama models come in different quantizations. The default (no suffix) is Q4_K_M — the best quality-to-size tradeoff. Available suffixes:

| Suffix | Size | Quality | Notes |
|--------|------|---------|-------|
| `:q2_k` | Smallest | ★★☆ | Very lossy |
| `:q4_k_m` | Medium | ★★★★ | **Default — recommended** |
| `:q5_k_m` | Larger | ★★★★★ | Slightly better than q4 |
| `:q8_0` | Large | ★★★★★ | Near fp16 quality |
| `:fp16` | Largest | ★★★★★ | Full quality, needs lots of VRAM |

Example: pull a specific quantization
```bash
ollama pull qwen3:14b-q8_0
```

---

## Import models from file

Have a GGUF model on a USB drive or Windows folder?

```bash
llm-import-models
```

This scans common locations (including `/mnt/c/`) and registers any `.gguf` files with Ollama.

---

## Context window

All models loaded via the coding agents use a 32,768 token context window by default. For very large codebases, some models support up to 128k — check the Ollama model page for details.
