#!/usr/bin/env bash
# steps/02-python.sh — Python 3.10+, venv setup

step "Python environment"

# ── Find Python 3.10+ ─────────────────────────────────────────────────────────
PYTHON_BIN=""
for _py in python3.13 python3.12 python3.11 python3.10 python3; do
  command -v "$_py" &>/dev/null || continue
  _pyver=$("$_py" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null)
  _pymaj="${_pyver%%.*}"
  _pymin="${_pyver##*.}"
  if [[ "$_pymaj" =~ ^[0-9]+$ ]] && (( _pymaj >= 3 && _pymin >= 10 )); then
    PYTHON_BIN=$(command -v "$_py")
    info "Python $_pyver ✔  ($PYTHON_BIN)"
    break
  fi
done

if [[ -z "$PYTHON_BIN" ]]; then
  info "Installing Python 3.12…"
  run_with_progress "python3.12 + venv + dev" "$LOG_FILE" \
    sudo apt-get install -y -q python3.12 python3.12-venv python3.12-dev \
    || error "Failed to install Python 3.12"
  PYTHON_BIN=$(command -v python3.12 2>/dev/null) || error "python3.12 not found after install"
  ok "Python 3.12 installed"
fi

# ── Install venv package for the detected Python version ──────────────────────
_pymin=$("$PYTHON_BIN" -c "import sys; print(sys.version_info.minor)" 2>/dev/null)
_pymin="${_pymin:-12}"  # fallback to 3.12 if detection fails
# Install venv packages — may already be present from preflight batch install
run_with_progress "python3 venv + pip" "$LOG_FILE" \
  sudo apt-get install -y -q "python3.${_pymin}-venv" python3-venv python3-pip \
  || warn "venv apt install had errors (may be fine)"

# Ensure pip cache and tmp dirs exist under HOME — WSL2 /tmp is a different filesystem
# which causes pip to fail with "OSError: [Errno 2]" when it tries to atomically move files.
mkdir -p "$HOME/.cache/pip" "$HOME/.tmp"
export TMPDIR="$HOME/.tmp"

# ── Create and activate venv ───────────────────────────────────────────────────
# Never upgrade system pip — it hits 'externally-managed-environment' on Ubuntu 24.04.
# Upgrade pip only INSIDE the venv.
VENV_DIR="$HOME/.local/share/llm-venv"
# Check for bin/activate — not just the directory. A previous run interrupted by
# a dpkg lock will leave the directory behind but empty (no activate script).
if [[ ! -f "$VENV_DIR/bin/activate" ]]; then
  if [[ -d "$VENV_DIR" ]]; then
    info "Removing incomplete venv (previous run was interrupted)…"
    rm -rf "$VENV_DIR"
  fi
  info "Creating venv: $VENV_DIR"
  if ! "$PYTHON_BIN" -m venv "$VENV_DIR" >> "$LOG_FILE" 2>&1; then
    # Creation failed — python3-venv package may not have landed yet (dpkg race).
    warn "venv creation failed — re-installing python3-venv and retrying…"
    run_with_progress "python3 venv (retry)" "$LOG_FILE" \
      sudo apt-get install -y -q "python3.${_pymin}-venv" python3-venv || true
    "$PYTHON_BIN" -m venv "$VENV_DIR" >> "$LOG_FILE" 2>&1 \
      || error "Failed to create Python venv — check: $LOG_FILE"
  fi
fi
source "$VENV_DIR/bin/activate" || error "Failed to activate venv"

# Upgrade pip inside the venv (safe — no system packages involved)
pip install --no-cache-dir --upgrade pip >> "$LOG_FILE" 2>&1 || true

ok "Venv active: $(python --version 2>&1)  pip $(pip --version 2>/dev/null | awk '{print $2}')"
