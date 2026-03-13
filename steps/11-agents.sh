#!/usr/bin/env bash
# steps/11-agents.sh — AI coding agents (Aider, Codex CLI, Claude Code, Qwen Code)
#
# Single multi-select menu shows all tools with current install status.
# Skips tools already installed. Aider and Claude Code are opt-in (heavy).
# Qwen model picker uses catalog.sh (same as step 06 — always up to date).

step "Coding Agents"

[[ -t 0 ]] || { info "Non-interactive — skipping agents"; return 0; }
(( HAVE_INTERNET )) || { warn "No internet — skipping agents"; return 0; }

source "$CONFIG_DIR/model.conf" 2>/dev/null || true
_MODEL="${OLLAMA_TAG:-qwen3:14b}"
AGENTS_VENV="$HOME/.local/share/agents-venv"
LITELLM_PORT="${LITELLM_PORT:-4010}"

# ── Detect what's already installed ──────────────────────────────────────────
_qwen_ok=false;   command -v qwen  &>/dev/null && _qwen_ok=true
_codex_ok=false;  command -v codex &>/dev/null && _codex_ok=true
_aider_ok=false;  [[ -x "$AGENTS_VENV/bin/aider" ]] && _aider_ok=true
_claude_ok=false; [[ -x "$BIN_DIR/claude-code" ]] && _claude_ok=true

# ── Unified selection menu ─────────────────────────────────────────────────────
_status() { [[ "$1" == "true" ]] && echo "${BGREEN}✔ installed${NC}" || echo "${DIM}not installed${NC}"; }

echo ""
echo -e "  ${BCYAN}╭─────────────────────────────────────────────────────────────────╮${NC}"
echo -e "  ${BCYAN}│${NC}  Coding Agents  — toggle with number, Enter to confirm          ${BCYAN}│${NC}"
echo -e "  ${BCYAN}├─────────────────────────────────────────────────────────────────┤${NC}"
printf  "  ${BCYAN}│${NC}  ${CYAN}[1]${NC}  %-13s  ${DIM}%-8s${NC}  %-12s  %b  ${BCYAN}│${NC}\n" \
  "Qwen Code"   "~10 MB"  "local + OAuth"  "$(_status $_qwen_ok)"
printf  "  ${BCYAN}│${NC}  ${CYAN}[2]${NC}  %-13s  ${DIM}%-8s${NC}  %-12s  %b  ${BCYAN}│${NC}\n" \
  "Codex CLI"   "~2 MB"   "local Ollama"   "$(_status $_codex_ok)"
printf  "  ${BCYAN}│${NC}  ${CYAN}[3]${NC}  %-13s  ${DIM}%-8s${NC}  %-12s  %b  ${BCYAN}│${NC}\n" \
  "Aider"       "~80 MB"  "git coder"      "$(_status $_aider_ok)"
printf  "  ${BCYAN}│${NC}  ${CYAN}[4]${NC}  %-13s  ${DIM}%-8s${NC}  %-12s  %b  ${BCYAN}│${NC}\n" \
  "Claude Code" "~200 MB" "+ LiteLLM"      "$(_status $_claude_ok)"
echo -e "  ${BCYAN}├─────────────────────────────────────────────────────────────────┤${NC}"
echo -e "  ${BCYAN}│${NC}  Enter numbers to toggle (e.g. 12 = Qwen+Codex). Default = 12   ${BCYAN}│${NC}"
echo -e "  ${BCYAN}│${NC}  Already-installed tools are skipped automatically.             ${BCYAN}│${NC}"
echo -e "  ${BCYAN}╰─────────────────────────────────────────────────────────────────╯${NC}"
echo ""
echo -ne "  Selection [1-4, default=12, s=skip]: "
read -r _sel
echo ""

# Default: qwen + codex
_sel="${_sel:-12}"
[[ "$_sel" == "s" || "$_sel" == "S" ]] && { info "Agents skipped"; return 0; }
_sel=$(echo "$_sel" | tr -dc '1-4')

_do_qwen=false;  [[ "$_sel" == *1* ]] && _do_qwen=true
_do_codex=false; [[ "$_sel" == *2* ]] && _do_codex=true
_do_aider=false; [[ "$_sel" == *3* ]] && _do_aider=true
_do_claude=false;[[ "$_sel" == *4* ]] && _do_claude=true

