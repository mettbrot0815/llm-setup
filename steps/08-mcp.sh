#!/usr/bin/env bash
# steps/08-mcp.sh — MCP tool bridges (optional, install on demand)
# Bridges: mcp-server-time (:8010)  +  mcp-server-filesystem (:8011)

step "MCP Tools  ${DIM}(optional)${NC}"

MCP_TIME_PORT=8010
MCP_FS_PORT=8011
MCP_VENV="$HOME/.local/share/mcp-venv"
MCP_LOG="$CONFIG_DIR/mcp.log"
MCP_PID_DIR="$CONFIG_DIR/pids"

mkdir -p "$MCP_PID_DIR"

# ── Already installed? ─────────────────────────────────────────────────────────
if [[ -x "$MCP_VENV/bin/mcpo" ]]; then
  ok "MCP already installed — skipping (run: llm-mcp-start to start bridges)"
  # Still write conf in case it's missing
  cat > "$CONFIG_DIR/mcp.conf" << MCPCONF
MCP_TIME_PORT="$MCP_TIME_PORT"
MCP_FS_PORT="$MCP_FS_PORT"
MCP_VENV="$MCP_VENV"
MCP_LOG="$MCP_LOG"
MCP_PID_DIR="$MCP_PID_DIR"
MCPCONF
  return 0
fi

# ── Ask ────────────────────────────────────────────────────────────────────────
if [[ -t 0 ]]; then
  echo ""
  echo -e "  ${BCYAN}╭──────────────────────────────────────────────────────────╮${NC}"
  echo -e "  ${BCYAN}│${NC}  MCP Tool Bridges  (optional)                            ${BCYAN}│${NC}"
  echo -e "  ${BCYAN}├──────────────────────────────────────────────────────────┤${NC}"
  echo -e "  ${BCYAN}│${NC}  Lets AI models call real tools during chat:             ${BCYAN}│${NC}"
  echo -e "  ${BCYAN}│${NC}  ·  time        current date/time, timezone  (:8010)     ${BCYAN}│${NC}"
  echo -e "  ${BCYAN}│${NC}  ·  filesystem  read/write files in ~/        (:8011)    ${BCYAN}│${NC}"
  echo -e "  ${BCYAN}│${NC}                                                          ${BCYAN}│${NC}"
  echo -e "  ${BCYAN}│${NC}  ~5 MB install · install later: llm-mcp-start            ${BCYAN}│${NC}"
  echo -e "  ${BCYAN}╰──────────────────────────────────────────────────────────╯${NC}"
  echo ""
  echo -ne "  Install MCP bridges? [y/N]: "
  read -r _mcp_choice
  _mcp_choice="${_mcp_choice:-n}"
else
  # Non-interactive: skip by default
  _mcp_choice="n"
fi

if [[ "${_mcp_choice,,}" != "y" ]]; then
  info "MCP skipped — install anytime with: llm-mcp-start"
  return 0
fi

# ── Install ────────────────────────────────────────────────────────────────────
(( HAVE_INTERNET )) || { warn "No internet — skipping MCP install"; return 0; }

if [[ -d "$MCP_VENV" && ! -f "$MCP_VENV/bin/activate" ]]; then
  info "Removing incomplete MCP venv…"; rm -rf "$MCP_VENV"
fi

"$PYTHON_BIN" -m venv "$MCP_VENV" >> "$LOG_FILE" 2>&1 \
  || { warn "Failed to create MCP venv"; return 0; }
"$MCP_VENV/bin/pip" install --quiet --no-cache-dir --upgrade pip >> "$LOG_FILE" 2>&1

run_with_progress "mcpo + mcp-server-time (~5 MB)" "$LOG_FILE" \
  "$MCP_VENV/bin/pip" install --no-cache-dir mcpo mcp-server-time

if (( $? != 0 )); then
  warn "MCP install failed — run: llm-mcp-start to retry"
  return 0
fi
ok "mcpo + mcp-server-time installed"

