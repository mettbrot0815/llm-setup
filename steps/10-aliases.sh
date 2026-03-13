#!/usr/bin/env bash
# steps/10-aliases.sh — shell aliases (only for commands that actually exist)

step "Aliases"

ALIAS_FILE="$CONFIG_DIR/aliases.sh"

cat > "$ALIAS_FILE" << 'ALIASES'
# llm-setup — sourced from ~/.bashrc
alias ask='run-model'
alias llm-status='llm-doctor'
alias fix='llm-fix'
alias models='llm-switch'
alias model-add='llm-add'
# 'code' intentionally not aliased — it conflicts with VS Code CLI
alias ai='aider'
alias cc='claude-code'
alias cx='codex'
alias qc='qwen-code'
ALIASES

if ! grep -qF "llm-setup aliases" "$HOME/.bashrc" 2>/dev/null; then
  echo ""                                                           >> "$HOME/.bashrc"
  echo "# llm-setup aliases"                                       >> "$HOME/.bashrc"
  echo "[ -f \"$ALIAS_FILE\" ] && source \"$ALIAS_FILE\""          >> "$HOME/.bashrc"
fi

ok "Aliases ready (run: source ~/.bashrc)"