# Show summary of what will happen
echo -e "  ${BOLD}Plan:${NC}"
for _t in "1:Qwen Code:_do_qwen:_qwen_ok" "2:Codex CLI:_do_codex:_codex_ok" \
          "3:Aider:_do_aider:_aider_ok" "4:Claude Code:_do_claude:_claude_ok"; do
  IFS=: read -r _n _name _do _ok <<< "$_t"
  _do_val="${!_do}"; _ok_val="${!_ok}"
  if [[ "$_do_val" == "true" ]]; then
    [[ "$_ok_val" == "true" ]] \
      && echo -e "    ${BGREEN}✔${NC}  $_name  ${DIM}(already installed — will skip)${NC}" \
      || echo -e "    ${CYAN}→${NC}  $_name  ${DIM}(will install)${NC}"
  else
    echo -e "    ${DIM}·  $_name  (skipped)${NC}"
  fi
done
echo ""

# ── Python venv — only if aider or litellm needed ─────────────────────────────
if [[ "$_do_aider" == "true" || "$_do_claude" == "true" ]]; then
  if [[ ! -f "$AGENTS_VENV/bin/activate" ]]; then
    [[ -d "$AGENTS_VENV" ]] && { info "Removing incomplete agents venv…"; rm -rf "$AGENTS_VENV"; }
    info "Creating agents venv…"
    "$PYTHON_BIN" -m venv "$AGENTS_VENV" >> "$LOG_FILE" 2>&1 \
      || { warn "Failed to create agents venv"; return 0; }
    "$AGENTS_VENV/bin/pip" install --no-cache-dir --upgrade pip >> "$LOG_FILE" 2>&1
  fi
fi

# ── Aider ──────────────────────────────────────────────────────────────────────
if [[ "$_do_aider" == "true" ]]; then
  if [[ "$_aider_ok" == "true" ]]; then
    ok "Aider already installed — skipping"
  else
    run_with_progress "aider-chat (~80 MB)" "$LOG_FILE" \
      "$AGENTS_VENV/bin/pip" install --no-cache-dir aider-chat
    _rc=$?
    (( _rc == 0 )) && : || warn "Aider install failed (non-fatal)"
  fi
  # Always refresh config to point at current model
  cat > "$HOME/.aider.conf.yml" << CONF
# Aider config — managed by llm-setup
model: ollama/${_MODEL}
openai-api-base: http://127.0.0.1:11434/v1
openai-api-key: ollama
no-auto-commits: false
dirty-commits: true
analytics: false
yes-always: true
no-show-model-warnings: true
CONF
  ok "Aider configured → ollama/${_MODEL}"
fi

# ── Claude Code + LiteLLM proxy ───────────────────────────────────────────────
if [[ "$_do_claude" == "true" ]]; then
  if [[ "$_claude_ok" == "true" ]]; then
    ok "Claude Code already installed — skipping"
  else
    run_with_progress "litellm[proxy] + apscheduler (~150 MB)" "$LOG_FILE" \
      "$AGENTS_VENV/bin/pip" install --no-cache-dir 'litellm[proxy]' apscheduler
    _rc=$?
    (( _rc == 0 )) && : || warn "LiteLLM install failed (non-fatal)"
  fi

  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_DIR/litellm.yaml" << LITELLM
model_list:
  - model_name: claude-3-5-sonnet-20241022
    litellm_params:
      model: ollama/${_MODEL}
      api_base: http://127.0.0.1:11434
  - model_name: claude-3-haiku-20240307
    litellm_params:
      model: ollama/${_MODEL}
      api_base: http://127.0.0.1:11434
litellm_settings:
  drop_params: true
LITELLM

  _litellm_service="$HOME/.config/systemd/user/litellm.service"
  mkdir -p "$HOME/.config/systemd/user"
  cat > "$_litellm_service" << SVCEOF
[Unit]
Description=LiteLLM proxy (Anthropic API → Ollama)
After=network.target

[Service]
ExecStart=${AGENTS_VENV}/bin/litellm --config ${CONFIG_DIR}/litellm.yaml --port ${LITELLM_PORT} --host 127.0.0.1
Restart=on-failure
RestartSec=5
Environment="HOME=${HOME}"

