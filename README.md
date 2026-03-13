# llm-setup

> One command. Full local AI stack. WSL2 + NVIDIA, no fuss.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/mettbrot0815/llm-setup/main/install.sh)
```

---

## What it installs

| Component | What | Why |
|-----------|------|-----|
| **Ollama** | Local model runtime | Serves LLMs via API |
| **oterm** | Terminal chat UI | Talk to your models instantly |
| **MCP bridges** | time + filesystem tools *(optional)* | Let models call real tools during chat |
| **qwen-code** | Qwen coding agent | Free cloud tier + local fallback |
| **codex** | OpenAI Codex CLI | Local via Ollama or cloud |
| **aider** | AI pair programmer | Git-aware coding assistant |
| **claude-code** | Claude CLI agent | Anthropic cloud or local proxy |

Everything is wired together out of the box. All agents auto-start Ollama before launching — no manual `ollama serve` needed.

---

## Requirements

- **OS**: Ubuntu 22.04 / 24.04 (native or WSL2)
- **GPU**: NVIDIA with ≥ 8 GB VRAM (6 GB works for small models)
- **RAM**: 8 GB minimum, 16 GB recommended
- **Disk**: 10 GB free minimum (models are separate)
- **Internet**: Required during install, optional after

> **WSL2 on Windows?** This is the primary target. See the [WSL2 setup guide](docs/wsl2-setup.md).

---

## Quick start

### Fresh machine (one command)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/mettbrot0815/llm-setup/main/install.sh)
```

This will:
1. Detect your hardware (GPU, VRAM, CPU, RAM)
2. Install Python, Node, Ollama, CUDA tools
3. Ask you which model to pull (or skip for later)
4. Ask which chat UI to install
5. Ask which coding agents to install
6. Optionally install MCP tool bridges
7. Add all commands to your PATH

### Clone and run locally

```bash
git clone https://github.com/mettbrot0815/llm-setup
cd llm-setup
./install.sh
```

---

## After install

```
chat          # open oterm terminal chat UI
qwen-code     # Qwen coding agent  (alias: qc)
codex         # Codex CLI          (alias: cx)
aider         # Aider AI coder     (alias: code)
claude-code   # Claude CLI         (alias: cc)

llm-switch    # change active model
llm-add       # download more models
llm-doctor    # diagnose your setup
llm-fix       # auto-repair common issues
llm-update    # upgrade all components
llm-mcp-start # install + start MCP tool bridges (optional, first run auto-installs)
```

---

## Models

The installer recommends a model based on your VRAM. You can always change it:

```bash
llm-switch           # interactive picker
llm-add              # browse + download more models
ollama pull qwen3:14b  # or pull directly
```

**Rough VRAM guide:**

| VRAM | Recommended | Notes |
|------|-------------|-------|
| 6 GB | `qwen3:4b` | Fast, capable |
| 8 GB | `qwen3:8b` | Good balance |
| 12 GB | `qwen3:14b` | Excellent for coding |
| 16 GB+ | `qwen3:30b` | Near-GPT-4 quality |
| 24 GB+ | `qwen3:32b` | Top tier |

---

## Chat UIs

### oterm (default — terminal, instant)

```bash
chat
```

A beautiful TUI that runs in your terminal. No browser needed.

### qwen-code

```bash
qc                  # start (uses free Qwen cloud + local fallback)
```

Free cloud tier: 1,000 requests/day. Falls back to local Ollama automatically.

### Codex

```bash
cx                  # local Ollama
OPENAI_API_KEY=sk-... cx   # OpenAI cloud
```

### Aider

```bash
code                # local Ollama, run from your project folder
```

### Claude Code

```bash
cc                  # uses LiteLLM proxy → Ollama, or Anthropic cloud
```

---

## Re-running the installer

The installer is **idempotent** — re-running it skips anything already installed. Safe to run after a failed install or to add new components.

```bash
cd ~/llm-setup && ./install.sh
# or simply:
llm-setup
```

---

## Troubleshooting

```bash
llm-doctor          # full diagnostic report
llm-fix             # attempt to auto-fix common issues
```

**GPU not detected / running on CPU:**
```bash
fix-gpu             # patches Ollama systemd service
```

**MCP bridges not installed / down:**
```bash
llm-mcp-start   # first run installs automatically
```

**Model loads on CPU instead of GPU:**
```bash
fix-gpu
```

See [docs/troubleshooting.md](docs/troubleshooting.md) for more.

---

## Project structure

```
llm-setup/
├── install.sh          # main entry point
├── lib/
│   ├── ui.sh           # colors, step headers, live progress bars
│   ├── detect.sh       # hardware detection (GPU, VRAM, CPU, RAM)
│   ├── catalog.sh      # auto-updating model catalog from ollama.com
│   ├── gpu-ensure.sh   # ensures Ollama uses GPU before any agent
│   ├── paths.sh        # canonical path definitions
│   └── util.sh         # shared helpers
├── steps/
│   ├── 01-preflight.sh # apt packages, uv, PATH setup
│   ├── 02-python.sh    # Python venv + pip
│   ├── 03-node.sh      # nvm + Node.js LTS
│   ├── 04-ollama.sh    # Ollama runtime
│   ├── 05-cuda.sh      # CUDA toolkit (NVIDIA only)
│   ├── 06-model.sh     # model selection + pull
│   ├── 07-openwebui.sh # chat UI (oterm)
│   ├── 08-mcp.sh       # MCP bridges — optional, y/N prompt during install
│   ├── 09-tools.sh     # install CLI tools to ~/.local/bin
│   ├── 10-aliases.sh   # shell aliases (qc, cx, code, cc, chat)
│   ├── 11-agents.sh    # coding agents (qwen-code, codex, aider, claude)
│   └── 12-validate.sh  # post-install health check
└── tools/
    ├── qwen-code        # Qwen Code wrapper (cloud + local)
    ├── codex            # Codex CLI wrapper
    ├── aider            # Aider wrapper
    ├── claude-code      # Claude Code wrapper + LiteLLM proxy
    ├── llm-switch       # interactive model switcher
    ├── llm-add          # model browser + downloader
    ├── llm-doctor       # diagnostic tool
    ├── llm-fix          # auto-repair tool
    ├── llm-update       # upgrade all components
    ├── llm-mcp-start    # start MCP bridges
    ├── llm-mcp-stop     # stop MCP bridges
    ├── llm-chat-ui      # install / switch chat UI
    └── fix-gpu          # GPU enforcement tool
```

---

## License

MIT — do whatever you want with it.

---

*Built for WSL2 + RTX 3060, tested on Ubuntu 24.04.*
*Contributions welcome.*
