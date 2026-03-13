#!/usr/bin/env bash
# steps/03-node.sh — Node.js latest LTS via nvm, npm latest

step "Node.js"

NODE_MIN=20   # absolute floor

_node_maj() { node --version 2>/dev/null | tr -d 'v' | cut -d. -f1; }

# ── nvm loader ────────────────────────────────────────────────────────────────
# nvm.sh uses unset variables internally — must source with set -u disabled
_load_nvm() {
  export NVM_DIR="$HOME/.nvm"
  set +u
  [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh" 2>/dev/null || true
  set -u
  command -v nvm &>/dev/null
}

# ── Symlink node/npm/npx into BIN_DIR (always-on-PATH, no nvm required) ──────
_pin_node_to_bin() {
  # Resolve the *real* node binary — not a symlink we may have already created in BIN_DIR.
  # If we use "command -v node" and it returns $BIN_DIR/node (our own symlink from a prior
  # run), then node_dir == BIN_DIR and we create a circular symlink → "Too many levels".
  local node_bin node_real node_dir
  node_bin=$(command -v node 2>/dev/null || true)
  [[ -z "$node_bin" ]] && return
  # Dereference fully — if it is already a real binary (nvm path), use it directly
  node_real=$(readlink -f "$node_bin" 2>/dev/null || echo "$node_bin")
  node_dir="${node_real%/node}"
  # Safety: never symlink BIN_DIR into itself
  [[ "$node_dir" == "$BIN_DIR" ]] && return
  for _bin in node npm npx corepack; do
    [[ -x "$node_dir/$_bin" ]] \
      && ln -sf "$node_dir/$_bin" "$BIN_DIR/$_bin" 2>/dev/null || true
  done
  # Also symlink npm-global bins (codex, claude, qwen, etc.) into BIN_DIR
  local npm_prefix
  npm_prefix=$(npm config get prefix 2>/dev/null || true)
  if [[ -d "$npm_prefix/bin" ]]; then
    for _g in "$npm_prefix/bin"/*; do
      [[ -x "$_g" ]] && ln -sf "$_g" "$BIN_DIR/$(basename "$_g")" 2>/dev/null || true
    done
  fi
}

# ── Install / upgrade ─────────────────────────────────────────────────────────
if (( HAVE_INTERNET )); then

  # Install nvm if missing
  if [[ ! -s "$HOME/.nvm/nvm.sh" ]]; then
    info "Installing nvm…"
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/HEAD/install.sh \
      | PROFILE=/dev/null bash >> "$LOG_FILE" 2>&1 \
      && ok "nvm installed" \
      || warn "nvm install failed — falling back to NodeSource"
  fi

  _load_nvm

  if command -v nvm &>/dev/null; then

    # nvm internals use unset variables — must disable set -u for all nvm calls
    set +u

    run_with_progress "Node.js LTS via nvm" "$LOG_FILE" \
      bash -c 'export NVM_DIR="$NVM_DIR"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"; NVM_PROGRESS=0 nvm install --lts --no-progress'
    _nvm_rc=$?
    if (( _nvm_rc != 0 )); then
      warn "nvm install --lts failed — trying lts/iron fallback"
      run_with_progress "Node.js lts/iron (fallback)" "$LOG_FILE" \
        bash -c 'export NVM_DIR="$NVM_DIR"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"; NVM_PROGRESS=0 nvm install lts/iron --no-progress'
    fi
    NVM_PROGRESS=0 nvm use   --lts           >> "$LOG_FILE" 2>&1 || true
    NVM_PROGRESS=0 nvm alias default 'lts/*' >> "$LOG_FILE" 2>&1 || true

    # Re-enable strict mode
    set -u

    # Put nvm's active bin dir on PATH immediately for this session
    _nvm_bin=$(nvm which current 2>/dev/null || true)
    _nvm_bin="${_nvm_bin%/node}"
    [[ -d "$_nvm_bin" ]] && export PATH="$_nvm_bin:$PATH"

    ok "Node.js $(node --version 2>/dev/null) via nvm ✔"

    # Upgrade npm to absolute latest
    info "Upgrading npm to latest…"
    npm install -g npm@latest >> "$LOG_FILE" 2>&1       && ok "npm $(npm --version 2>/dev/null) ✔"       || warn "npm upgrade failed — using $(npm --version 2>/dev/null)"

  else
    # nvm unavailable — NodeSource latest LTS
    warn "nvm unavailable — using NodeSource LTS"
    retry 3 8 bash -c "curl -fsSL 'https://deb.nodesource.com/setup_lts.x' | sudo -E bash -" \
      </dev/null >> "$LOG_FILE" 2>&1 || warn "NodeSource setup failed"
    apt_wait apt-get install -y -q nodejs >> "$LOG_FILE" 2>&1 \
      || error "Node.js install failed"
    sudo npm install -g npm@latest >> "$LOG_FILE" 2>&1 \
      && ok "npm $(npm --version) ✔" || warn "npm upgrade failed"
  fi

else
  # Offline: use whatever apt has
  if ! command -v node &>/dev/null; then
    apt_wait apt-get install -y -q nodejs npm >> "$LOG_FILE" 2>&1 \
      || error "Node.js install failed (offline)"
  fi
  _load_nvm
fi

# ── Verify ────────────────────────────────────────────────────────────────────
_maj=$(_node_maj)
if [[ "$_maj" =~ ^[0-9]+$ ]] && (( _maj >= NODE_MIN )); then
  ok "Node.js $(node --version) ✔  (need >= v${NODE_MIN})"
else
  error "Node.js v${_maj:-?} too old or missing — need v${NODE_MIN}+.  Fix: nvm install --lts"
fi

# ── Persist nvm in .bashrc ────────────────────────────────────────────────────
if [[ -s "$HOME/.nvm/nvm.sh" ]] && ! grep -q 'NVM_DIR' "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" << 'NVMRC'

# nvm — Node Version Manager
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && source "$NVM_DIR/bash_completion"
NVMRC
  ok "nvm added to ~/.bashrc"
fi

# ── Symlink node/npm/npx/npm-globals into BIN_DIR ────────────────────────────
# This means node, npm, npx, qwen, claude, codex etc. all work in new terminals
# without the user manually running 'source ~/.bashrc' or nvm use.
mkdir -p "$BIN_DIR"
_pin_node_to_bin
info "Node binaries pinned to $BIN_DIR"
