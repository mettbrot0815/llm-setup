#!/usr/bin/env bash
# lib/paths.sh — canonical install paths for tool scripts
CONF_DIR="$HOME/.config/llm-setup"
MODEL_CONF="$CONF_DIR/model.conf"
MCP_CONF="$CONF_DIR/mcp.conf"
VENV_DIR="$HOME/.local/share/llm-venv"
OTERM_VENV="$HOME/.local/share/oterm-venv"
MCP_VENV_DEFAULT="$HOME/.local/share/mcp-venv"
BIN_DIR="$HOME/.local/bin"

# Load MCP config with safe defaults
if [[ -f "$MCP_CONF" ]]; then
  source "$MCP_CONF"
fi
MCP_TIME_PORT="${MCP_TIME_PORT:-8010}"
MCP_FS_PORT="${MCP_FS_PORT:-8011}"
MCP_VENV="${MCP_VENV:-$MCP_VENV_DEFAULT}"
MCP_LOG="${MCP_LOG:-$CONF_DIR/mcp.log}"
MCP_PID_DIR="${MCP_PID_DIR:-$CONF_DIR/pids}"
