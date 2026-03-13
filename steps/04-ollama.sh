#!/usr/bin/env bash
# steps/04-ollama.sh — install and start Ollama

step "Ollama"

_ollama_running() {
  curl -sf --max-time 3 http://127.0.0.1:11434/api/tags >/dev/null 2>&1
}

_ollama_start() {
  if is_wsl2; then
    nohup ollama serve >> "$LOG_FILE" 2>&1 &
    _ollama_pid=$!
    disown "$_ollama_pid" 2>/dev/null
  else
    if sudo systemctl start ollama >> "$LOG_FILE" 2>&1; then
      : # systemd started it
    else
      nohup ollama serve >> "$LOG_FILE" 2>&1 &
      _ollama_pid=$!
      disown "$_ollama_pid" 2>/dev/null
    fi
  fi
  local i
  for (( i=0; i<20; i++ )); do
    _ollama_running && return 0
    sleep 1
  done
  return 1
}

# ── Fix permissions if binary exists but isn't executable ────────────────────
for _oll_path in /usr/local/bin/ollama /usr/bin/ollama; do
  if [[ -f "$_oll_path" && ! -x "$_oll_path" ]]; then
    warn "Fixing permissions on $_oll_path (not executable)"
    sudo chmod +x "$_oll_path" || warn "Could not chmod — may need manual: sudo chmod +x $_oll_path"
  fi
done

# Also ensure current user can execute it (add to ollama group if exists)
if getent group ollama &>/dev/null && ! id -nG | grep -qw ollama; then
  info "Adding $USER to ollama group…"
  sudo usermod -aG ollama "$USER" 2>/dev/null || true
  info "  Group change takes effect in new shell — using sudo for this session"
fi

# ── Install if missing ────────────────────────────────────────────────────────
if ! command -v ollama &>/dev/null; then
  (( HAVE_INTERNET )) || error "Ollama not installed and no internet"

  echo ""
  echo -e "  ${BOLD}Installing Ollama${NC}  ${DIM}(binary ~50 MB + CUDA libs ~200 MB on GPU systems)${NC}"
  echo -e "  ${DIM}This takes 1-3 min depending on connection speed…${NC}"
  echo ""

  # Run installer in background and tail log for progress
  bash -c "curl -fsSL https://ollama.com/install.sh | bash" </dev/null >> "$LOG_FILE" 2>&1 &
  _install_pid=$!

  while kill -0 "$_install_pid" 2>/dev/null; do
    _line=$(tail -1 "$LOG_FILE" 2>/dev/null | grep -oP "(Downloading|Installing|Unpacking|Writing|Fetching|nvidia|cuda|%|MB).*" || true)
    [[ -n "$_line" ]] && printf "\r\033[2K  ${DIM}%-72s${NC}" "${_line:0:72}"
    sleep 1
  done
  printf "\r\033[2K"

  wait "$_install_pid"
  _install_rc=$?

  if command -v ollama &>/dev/null; then
    ok "Ollama installed: $(ollama --version 2>/dev/null)"
  elif (( _install_rc != 0 )); then
    warn "Installer returned exit $_install_rc — retrying with live output…"
    curl -fsSL https://ollama.com/install.sh | bash
    command -v ollama &>/dev/null || error "Ollama binary not found after install"
    ok "Ollama installed: $(ollama --version 2>/dev/null)"
  else
    error "Ollama binary not found after install"
  fi

  # Fix permissions immediately after fresh install
  for _oll_path in /usr/local/bin/ollama /usr/bin/ollama; do
    [[ -f "$_oll_path" && ! -x "$_oll_path" ]] && sudo chmod +x "$_oll_path" || true
  done
else
  ok "Ollama already installed: $(ollama --version 2>/dev/null)"
fi

# ── Fix models directory ownership ────────────────────────────────────────────
# Ollama installs to /usr/share/ollama/.ollama owned by the ollama system user.
# Current user gets "permission denied" writing manifests after pull.
# Primary fix: chown to current user. Fallback: redirect to $HOME/.ollama.
_ollama_models_dir="/usr/share/ollama/.ollama"
if [[ -d "$_ollama_models_dir" ]]; then
  _owner=$(stat -c '%U' "$_ollama_models_dir" 2>/dev/null || true)
  if [[ "$_owner" != "$USER" ]]; then
    info "Fixing models directory ownership ($USER) on $_ollama_models_dir…"
    if sudo chown -R "$USER:$USER" "$_ollama_models_dir" 2>/dev/null; then
      ok "Models directory: ownership fixed → $USER"
    else
      warn "Could not chown — redirecting models to \$HOME/.ollama/models"
      mkdir -p "$HOME/.ollama/models"
      export OLLAMA_MODELS="$HOME/.ollama/models"
      grep -qF "OLLAMA_MODELS" "$HOME/.bashrc" 2>/dev/null \
        || echo 'export OLLAMA_MODELS="$HOME/.ollama/models"' >> "$HOME/.bashrc"
      grep -qF "OLLAMA_MODELS" "$CONFIG_DIR/keys.env" 2>/dev/null \
        || echo 'export OLLAMA_MODELS="$HOME/.ollama/models"' >> "$CONFIG_DIR/keys.env"
      ok "OLLAMA_MODELS → $HOME/.ollama/models"
    fi
  else
    ok "Models directory ownership: OK ($USER)"
  fi
fi

# ── WSL2: ensure wrapper exists ───────────────────────────────────────────────
if is_wsl2 && [[ ! -x "$BIN_DIR/ollama-start" ]]; then
  cat > "$BIN_DIR/ollama-start" << 'WRAPPER'
#!/usr/bin/env bash
pgrep -f "ollama serve" >/dev/null 2>&1 && echo "Ollama already running" && exit 0
nohup ollama serve >/dev/null 2>&1 & disown $!
for i in {1..20}; do
  curl -sf http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && echo "Ollama started" && exit 0
  sleep 1
done
echo "Warning: Ollama may not have started" >&2; exit 1
WRAPPER
  chmod +x "$BIN_DIR/ollama-start"
fi

# ── Systemd enable ────────────────────────────────────────────────────────────
if ! is_wsl2 && command -v systemctl &>/dev/null; then
  sudo systemctl enable ollama >> "$LOG_FILE" 2>&1 || true
fi

# ── Start if not running ──────────────────────────────────────────────────────
if ! _ollama_running; then
  info "Starting Ollama…"
  _ollama_start && ok "Ollama API responding on port 11434" \
    || warn "Ollama API not responding — some steps may fail"
else
  ok "Ollama API responding on port 11434"
fi
