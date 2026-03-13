# Troubleshooting

Run the diagnostic tool first — it checks everything and tells you what's wrong:

```bash
llm-doctor
```

---

## GPU issues

### Model running on CPU

Symptoms: slow generation, `ollama ps` shows `100% CPU`

```bash
fix-gpu          # patches Ollama systemd + restarts it
llm-doctor       # verify GPU is active
```

Manual check:
```bash
ollama ps        # should show GPU%, not 100% CPU
nvidia-smi       # should show Ollama process using VRAM
```

### `nvidia-smi` works but Ollama ignores GPU

The Ollama systemd service may be missing the `OLLAMA_NUM_GPU` environment variable.

```bash
fix-gpu
```

This creates `/etc/systemd/system/ollama.service.d/override.conf` with:
```ini
[Service]
Environment="OLLAMA_NUM_GPU=99"
```

### CUDA not found

In WSL2, CUDA lives at `/usr/lib/wsl/lib`. The installer adds this to your PATH and `LD_LIBRARY_PATH`. If something reset it:

```bash
llm-fix
```

---

## Ollama issues

### Ollama won't start

```bash
sudo systemctl status ollama
sudo journalctl -u ollama -n 50
```

Restart manually:
```bash
sudo systemctl restart ollama
# or without systemd:
OLLAMA_NUM_GPU=99 ollama serve &
```

### Model not found

```bash
ollama list          # see what's installed
llm-add              # browse and download models
ollama pull qwen3:14b  # or pull directly
```

### Out of VRAM

Switch to a smaller model:
```bash
llm-switch
```

Or unload current model and reload:
```bash
ollama stop <model>
ollama run <model>
```

---

## Agent issues

### `qwen-code` shows auth screen

The settings.json injection should suppress this. If it reappears:
1. Select **API Key** in the auth dialog
2. Type `ollama` as the key
3. Press Enter

This is saved permanently. The wrapper re-applies the fix on each launch.

### `codex` / `aider` / `claude-code` can't find the binary

```bash
llm-update     # re-installs/updates all agents
source ~/.bashrc
```

### Agent times out on first message

The model may need to load. First inference always takes longer (model loads into VRAM). Subsequent messages are fast.

---

## MCP bridges

### Bridges not responding

```bash
llm-mcp-start
llm-doctor     # should show :8010 and :8011 as ✔
```

### Check bridge logs

```bash
cat ~/.local/share/llm-setup/mcp-time.log
cat ~/.local/share/llm-setup/mcp-fs.log
```

- `http://127.0.0.1:8010` → Name: `Time`
- `http://127.0.0.1:8011` → Name: `Filesystem`

---

## oterm / chat

### `chat` command opens but Ollama isn't running

All launchers now auto-start Ollama. If it's still failing:

```bash
sudo systemctl start ollama
chat
```

### oterm can't connect to Ollama

oterm connects to `http://127.0.0.1:11434` by default. Verify:
```bash
curl http://127.0.0.1:11434/api/tags
```

---

## Re-running the installer

The installer is idempotent — already-installed components are detected and skipped.

```bash
llm-setup      # alias for re-running install.sh
```

Or to force a full reinstall of a specific component, delete its marker and re-run:
```bash
# Example: force re-install of agents
rm ~/.config/llm-setup/agents-venv.txt
llm-setup
```

---

## Full reset

To start completely fresh:
```bash
# Remove all llm-setup data (keeps Ollama models)
rm -rf ~/.config/llm-setup ~/.local/share/llm-setup
rm -rf ~/.local/share/llm-venv ~/.local/share/mcp-venv

# Remove CLI tools
rm -f ~/.local/bin/{llm-switch,llm-add,llm-doctor,llm-fix,llm-update}
rm -f ~/.local/bin/{llm-mcp-start,llm-mcp-stop,fix-gpu,llm-chat-ui}

# Re-run
bash <(curl -fsSL https://raw.githubusercontent.com/mettbrot0815/llm-setup/main/install.sh)
```

Ollama and your downloaded models are untouched by this.
