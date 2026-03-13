#!/usr/bin/env bash
# steps/06-model.sh — model selection and pull

step "Model"

# ── Verify ollama binary is usable ────────────────────────────────────────────
_ollama_bin=$(command -v ollama 2>/dev/null || true)
if [[ -z "$_ollama_bin" ]]; then
  error "ollama not found. Re-run setup or: curl -fsSL https://ollama.com/install.sh | sh"
fi
if [[ ! -x "$_ollama_bin" ]]; then
  warn "ollama not executable — fixing: sudo chmod +x $_ollama_bin"
  sudo chmod +x "$_ollama_bin" || error "Cannot chmod ollama. Run: sudo chmod +x $_ollama_bin"
fi

# ── API must be up before we pull ─────────────────────────────────────────────
if ! curl -sf --max-time 3 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  warn "Ollama API not responding — attempting to start…"
  if ! is_wsl2 && command -v systemctl &>/dev/null; then
    sudo systemctl start ollama >> "$LOG_FILE" 2>&1 || true
  else
    nohup ollama serve >> "$LOG_FILE" 2>&1 &
    disown $! 2>/dev/null
  fi
  for (( _w=0; _w<15; _w++ )); do
    curl -sf --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && break
    sleep 1
  done
fi

# ── Auto-detect ───────────────────────────────────────────────────────────────
INSTALLED_MODELS=()
auto_select_model

echo ""
echo -e "  ${BOLD}Auto-selected:${NC}  ${_M[name]}  (${_M[size_gb]} GB)"
echo -e "  ${DIM}Ollama tag:${NC}  ${_M[tag]}"
echo ""

if ! ask_yes_no "Use this model?" "y"; then
  pick_model
fi

print_model_card
save_model_config
info "Model config saved: $CONFIG_DIR/model.conf"

if ollama_has_model "${_M[tag]}"; then
  ok "Model already installed: ${_M[tag]}"
  return 0
fi

(( HAVE_INTERNET )) || { warn "No internet — pull later: ollama pull ${_M[tag]}"; return 0; }

echo -e "  ${DIM}Model download: ~${_M[size_gb]} GB — this is the large part of the install.${NC}"
echo -e "  ${DIM}Skip if on a slow connection and pull later with: ollama pull ${_M[tag]}${NC}"
echo ""
if ! ask_yes_no "Pull ${_M[tag]} now?  (~${_M[size_gb]} GB)" "n"; then
  info "Skipped — pull later: ollama pull ${_M[tag]}"
  return 0
fi

echo ""
echo -e "  ${BOLD}⬇  ollama pull ${_M[tag]}${NC}"
echo ""

ollama pull "${_M[tag]}"
_pull_rc=$?

case $_pull_rc in
  0)
    ok "Model ready: ${_M[tag]}"
    save_model_config
    ;;
  126)
    fail "Permission denied on ollama binary (exit 126)"
    warn "Fix: sudo chmod +x $_ollama_bin  then: ollama pull ${_M[tag]}"
    ;;
  139)
    fail "Ollama segfaulted (exit 139) — this is a CUDA library conflict"
    echo ""
    if is_wsl2; then
      echo -e "  ${BOLD}You are on WSL2.${NC}  This is almost always a CUDA toolkit"
      echo -e "  version mismatch — your toolkit version must be <= your"
      echo -e "  Windows driver's supported CUDA version."
      echo ""
      echo -e "  ${BOLD}Fix:${NC}"
      echo -e "  ${CYAN}1.${NC}  Check what your driver supports:"
      echo -e "       nvidia-smi  ← see 'CUDA Version' (e.g. 12.1)"
      echo -e "  ${CYAN}2.${NC}  Remove mismatched toolkit:"
      echo -e "       sudo apt-get remove --purge 'cuda-toolkit-*'"
      echo -e "  ${CYAN}3.${NC}  Reinstall from the WSL2-specific repo (not ubuntu2204):"
      echo -e "       wget https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/cuda-keyring_1.0-1_all.deb"
      echo -e "       sudo dpkg -i cuda-keyring_1.0-1_all.deb"
      echo -e "       sudo apt-get update && sudo apt-get install -y cuda-toolkit-12-0"
      echo -e "  ${CYAN}4.${NC}  Reinstall ollama:"
      echo -e "       curl -fsSL https://ollama.com/install.sh | sh"
      echo -e "  ${CYAN}5.${NC}  Pull the model:"
      echo -e "       OLLAMA_NUM_GPU=1 ollama pull ${_M[tag]}"
      echo ""
      echo -e "  ${DIM}Note: do NOT install NVIDIA drivers inside WSL2 — the"
      echo -e "  Windows driver handles hardware. Only the toolkit goes inside.${NC}"
    else
      echo -e "  ${BOLD}Possible causes:${NC}"
      echo -e "    ${CYAN}·${NC}  CUDA version mismatch between driver and toolkit"
      echo -e "    ${CYAN}·${NC}  Corrupt ollama binary"
      echo ""
      echo -e "  ${BOLD}Fix:${NC}"
      echo -e "  ${CYAN}1.${NC}  curl -fsSL https://ollama.com/install.sh | sh"
      echo -e "  ${CYAN}2.${NC}  ollama pull ${_M[tag]}"
    fi
    echo ""
    warn "Setup continuing — pull the model manually once ollama is stable"
    ;;
  *)
    fail "ollama pull failed (exit $_pull_rc)"
    warn "Pull manually: ollama pull ${_M[tag]}"
    ;;
esac