[Install]
WantedBy=default.target
SVCEOF

  if command -v systemctl &>/dev/null; then
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable litellm 2>/dev/null || true
    systemctl --user restart litellm 2>/dev/null || true
    for _i in {1..20}; do
      curl -sf --max-time 2 "http://127.0.0.1:${LITELLM_PORT}/v1/models" >/dev/null 2>&1 && break
      sleep 1
    done
    curl -sf --max-time 2 "http://127.0.0.1:${LITELLM_PORT}/v1/models" >/dev/null 2>&1 \
      && ok "LiteLLM proxy running on :${LITELLM_PORT}" \
      || warn "LiteLLM proxy slow to start — will retry on first cc run"
  fi

  if [[ ! -x "$HOME/.local/bin/claude" ]]; then
    run_with_progress "Claude Code (native)" "$LOG_FILE" \
      bash -c 'curl -fsSL https://claude.ai/install.sh | sh'
    _rc=$?
    command -v claude &>/dev/null \
      && ok "Claude Code installed: $(claude --version 2>/dev/null | head -1)" \
      || warn "Claude Code install failed (non-fatal)"
  fi

  _claude_cfg="$HOME/.claude.json"
  if [[ ! -f "$_claude_cfg" ]] || ! grep -q "hasCompletedOnboarding" "$_claude_cfg" 2>/dev/null; then
    cat > "$_claude_cfg" << 'CLAUDECFG'
{
  "hasCompletedOnboarding": true,
  "primaryApiKeySource": "environmentVariable",
  "autoUpdaterStatus": "disabled"
}
CLAUDECFG
    chmod 600 "$_claude_cfg"
    ok "Claude Code pre-configured (skips account setup)"
  fi
fi

# ── Codex CLI ──────────────────────────────────────────────────────────────────
if [[ "$_do_codex" == "true" ]]; then
  if command -v npm &>/dev/null; then
    if [[ "$_codex_ok" == "false" ]]; then
      run_with_progress "@openai/codex" "$LOG_FILE" npm install -g @openai/codex
      _rc=$?
      (( _rc == 0 )) && : || warn "Codex install failed (non-fatal)"
    else
      ok "Codex already installed — skipping"
    fi
    # Always refresh config
    mkdir -p "$HOME/.codex"
    cat > "$HOME/.codex/config.toml" << CODEXCFG
model_provider = "ollama"
model = "${OLLAMA_TAG:-qwen3:14b}"
ollama_base_url = "http://127.0.0.1:11434"
model_supports_reasoning = false
sandbox = "workspace-write"
approval_policy = "never"
CODEXCFG
    chmod 600 "$HOME/.codex/config.toml"
    rm -f "$HOME/.codex/config.json"
    ok "Codex configured → ollama/${OLLAMA_TAG:-qwen3:14b}"
  else
    warn "npm not found — Codex CLI skipped"
  fi
fi

