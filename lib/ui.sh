#!/usr/bin/env bash
# lib/ui.sh — Professional installer UI
# Inspired by: cargo, bun, uv, Homebrew

# ── Terminal detection + color setup ──────────────────────────────────────────
if [[ -t 1 ]]; then
  _COLORS=1
  BLK=$'\033[0;30m'  RED=$'\033[0;31m'  GRN=$'\033[0;32m'  YLW=$'\033[0;33m'
  BLU=$'\033[0;34m'  PRP=$'\033[0;35m'  CYN=$'\033[0;36m'  WHT=$'\033[0;37m'
  BRED=$'\033[1;31m' BGRN=$'\033[1;32m' BYLW=$'\033[1;33m' BBLU=$'\033[1;34m'
  BPRP=$'\033[1;35m' BCYN=$'\033[1;36m' BWHT=$'\033[1;37m'
  BOLD=$'\033[1m'    DIM=$'\033[2m'     ITAL=$'\033[3m'    NC=$'\033[0m'
  _CLR=$'\033[2K'
  # Aliases used throughout steps (keep old names for backwards compat)
  BGREEN="$BGRN"  BYELLOW="$BYLW"  GREEN="$GRN"  CYAN="$CYN"  BCYAN="$BCYN"
else
  _COLORS=0
  RED='' GRN='' YLW='' BLU='' PRP='' CYN='' WHT='' NC=''
  BRED='' BGRN='' BYLW='' BBLU='' BPRP='' BCYN='' BWHT=''
  BOLD='' DIM='' ITAL='' NC='' _CLR=''
  BGREEN='' BYELLOW='' GREEN='' CYAN=''  BCYAN=''
fi

_W=60     # inner content width
_BAR_W=32 # indeterminate bar fill width

# ── Step counter ───────────────────────────────────────────────────────────────
_STEP_NUM=0
_STEP_TOTAL=9

# ── Core log functions ─────────────────────────────────────────────────────────
ok()   { printf "  ${BGRN}✔${NC}  %s\n"            "$*"; }
fail() { printf "  ${BRED}✘${NC}  ${BOLD}%s${NC}\n" "$*"; }
info() { printf "  ${DIM}·  %s${NC}\n"              "$*"; }
warn() { printf "  ${BYLW}⚠${NC}  %s\n"            "$*"; }

# ── Fatal error ────────────────────────────────────────────────────────────────
error() {
  echo ""
  printf "  ${BRED}"; printf '━%.0s' $(seq 1 $((_W+4))); printf "${NC}\n"
  printf "  ${BRED}  ✘  FATAL: %-*s${NC}\n" $((_W-4)) "$1"
  printf "  ${BRED}"; printf '━%.0s' $(seq 1 $((_W+4))); printf "${NC}\n"
  printf "  ${DIM}  Log → %s${NC}\n" "${LOG_FILE:-/tmp/llm-setup.log}"
  echo ""
  exit 1
}

# ── Yes/No prompt ──────────────────────────────────────────────────────────────
ask_yes_no() {
  local prompt="$1" default="${2:-y}" hint reply
  if [[ "$default" == "y" ]]; then
    hint="${BGRN}Y${NC}${DIM}/n${NC}"
  else
    hint="${DIM}y/${NC}${BGRN}N${NC}"
  fi
  printf "  ${BCYN}?${NC}  %s  [%b]  " "$prompt" "$hint"
  read -r reply
  reply="${reply:-$default}"
  [[ "${reply,,}" =~ ^(y|yes|1|yep|yeah|sure|ok)$ ]]
}

# ── step() — full-width header with overall progress bar ──────────────────────
step() {
  _STEP_NUM=$(( _STEP_NUM + 1 ))
  local title="$1"
  local filled=$(( _STEP_NUM * _BAR_W / _STEP_TOTAL ))
  local bar="" i
  for (( i=0; i<filled;     i++ )); do bar+="━"; done
  for (( i=filled; i<_BAR_W; i++ )); do bar+="╌"; done

  echo ""
  printf "  ${BCYN}%s${NC}  ${DIM}%d/%d${NC}  ${BOLD}%s${NC}\n" \
    "$bar" "$_STEP_NUM" "$_STEP_TOTAL" "$title"
  printf "  ${DIM}"; printf '─%.0s' $(seq 1 $((_W+4))); printf "${NC}\n"
}

_fmt_time() {
  local t=$1 m s
  m=$(( t / 60 )); s=$(( t % 60 ))
  (( m > 0 )) && printf "%dm %02ds" "$m" "$s" || printf "%ds" "$s"
}

