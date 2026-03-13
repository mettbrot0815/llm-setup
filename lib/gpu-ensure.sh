#!/usr/bin/env bash
# lib/gpu-ensure.sh — sourced by agent wrappers to guarantee Ollama uses GPU
# Usage: source gpu-ensure.sh "$MODEL_TAG"
#   $1 = ollama model tag (e.g. "qwen3:14b" or "qwen3-coder:14b")

# Inline fallbacks for ok/warn/info in case ui.sh is not sourced
_gu_ok()   { echo -e "  ${BGREEN:-\033[1;32m}✔${NC:-\033[0m}  $1"; }
_gu_warn() { echo -e "  ${BYELLOW:-\033[1;33m}⚠${NC:-\033[0m}  $1"; }
_gu_info() { echo -e "  ${DIM:-\033[2m}·${NC:-\033[0m}  ${DIM:-\033[2m}$1${NC:-\033[0m}"; }
command -v ok   &>/dev/null || ok()   { _gu_ok   "$@"; }
command -v warn &>/dev/null || warn() { _gu_warn "$@"; }
command -v info &>/dev/null || info() { _gu_info "$@"; }

_gpu_ensure() {
  local model="${1:-}"
  local model_short="${model%%:*}"

  command -v nvidia-smi &>/dev/null \
    && nvidia-smi --query-gpu=name --format=csv,noheader &>/dev/null \
    || return 0  # no NVIDIA GPU — nothing to do

  # Ensure Ollama systemd override has OLLAMA_NUM_GPU=99
  # Must handle: file missing, dir missing, file exists but lacks the var
  local _override="/etc/systemd/system/ollama.service.d/override.conf"
  if ! grep -q "OLLAMA_NUM_GPU" "$_override" 2>/dev/null; then
    echo -e "  ${BYELLOW:-\033[1;33m}⚠${NC:-\033[0m}  Adding OLLAMA_NUM_GPU=99 to Ollama service…"
    sudo mkdir -p "$(dirname "$_override")"
    # Write a complete override file (idempotent)
    printf '[Service]\nEnvironment="OLLAMA_NUM_GPU=99"\n' \
      | sudo tee "$_override" >/dev/null 2>&1
    sudo systemctl daemon-reload 2>/dev/null || true
    sudo systemctl restart ollama 2>/dev/null || true
    for _i in {1..20}; do
      curl -sf --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && break
      sleep 1
    done
    ok "Ollama restarted with GPU=99"
  fi

  # Ensure Ollama is running
  if ! curl -sf --max-time 3 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    echo -e "  ${DIM}Starting Ollama…${NC}"
    if command -v systemctl &>/dev/null; then
      sudo systemctl start ollama 2>/dev/null || true
    else
      OLLAMA_NUM_GPU=99 nohup ollama serve >/dev/null 2>&1 & disown $!
    fi
    for _i in {1..15}; do
      curl -sf --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && break
      sleep 1
    done
  fi

  [[ -z "$model" ]] && return 0

  # Check if model is loaded on CPU-only and force reload onto GPU
  local _ps _proc
  _ps=$(ollama ps 2>/dev/null || true)
  if echo "$_ps" | grep -qi "$model_short"; then
    _proc=$(echo "$_ps" | grep -i "$model_short" | awk '{print $4, $5, $6}')
    if echo "$_proc" | grep -qi "cpu" && ! echo "$_proc" | grep -qi "gpu"; then
      echo -e "  ${BYELLOW}⚠${NC}  $model_short loaded on CPU — forcing GPU reload…"
      # Evict model
      curl -sf -X POST http://127.0.0.1:11434/api/generate \
        -d "{\"model\":\"$model\",\"keep_alive\":0}" >/dev/null 2>&1 || true
      sleep 2
      # Reload with GPU
      curl -sf --max-time 60 -X POST http://127.0.0.1:11434/api/generate \
        -d "{\"model\":\"$model\",\"prompt\":\"\",\"stream\":false,\"options\":{\"num_gpu\":99}}" \
        >/dev/null 2>&1 || true
      sleep 2
    fi
  else
    # Pre-load model onto GPU before agent starts
    echo -e "  ${DIM}Loading $model onto GPU…${NC}"
    curl -sf --max-time 60 -X POST http://127.0.0.1:11434/api/generate \
      -d "{\"model\":\"$model\",\"prompt\":\"\",\"stream\":false,\"options\":{\"num_gpu\":99}}" \
      >/dev/null 2>&1 || true
  fi

  # Report GPU status
  local _ps2 _proc2 _vused _vtotal
  _ps2=$(ollama ps 2>/dev/null || true)
  if echo "$_ps2" | grep -qi "$model_short"; then
    _proc2=$(echo "$_ps2" | grep -i "$model_short" | awk '{print $4, $5, $6}')
    if echo "$_proc2" | grep -qi "gpu"; then
      _vused=$(nvidia-smi --query-gpu=memory.used   --format=csv,noheader,nounits 2>/dev/null | head -1 | xargs)
      _vtotal=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 | xargs)
      ok "GPU active  (${_vused:-?} / ${_vtotal:-?} MiB VRAM)"
    else
      warn "Model still on CPU — run: llm-fix"
    fi
  fi
}
