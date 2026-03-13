#!/usr/bin/env bash
# steps/12-validate.sh — final checks

step "Validation"

# Ensure MCP port vars are defined (sourced from install.sh context or paths.sh)
MCP_TIME_PORT="${MCP_TIME_PORT:-8010}"
MCP_FS_PORT="${MCP_FS_PORT:-8011}"

PASS=0; FAIL=0; WARN=0
_ok()   { ok "$1";   PASS=$(( PASS+1 )); }
_fail() { fail "$1"; FAIL=$(( FAIL+1 )); }
_warn() { warn "$1"; WARN=$(( WARN+1 )); }

# Ollama binary
_oll=$(command -v ollama 2>/dev/null || true)
if [[ -n "$_oll" && -x "$_oll" ]]; then
  _ok "Ollama $(ollama --version 2>/dev/null) ✔"
else
  _fail "Ollama binary missing or not executable"
fi

# Ollama API
if curl -sf --max-time 3 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  _ok "Ollama API responding ✔"
else
  _fail "Ollama API not responding — run: ollama serve"
fi

# Chat UI
if [[ -x "$HOME/.local/share/oterm-venv/bin/oterm" ]] || command -v oterm &>/dev/null; then
  _ok "oterm installed ✔"
else
  _warn "oterm not installed — run: llm-chat-ui"
fi

# Model config
if [[ -f "$CONFIG_DIR/model.conf" ]]; then
  source "$CONFIG_DIR/model.conf" 2>/dev/null || true
  _ok "Model config: ${OLLAMA_TAG:-?} ✔"
else
  _fail "model.conf missing — run: llm-setup"
fi

# Tool scripts
for _t in llm-switch llm-add llm-doctor llm-fix llm-update llm-mcp-start llm-mcp-stop llm-import-models; do
  [[ -x "$BIN_DIR/$_t" ]] && _ok "$_t ✔" || _fail "$_t missing"
done

# Coding agents (optional — ok only if installed)
for _t in aider codex claude-code qwen-code; do
  [[ -x "$BIN_DIR/$_t" ]] && _ok "$_t ✔"
done

# MCP bridges
if curl -sf --max-time 2 "http://127.0.0.1:${MCP_TIME_PORT}/openapi.json" >/dev/null 2>&1; then
  _ok "MCP/time on :${MCP_TIME_PORT} ✔"
else
  _warn "MCP/time not responding — run: llm-mcp-start"
fi
if curl -sf --max-time 2 "http://127.0.0.1:${MCP_FS_PORT}/openapi.json" >/dev/null 2>&1; then
  _ok "MCP/filesystem on :${MCP_FS_PORT} ✔"
else
  _warn "MCP/filesystem not responding — run: llm-mcp-start"
fi

echo ""
echo -e "  ${DIM}Passed: ${GREEN}${PASS}${NC}  ${DIM}Warnings: ${BYLW}${WARN}${NC}  ${DIM}Failed: ${RED}${FAIL}${NC}"
(( FAIL > 0 )) && echo -e "  ${DIM}Re-run: ${CYAN}llm-setup${NC}"
true
