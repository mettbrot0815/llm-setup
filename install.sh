#!/usr/bin/env bash
# install.sh — Local LLM Auto-Setup
# Usage: cd llm-setup && ./install.sh
# Or:    bash <(curl -fsSL https://raw.githubusercontent.com/mettbrot0815/llm-setup/main/install.sh)

set -uo pipefail
set -o errtrace
trap 'echo "  [ERR] $BASH_SOURCE:$LINENO: $BASH_COMMAND" >> "${LOG_FILE:-/tmp/llm-setup.log}"' ERR

SETUP_VERSION="4.2.0"

# ── Resolve location ──────────────────────────────────────────────────────────
SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"

# Piped from curl: BASH_SOURCE is empty, lib/ won't exist — clone first
if [[ ! -f "$SETUP_DIR/lib/ui.sh" ]]; then
  INSTALL_TARGET="$HOME/.local/share/llm-setup"
  if [[ ! -d "$INSTALL_TARGET/.git" ]]; then
    echo "Cloning llm-setup to $INSTALL_TARGET…"
    git clone --depth=1 https://github.com/mettbrot0815/llm-setup "$INSTALL_TARGET" \
      || { echo "Clone failed" >&2; exit 1; }
  else
    git -C "$INSTALL_TARGET" pull --ff-only 2>/dev/null || true
  fi
  exec bash "$INSTALL_TARGET/install.sh" "$@"
fi

# ── Canonical global paths — defined HERE, used everywhere ───────────────────
CONFIG_DIR="$HOME/.config/llm-setup"
BIN_DIR="$HOME/.local/bin"
LOG_FILE="$HOME/llm-setup-$(date +%Y%m%d-%H%M%S).log"

VENV_DIR="$HOME/.local/share/llm-venv"


MCP_VENV="$HOME/.local/share/mcp-venv"
MCP_LOG="$CONFIG_DIR/mcp.log"
MCP_PID_DIR="$CONFIG_DIR/pids"
MCP_TIME_PORT="${MCP_TIME_PORT:-8010}"
MCP_FS_PORT="${MCP_FS_PORT:-8011}"

mkdir -p "$CONFIG_DIR" "$BIN_DIR" "$MCP_PID_DIR"
echo "$SETUP_DIR" > "$CONFIG_DIR/setup-dir.txt"

# ── Source libs ───────────────────────────────────────────────────────────────
source "$SETUP_DIR/lib/ui.sh"      || { echo "Missing lib/ui.sh"      >&2; exit 1; }
source "$SETUP_DIR/lib/detect.sh"  || { echo "Missing lib/detect.sh"  >&2; exit 1; }
source "$SETUP_DIR/lib/util.sh"    || { echo "Missing lib/util.sh"    >&2; exit 1; }
source "$SETUP_DIR/lib/catalog.sh" || { echo "Missing lib/catalog.sh" >&2; exit 1; }

# ── Hardware detection ────────────────────────────────────────────────────────
detect_hardware

# Step count: 05-cuda only increments counter when HAS_NVIDIA
(( HAS_NVIDIA )) && _STEP_TOTAL=12 || _STEP_TOTAL=11

# ── Banner ────────────────────────────────────────────────────────────────────
print_banner
print_hw_summary
echo -e "  ${DIM}Log → $LOG_FILE${NC}"
echo ""

# ── WSL2 pip safety: use HOME-based tmp so pip atomic moves don't cross filesystems
mkdir -p "$HOME/.tmp" "$HOME/.cache/pip"
export TMPDIR="$HOME/.tmp"

# ── Run steps ─────────────────────────────────────────────────────────────────
_INSTALL_START=$SECONDS
for _step in "$SETUP_DIR/steps"/[0-9]*.sh; do
  source "$_step" || {
    echo -e "  ${BRED}✘${NC}  Step failed: $(basename "$_step")"
    echo -e "  Re-run: bash $SETUP_DIR/install.sh"
    exit 1
  }
done

# ── First-run: start services ─────────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}⚡  Starting services…${NC}"
echo ""

# MCP bridges started by step 08 if user opted in
# ── Summary ───────────────────────────────────────────────────────────────────
source "$CONFIG_DIR/model.conf" 2>/dev/null || true
_install_elapsed=$(( SECONDS - _INSTALL_START ))
_mm=$(( _install_elapsed / 60 )); _ss=$(( _install_elapsed % 60 ))
_total_time_str=""
(( _mm > 0 )) && printf -v _total_time_str "%dm %02ds" "$_mm" "$_ss"               || printf -v _total_time_str "%ds" "$_ss"

# Hardware / model card — printed before summary box
echo ""
_os=$(source /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-$(uname -s)}")
printf "  ${DIM}%-14s  %s${NC}\n" "OS"    "${_os:0:50}"
printf "  ${DIM}%-14s  %s${NC}\n" "CPU"   "${CPU_NAME:0:50}"
printf "  ${DIM}%-14s  %s${NC}\n" "RAM"   "${TOTAL_RAM_GB} GB"
(( HAS_GPU )) && printf "  ${DIM}%-14s  %s (${GPU_VRAM_GB} GB)${NC}\n" "GPU" "${GPU_NAME:0:40}"
printf "  ${DIM}%-14s  %s${NC}\n" "Model" "${OLLAMA_TAG:-not pulled yet}"
(( HAS_GPU )) && printf "  ${DIM}%-14s  %s / %s layers   threads %s   batch %s${NC}\n"   "" "${GPU_LAYERS:-?}" "${MODEL_LAYERS:-?}" "${HW_THREADS:-?}" "${BATCH:-?}"
echo ""


print_summary "$_total_time_str"

echo -e "  ${DIM}New terminal?  Run: ${CYN}source ~/.bashrc${NC}"
echo ""