# ── Filesystem allowed directories ────────────────────────────────────────────
MCP_FS_DIRS=("$HOME" "$HOME/Documents" "$HOME/Downloads")
is_wsl2 && MCP_FS_DIRS+=("/mnt")

echo ""
echo -e "  ${DIM}Filesystem bridge will have access to:${NC}"
for _d in "${MCP_FS_DIRS[@]}"; do
  [[ -d "$_d" ]] && echo -e "    ${CYAN}·${NC}  $_d"
done
echo ""
echo -e "  ${DIM}Add extra directories (space-separated, or Enter to skip):${NC}"
read -r -p "  Extra dirs: " _extra_dirs
if [[ -n "$_extra_dirs" ]]; then
  read -ra _dirs_arr <<< "$_extra_dirs"
  for _d in "${_dirs_arr[@]}"; do
    [[ -d "$_d" ]] && MCP_FS_DIRS+=("$_d") || warn "Skipping non-existent dir: $_d"
  done
fi
printf '%s\n' "${MCP_FS_DIRS[@]}" > "$CONFIG_DIR/mcp_fs_dirs.txt"

# ── Write mcp.conf ─────────────────────────────────────────────────────────────
cat > "$CONFIG_DIR/mcp.conf" << MCPCONF
MCP_TIME_PORT="$MCP_TIME_PORT"
MCP_FS_PORT="$MCP_FS_PORT"
MCP_VENV="$MCP_VENV"
MCP_LOG="$MCP_LOG"
MCP_PID_DIR="$MCP_PID_DIR"
MCPCONF
ok "MCP config written"

# ── bashrc auto-start hook ─────────────────────────────────────────────────────
if ! grep -qF "llm-mcp-start" "$HOME/.bashrc" 2>/dev/null; then
  printf '\n# llm-setup: start MCP tool bridges\n' >> "$HOME/.bashrc"
  printf '[ -x "$HOME/.local/bin/llm-mcp-start" ] && llm-mcp-start &>/dev/null &\n' \
    >> "$HOME/.bashrc"
  info "Added MCP auto-start to ~/.bashrc"
fi

# ── Start bridges now ─────────────────────────────────────────────────────────
info "Starting MCP bridges…"
_mcp_start() {
  local name="$1" port="$2"; shift 2
  local pid_file="$MCP_PID_DIR/mcpo-${name}.pid"
  [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file" 2>/dev/null)" 2>/dev/null && return 0
  rm -f "$pid_file"
  nohup "$MCP_VENV/bin/mcpo" --host 127.0.0.1 --port "$port" -- "$@" \
    >> "$MCP_LOG" 2>&1 &
  local _pid=$!
  echo "$_pid" > "$pid_file"
  disown "$_pid" 2>/dev/null
}

[[ -x "$MCP_VENV/bin/mcp-server-time" ]] \
  && _mcp_start time "$MCP_TIME_PORT" "$MCP_VENV/bin/mcp-server-time" \
  || warn "mcp-server-time not found"

command -v npx &>/dev/null \
  && _mcp_start filesystem "$MCP_FS_PORT" npx -y @modelcontextprotocol/server-filesystem "${MCP_FS_DIRS[@]}" \
  || warn "npx not found — filesystem bridge skipped"

# ── Verify ─────────────────────────────────────────────────────────────────────
for _pair in "time:$MCP_TIME_PORT" "filesystem:$MCP_FS_PORT"; do
  _mcp_name="${_pair%%:*}"
  _mcp_port="${_pair##*:}"
  _ok=0
  for (( _i=0; _i<15; _i++ )); do
    sleep 2
    curl -sf --max-time 3 "http://127.0.0.1:$_mcp_port/openapi.json" >/dev/null 2>&1 \
      && { _ok=1; break; }
  done
  (( _ok )) && ok "mcpo/$_mcp_name ready on :$_mcp_port" \
             || warn "mcpo/$_mcp_name not responding — run: llm-mcp-start"
done

echo ""
