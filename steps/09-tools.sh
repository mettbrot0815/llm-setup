#!/usr/bin/env bash
# steps/09-tools.sh — copy tools/ to ~/.local/bin, write run-model wrapper

step "Helper scripts"

mkdir -p "$BIN_DIR"

# ── Copy lib/ to fixed location tools can always find ────────────────────────
_lib_dest="$HOME/.local/share/llm-setup/lib"
mkdir -p "$_lib_dest"
cp "$SETUP_DIR/lib/"*.sh "$_lib_dest/" \
  && ok "Lib files installed to $_lib_dest" \
  || warn "Some lib files may not have copied — tools may fail"

# ── Copy standalone tools ─────────────────────────────────────────────────────
for _tool in "$SETUP_DIR/tools/"*; do
  [[ -f "$_tool" ]] || continue
  _tname=$(basename "$_tool")
  cp "$_tool" "$BIN_DIR/$_tname"
  chmod +x "$BIN_DIR/$_tname"
done
ok "Tools installed to $BIN_DIR"

# ── run-model launcher ────────────────────────────────────────────────────────
cat > "$BIN_DIR/run-model" <<'RUNMODEL'
#!/usr/bin/env bash
CONF="$HOME/.config/llm-setup/model.conf"
[[ -f "$CONF" ]] && source "$CONF"
TAG="${OLLAMA_TAG:-}"
if [[ -z "$TAG" ]]; then
  echo "No model configured. Run: llm-switch" >&2; exit 1
fi
exec ollama run "$TAG" "$@"
RUNMODEL
chmod +x "$BIN_DIR/run-model"
ln -sf "$BIN_DIR/run-model" "$BIN_DIR/ask" 2>/dev/null || true

# ── Ollama convenience wrappers ────────────────────────────────────────────────
for _pair in "ollama-run:ollama run" "ollama-pull:ollama pull" "ollama-list:ollama list"; do
  _wname="${_pair%%:*}"
  _wcmd="${_pair##*:}"
  printf '#!/usr/bin/env bash\nexec %s "$@"\n' "$_wcmd" > "$BIN_DIR/$_wname"
  chmod +x "$BIN_DIR/$_wname"
done

# ── llm-setup re-runner ───────────────────────────────────────────────────────
cat > "$BIN_DIR/llm-setup" << 'RERUN'
#!/usr/bin/env bash
# Always prefer the canonical installed copy
_target="$HOME/.local/share/llm-setup/install.sh"
if [[ -x "$_target" ]]; then
  exec bash "$_target" "$@"
fi
# Fallback: relative to this script (dev/source checkout)
_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_rel="$(dirname "$_here")/llm-setup/install.sh"
[[ -x "$_rel" ]] && exec bash "$_rel" "$@"
echo "llm-setup not found — re-install: bash <(curl -fsSL https://raw.githubusercontent.com/mettbrot0815/llm-setup/main/install.sh)" >&2
exit 1
RERUN
chmod +x "$BIN_DIR/llm-setup"

# ── PATH ──────────────────────────────────────────────────────────────────────
if ! echo "$PATH" | grep -qF "$BIN_DIR"; then
  if ! grep -q "llm-setup PATH" "$HOME/.bashrc" 2>/dev/null; then
    { echo ""
      echo "# llm-setup PATH"
      echo "export PATH=\"$BIN_DIR:\$PATH\""
    } >> "$HOME/.bashrc"
  fi
fi
export PATH="$BIN_DIR:$PATH"

ok "All helper scripts ready"