# ── run_with_progress ──────────────────────────────────────────────────────────
#
# Renders a live 4-line box while a command runs in the background:
#
#   ┌ aider-chat (~80 MB) ─────────────────────────── 00:42 ┐
#   │ ░░░░░░░░████████████████░░░░░░░░░░░░░░░░░░░░░░        │
#   │ Downloading aider_chat-0.82.0-py3-none-any.whl        │
#   └───────────────────────────────────────────────────────┘
#
# On success:  ✔  aider-chat (~80 MB)                   1m 23s
# On failure:  ✘  aider-chat (~80 MB)         exit 1  — 0m 08s

_PROG_LINES=4  # number of lines the box occupies

run_with_progress() {
  local label="$1" log="$2"; shift 2
  local start_ts=$SECONDS _pid _rc=0 _elapsed _last_line=""
  local _log_offset
  _log_offset=$(wc -c < "$log" 2>/dev/null || echo 0)

  "$@" >> "$log" 2>&1 &
  _pid=$!

  # Bouncing window for indeterminate bar
  local _pos=0 _dir=1
  local _win=10  # width of the "lit" window

  _draw_box() {
    local elapsed="$1" last="$2" pos="$3"
    local tstr; tstr=$(_fmt_time "$elapsed")

    # Build bouncing bar
    local bar="" i
    for (( i=0; i<_BAR_W; i++ )); do
      if (( i >= pos && i < pos + _win )); then bar+="█"
      else bar+="░"; fi
    done

    # Label fits between corner and timer
    local lbl="${label:0:$((_W - ${#tstr} - 3))}"
    local gap=$(( _W - ${#lbl} - ${#tstr} - 1 ))
    (( gap < 1 )) && gap=1
    local spc; printf -v spc '%*s' "$gap" ''

    # Activity line truncated to fit
    local act="${last:0:$((_W - 1))}"

    printf "  ${BCYN}┌${NC} ${BOLD}%s${NC}${DIM}%s%s${NC} ${BCYN}┐${NC}\n" \
      "$lbl" "$spc" "$tstr"
    printf "  ${BCYN}│${NC} ${CYN}%s${NC}%*s ${BCYN}│${NC}\n" \
      "$bar" $((_W - _BAR_W)) ''
    printf "  ${BCYN}│${NC} ${DIM}%-*s${NC} ${BCYN}│${NC}\n" $((_W)) "$act"
    printf "  ${BCYN}└${NC}"; printf '─%.0s' $(seq 1 $((_W+2))); printf "${BCYN}┘${NC}\n"
  }

  # Initial render
  _draw_box 0 "starting…" 0

  while kill -0 "$_pid" 2>/dev/null; do
    _elapsed=$(( SECONDS - start_ts ))

    local _line
    _line=$(tail -c "+$(( _log_offset + 1 ))" "$log" 2>/dev/null \
      | grep -oP '(Downloading|Installing|Collecting|Unpacking|Setting up|Get:[0-9]+|added [0-9]+|pulling|verifying|writing|Fetching|Resolving|Preparing|Building)\s+\S+[^\n]*' \
      | tail -1 || true)
    [[ -n "$_line" ]] && _last_line="$_line"

    # Advance bounce
    _pos=$(( _pos + _dir ))
    (( _pos + _win >= _BAR_W )) && _dir=-1
    (( _pos <= 0 ))              && _dir=1

    # Move cursor up and redraw in place
    printf "\033[%dA" "$_PROG_LINES"
    _draw_box "$_elapsed" "$_last_line" "$_pos"
    sleep 0.1
  done

  wait "$_pid"; _rc=$?
  _elapsed=$(( SECONDS - start_ts ))
  local tstr; tstr=$(_fmt_time "$_elapsed")

  # Erase the box
  printf "\033[%dA" "$_PROG_LINES"
  for (( i=0; i<_PROG_LINES; i++ )); do printf "\r${_CLR}\n"; done
  printf "\033[%dA" "$_PROG_LINES"

  if (( _rc == 0 )); then
    printf "  ${BGRN}✔${NC}  ${BOLD}%-44s${NC}  ${DIM}%s${NC}\n" "$label" "$tstr"
  else
    printf "  ${BRED}✘${NC}  ${BOLD}%-44s${NC}  ${DIM}exit %d — %s${NC}\n" \
      "$label" "$_rc" "$tstr"
    printf "  ${DIM}    └─ log: %s${NC}\n" "$log"
  fi

  return $_rc
}

# Backwards-compat shims for any remaining spin_start/spin_stop calls
_SPIN_LABEL=""
spin_start() { _SPIN_LABEL="$1"; }
spin_stop() {
  local rc="${1:-0}"
  printf "\r${_CLR}"
  (( rc == 0 )) && ok "$_SPIN_LABEL" || warn "$_SPIN_LABEL failed (exit $rc)"
  _SPIN_LABEL=""
  return "$rc"
}

# ── print_banner ───────────────────────────────────────────────────────────────
print_banner() {
  local ver="${SETUP_VERSION:-dev}"

  # Hardware summary — use globals from detect_hardware (already ran)
  local hw=""
  [[ -n "${GPU_NAME:-}" ]] && hw="GPU  ${GPU_NAME}  (${GPU_VRAM_MIB:-?} MiB)"

  local inner=$(( _W + 2 ))
  echo ""
  printf "  ${BCYN}╭"; printf '─%.0s' $(seq 1 $inner); printf "╮${NC}\n"
  printf "  ${BCYN}│${NC}  ${BOLD}llm-setup${NC}  ${DIM}v%-*s${NC}  ${BCYN}│${NC}\n" \
    $(( inner - 13 )) "$ver"
  printf "  ${BCYN}│${NC}  ${DIM}%-*s${NC}  ${BCYN}│${NC}\n" \
    $(( inner - 2 )) "Ollama  ·  oterm  ·  MCP Bridges  ·  Coding Agents"
  if [[ -n "$hw" ]]; then
    printf "  ${BCYN}│${NC}  ${DIM}%-*s${NC}  ${BCYN}│${NC}\n" $(( inner - 2 )) "$hw"
  fi
  printf "  ${BCYN}╰"; printf '─%.0s' $(seq 1 $inner); printf "╯${NC}\n"
  echo ""
}

# ── print_summary ──────────────────────────────────────────────────────────────
print_summary() {
  local total_time="${1:-}"
  local inner=$(( _W + 2 ))

  echo ""
  printf "  ${BGRN}╭"; printf '─%.0s' $(seq 1 $inner); printf "╮${NC}\n"
  printf "  ${BGRN}│${NC}  ${BOLD}%-*s${NC}  ${BGRN}│${NC}\n" $(( inner - 2 )) "Installation complete  ✔"
  [[ -n "$total_time" ]] && \
    printf "  ${BGRN}│${NC}  ${DIM}%-*s${NC}  ${BGRN}│${NC}\n" $(( inner - 2 )) "Total time: $total_time"
  printf "  ${BGRN}╰"; printf '─%.0s' $(seq 1 $inner); printf "╯${NC}\n"
  echo ""

  printf "  ${BOLD}%-26s  %-18s  %s${NC}\n" "Service" "Command" "URL"
  printf "  ${DIM}"; printf '─%.0s' $(seq 1 $inner); printf "${NC}\n"

  { command -v oterm &>/dev/null || [[ -x "$HOME/.local/share/oterm-venv/bin/oterm" ]]; } && \
    printf "  ${GRN}✔${NC}  %-24s  ${CYN}%-16s${NC}  ${DIM}%s${NC}\n" \
      "oterm" "chat" "(terminal UI)"
  command -v ollama &>/dev/null && \
    printf "  ${GRN}✔${NC}  %-24s  ${CYN}%-16s${NC}  ${DIM}%s${NC}\n" \
      "Ollama" "ollama list" "http://localhost:11434"
  curl -sf --max-time 1 http://127.0.0.1:8010/openapi.json &>/dev/null && \
    printf "  ${GRN}✔${NC}  %-24s  ${CYN}%-16s${NC}  ${DIM}%s${NC}\n" \
      "MCP time" "llm-mcp-start" "http://localhost:8010"
  curl -sf --max-time 1 http://127.0.0.1:8011/openapi.json &>/dev/null && \
    printf "  ${GRN}✔${NC}  %-24s  ${CYN}%-16s${NC}  ${DIM}%s${NC}\n" \
      "MCP filesystem" "" "http://localhost:8011"

  echo ""

  local agents=()
  command -v qwen   &>/dev/null && agents+=("qwen-code")
  command -v codex  &>/dev/null && agents+=("codex")
  command -v aider  &>/dev/null && agents+=("aider")
  command -v claude &>/dev/null && agents+=("claude")
  (( ${#agents[@]} > 0 )) && \
    printf "  ${BOLD}Coding agents:${NC}  %s\n" "${agents[*]}"

  echo ""
  printf "  ${DIM}Run ${NC}${CYN}llm-doctor${NC}${DIM} to verify · ${NC}${CYN}llm-switch${NC}${DIM} to change model${NC}\n"
  printf "  ${DIM}Log → %s${NC}\n" "${LOG_FILE:-/tmp/llm-setup.log}"
  echo ""
}