# ── Qwen Code ─────────────────────────────────────────────────────────────────
if [[ "$_do_qwen" == "true" ]]; then
  if command -v npm &>/dev/null; then
    if [[ "$_qwen_ok" == "false" ]]; then
      run_with_progress "@qwen-code/qwen-code" "$LOG_FILE" npm install -g @qwen-code/qwen-code
      _rc=$?
      (( _rc == 0 )) && : || warn "Qwen Code install failed"
    else
      ok "Qwen Code already installed — skipping"
    fi
  else
    warn "npm not found — Qwen Code skipped"
    _do_qwen=false
  fi

  if [[ "$_do_qwen" == "true" ]]; then
    # ── Model selection — uses catalog.sh same as step 06 ─────────────────────
    # Wait briefly for background catalog refresh (started in preflight)
    sleep 1

    # Auto-recommend based on VRAM (uses same logic as auto_select_model)
    _vram_mb=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0")
    _vram_mb=$(echo "$_vram_mb" | tr -dc '0-9' || echo "0")
    _vram_gb=$(( _vram_mb / 1024 ))

    # Check if a qwen3 model is already installed in Ollama
    _installed_qwen=$(ollama list 2>/dev/null | awk 'NR>1 && $1~/^qwen/{print $1}' | head -1 || true)

    if [[ -n "$_installed_qwen" ]]; then
      _qwen_local_model="$_installed_qwen"
      ok "Using already-pulled model: $_qwen_local_model"
    else
      # Use catalog to pick best model for VRAM
      # Filter catalog for qwen models, pick best fit
      _qwen_local_model="qwen3:8b"  # safe default
      for _row in "${_MODELS[@]:-}"; do
        IFS='|' read -r _t _n _q _v _s _l _c <<< "$_row"
        _t=$(echo "$_t" | xargs); _v=$(echo "$_v" | xargs)
        [[ "$_t" != qwen3:* ]] && continue
        [[ "$_v" == "CPU" ]] && continue
        [[ "$_v" =~ ^[0-9]+$ ]] && (( _vram_gb >= _v )) && _qwen_local_model="$_t"
      done

      # Show a compact picker using catalog qwen3 models
      echo ""
      echo -e "  ${BOLD}Select Qwen3 model for qwen-code:${NC}  ${DIM}(your GPU: ${_vram_gb} GB VRAM)${NC}"
      echo ""

      _qwen_opts=()
      _i=0
      for _row in "${_MODELS[@]:-}"; do
        IFS='|' read -r _t _n _q _v _s _l _c <<< "$_row"
        _t=$(echo "$_t" | xargs); _v=$(echo "$_v" | xargs)
        _s=$(echo "$_s" | xargs); _n=$(echo "$_n" | xargs)
        [[ "$_t" != qwen3:* ]] && continue
        _i=$(( _i + 1 ))
        _qwen_opts+=("$_t")
        _fit=""
        if [[ "$_v" == "CPU" ]] || { [[ "$_v" =~ ^[0-9]+$ ]] && (( _vram_gb >= _v )); }; then
          _fit="${BGREEN}✔${NC} "
        else
          _fit="${DIM}  ${NC}"
        fi
        _rec=""
        [[ "$_t" == "$_qwen_local_model" ]] && _rec=" ${CYAN}← recommended${NC}"
        printf "  %b[%d]  %-22s  ${DIM}%s GB VRAM  %s GB download${NC}%b\n" \
          "$_fit" "$_i" "$_t" "$_v" "$_s" "$_rec"
      done

      # Fallback if catalog empty (no cache yet)
      if (( ${#_qwen_opts[@]} == 0 )); then
        _qwen_opts=("qwen3:8b" "qwen3:14b" "qwen3:30b-a3b" "qwen3:32b")
        printf "  [1]  qwen3:8b          5 GB VRAM   5 GB download\n"
        printf "  [2]  qwen3:14b         9 GB VRAM   9 GB download  ${CYAN}← recommended for 12GB${NC}\n"
        printf "  [3]  qwen3:30b-a3b    16 GB VRAM  18 GB download\n"
        printf "  [4]  qwen3:32b        19 GB VRAM  19 GB download\n"
        _i=4
      fi

      echo ""
      read -r -p "  Choice [1-${_i}, Enter = recommended]: " _qpick
      _qpick=$(echo "$_qpick" | tr -dc '0-9')
      if [[ "$_qpick" =~ ^[0-9]+$ ]] && (( _qpick >= 1 && _qpick <= ${#_qwen_opts[@]} )); then
        _qwen_local_model="${_qwen_opts[$(( _qpick - 1 ))]}"
      fi
      echo ""

      info "Pulling $_qwen_local_model…"
      ollama pull "$_qwen_local_model" \
        && ok "$_qwen_local_model ready" \
        || warn "Pull failed — run: ollama pull $_qwen_local_model"
    fi

    # ── Auth mode ──────────────────────────────────────────────────────────────
    echo ""
    echo -e "  ${BCYAN}╭──────────────────────────────────────────────────────────╮${NC}"
    echo -e "  ${BCYAN}│${NC}  Qwen Code — Auth mode                                   ${BCYAN}│${NC}"
    echo -e "  ${BCYAN}├──────────────────────────────────────────────────────────┤${NC}"
    echo -e "  ${BCYAN}│${NC}  [1]  Qwen OAuth  (recommended)                          ${BCYAN}│${NC}"
    echo -e "  ${BCYAN}│${NC}       Free · 1000 req/day · browser sign-in once         ${BCYAN}│${NC}"
    echo -e "  ${BCYAN}│${NC}                                                          ${BCYAN}│${NC}"
    echo -e "  ${BCYAN}│${NC}  [2]  Local only  (100% offline)                         ${BCYAN}│${NC}"
    echo -e "  ${BCYAN}│${NC}       ${DIM}No account · unlimited · uses $_qwen_local_model${NC}  ${BCYAN}│${NC}"
    echo -e "  ${BCYAN}╰──────────────────────────────────────────────────────────╯${NC}"
    echo ""
    echo -ne "  Choice [1/2, default=1]: "
    read -r _qwen_auth_choice
    echo ""
    _qwen_auth_choice="${_qwen_auth_choice:-1}"

    # Write settings.json
    mkdir -p "$HOME/.qwen"
    export _QWEN_AUTH="$_qwen_auth_choice"
    export _QWEN_MODEL="$_qwen_local_model"
    python3 - << 'PYEOF'
import json, os
auth  = os.environ.get("_QWEN_AUTH",  "1")
model = os.environ.get("_QWEN_MODEL", "qwen3:14b")

ollama_provider = {
    "id":          model,
    "name":        f"Ollama: {model}",
    "description": "Local model via Ollama — offline, no request limits",
    "baseUrl":     "http://127.0.0.1:11434/v1",
    "envKey":      "QWEN_OLLAMA_KEY",
    "authType":    "openai",
    "generationConfig": {
        "timeout":           600000,
        "maxRetries":        1,
        "contextWindowSize": 32768,
        "samplingParams": { "temperature": 0.2, "top_p": 0.9, "max_tokens": 8192 }
    }
}

cfg = {
    "$version": 3,
    "modelProviders": { "openai": [ ollama_provider ] },
    "security": { "auth": { "selectedType": "openai" } },
    "model":    { "name": model }
}

if auth == "2":
    cfg.update({
        "selectedProvider": model, "selectedModelId": model,
        "currentProvider":  "openai", "activeProvider": "openai",
        "activeModelId":    model, "authMethod": "apikey",
        "skipAuthScreen":   True, "coderModel": model, "selectedCoderModel": model
    })

qwen_dir = os.path.expanduser("~/.qwen")
os.makedirs(qwen_dir, exist_ok=True)
with open(os.path.join(qwen_dir, "settings.json"), "w") as f:
    json.dump(cfg, f, indent=2)

if auth == "2":
    auth_out = os.path.join(qwen_dir, "auth.json")
    if not os.path.exists(auth_out):
        with open(auth_out, "w") as f:
            json.dump({"type":"apikey","apiKey":"ollama","provider":"openai",
                       "baseUrl":"http://127.0.0.1:11434/v1","model":model}, f, indent=2)

print(f"  settings.json written ({model})")
PYEOF

    _keys_env="$CONFIG_DIR/keys.env"
    grep -qF "QWEN_OLLAMA_KEY" "$_keys_env" 2>/dev/null \
      || echo 'export QWEN_OLLAMA_KEY="ollama"' >> "$_keys_env"
    grep -qF "QWEN_AUTH_MODE"   "$CONFIG_DIR/model.conf" 2>/dev/null \
      || printf 'QWEN_AUTH_MODE="%s"\n'   "$_qwen_auth_choice"  >> "$CONFIG_DIR/model.conf"
    grep -qF "QWEN_LOCAL_MODEL" "$CONFIG_DIR/model.conf" 2>/dev/null \
      || printf 'QWEN_LOCAL_MODEL="%s"\n' "$_qwen_local_model"  >> "$CONFIG_DIR/model.conf"

    if [[ "$_qwen_auth_choice" == "2" ]]; then
      ok "qwen-code → local Ollama ($_qwen_local_model, 100% offline)"
    else
      ok "qwen-code → Qwen OAuth (free, 1000 req/day) + Ollama fallback"
      info "First launch: browser opens for qwen.ai sign-in"
    fi
  fi
fi

# ── Symlink npm-global bins into BIN_DIR ──────────────────────────────────────
if declare -f _pin_node_to_bin &>/dev/null; then
  _pin_node_to_bin
  ok "npm global bins pinned to $BIN_DIR"
fi

# ── keys.env — local defaults ──────────────────────────────────────────────────
_keys_env="$CONFIG_DIR/keys.env"
if [[ ! -f "$_keys_env" ]]; then
  cat > "$_keys_env" << 'KEYS'
# llm-setup API keys — sourced on login
# Local Ollama defaults are pre-filled. Replace with real keys to use cloud.

export OPENAI_API_KEY="ollama"
export OPENAI_BASE_URL="http://127.0.0.1:11434/v1"

export ANTHROPIC_API_KEY="local"
export ANTHROPIC_BASE_URL="http://127.0.0.1:4010"

export QWEN_OLLAMA_KEY="ollama"

# To use cloud APIs, replace values above and remove BASE_URL lines.
KEYS
  chmod 600 "$_keys_env"
  ok "Created $CONFIG_DIR/keys.env"
fi

if ! grep -qF "keys.env" "$HOME/.bashrc" 2>/dev/null; then
  { echo ""; echo "# llm-setup: API keys"; echo "[ -f \"$_keys_env\" ] && source \"$_keys_env\""; } >> "$HOME/.bashrc"
fi

echo "$AGENTS_VENV"  > "$CONFIG_DIR/agents-venv.txt"
echo "$LITELLM_PORT" >> "$CONFIG_DIR/agents-venv.txt"
ok "Agents done"
info "Edit $CONFIG_DIR/keys.env to switch to cloud APIs"
