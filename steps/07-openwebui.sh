#!/usr/bin/env bash
# steps/07-openwebui.sh — Chat UI: oterm

step "Chat UI"

OTERM_VENV="$HOME/.local/share/oterm-venv"

# ── Already installed? ─────────────────────────────────────────────────────────
if command -v oterm &>/dev/null || [[ -x "$OTERM_VENV/bin/oterm" ]]; then
  ok "oterm already installed"
  _oterm_installed=1
else
  # ── Install ──────────────────────────────────────────────────────────────────
  (( HAVE_INTERNET )) || { warn "No internet — skipping oterm install"; return 0; }

  if [[ -d "$OTERM_VENV" && ! -f "$OTERM_VENV/bin/activate" ]]; then
    rm -rf "$OTERM_VENV"
  fi
  "$PYTHON_BIN" -m venv "$OTERM_VENV" >> "$LOG_FILE" 2>&1
  run_with_progress "oterm (~2 MB)" "$LOG_FILE" \
    "$OTERM_VENV/bin/pip" install --no-cache-dir oterm
  _rc=$?
  if (( _rc == 0 )); then
    ln -sf "$OTERM_VENV/bin/oterm" "$BIN_DIR/oterm" 2>/dev/null || true
    ok "oterm installed"
    _oterm_installed=1
  else
    warn "oterm install failed — run: pip install oterm"
    return 0
  fi
fi

# ── Write chat launcher ────────────────────────────────────────────────────────
mkdir -p "$BIN_DIR"
_oterm_bin="$OTERM_VENV/bin/oterm"
[[ ! -x "$_oterm_bin" ]] && _oterm_bin="oterm"

cat > "$BIN_DIR/chat" << 'LAUNCHER'
#!/usr/bin/env bash
# Ensure Ollama is running before starting oterm
if ! curl -sf --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  printf "  Starting Ollama…"
  if command -v systemctl &>/dev/null && systemctl is-enabled ollama &>/dev/null 2>&1; then
    sudo systemctl start ollama 2>/dev/null || true
  else
    OLLAMA_NUM_GPU=99 nohup ollama serve >/dev/null 2>&1 & disown $!
  fi
  for _i in {1..20}; do
    curl -sf --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && { echo " ready"; break; }
    printf "."; sleep 1
  done
fi
# GPU warmup (best-effort)
_LIB="$HOME/.local/share/llm-setup/lib"
if [[ -f "$_LIB/gpu-ensure.sh" ]]; then
  source "$_LIB/colors.sh"  2>/dev/null || true
  source "$_LIB/paths.sh"   2>/dev/null || true
  source "$_LIB/gpu-ensure.sh"
  _model=$(grep OLLAMA_TAG "${CONF_DIR:-$HOME/.config/llm-setup}/model.conf" 2>/dev/null \
    | cut -d= -f2 | tr -d '"' || echo "")
  [[ -n "$_model" ]] && _gpu_ensure "$_model"
fi
exec "OTERM_BIN_PLACEHOLDER"
LAUNCHER

sed -i "s|OTERM_BIN_PLACEHOLDER|${_oterm_bin}|" "$BIN_DIR/chat"
chmod +x "$BIN_DIR/chat"
ok "chat launcher → oterm"
