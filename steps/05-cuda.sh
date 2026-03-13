#!/usr/bin/env bash
# steps/05-cuda.sh — CUDA setup
#
# WSL2: Ollama ships its own bundled CUDA libs — no toolkit install needed.
#   We just pin /usr/lib/wsl/lib first in ldconfig (libcuda.so stub) and
#   register Ollama's bundled cuda_v12 dir so everything else can find it.
#   nvcc / the full toolkit is NOT required for Ollama GPU inference.
#
# Native Linux: install toolkit from nvidia repo if not present.

(( HAS_NVIDIA )) || { info "No NVIDIA GPU — skipping CUDA step"; return 0; }

step "CUDA toolkit"

_CUDA_TAG=""  # e.g. "cu121" — consumed by later steps

# Temp dir for .deb downloads — cleaned up on step exit
TEMP_DIR=$(mktemp -d)
_cuda_cleanup() { rm -rf "$TEMP_DIR" 2>/dev/null || true; }
trap '_cuda_cleanup' RETURN

# ── Map driver CUDA ver → wheel tag ───────────────────────────────────────────
_cuda_to_tag() {
  local ver="$1" maj="${1%%.*}" min="0"
  [[ "$ver" == *.* ]] && min=$(echo "$ver" | cut -d. -f2)
  if   [[ "$maj" == "11" ]];        then echo "cu118"
  elif [[ "$maj" == "12" ]]; then
    case "$min" in
      0|1) echo "cu121" ;; 2) echo "cu122" ;;
      3)   echo "cu123" ;; *) echo "cu124" ;;
    esac
  else echo "cu124"  # 13.x+ forward-compatible
  fi
}

# ── Driver CUDA cap ───────────────────────────────────────────────────────────
_driver_cuda_ver=$(nvidia-smi 2>/dev/null \
  | grep -oP 'CUDA Version:\s*\K[0-9]+\.[0-9]+' | head -1 || true)
info "Driver max CUDA: ${_driver_cuda_ver:-unknown}"

# ── WSL2 path — use Ollama's bundled CUDA, no toolkit install ─────────────────
if is_wsl2; then

  # 1. Pin /usr/lib/wsl/lib first — libcuda.so stub must come before any toolkit
  _wsl_lib="/usr/lib/wsl/lib"
  if [[ -d "$_wsl_lib" ]]; then
    _wsl_conf="/etc/ld.so.conf.d/00-wsl-cuda.conf"
    if [[ ! -f "$_wsl_conf" ]] || ! grep -q "$_wsl_lib" "$_wsl_conf" 2>/dev/null; then
      echo "$_wsl_lib" | sudo tee "$_wsl_conf" >/dev/null 2>&1 \
        && sudo ldconfig 2>/dev/null || true
    fi
    export LD_LIBRARY_PATH="${_wsl_lib}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    ok "WSL2 CUDA stub: $_wsl_lib  (first in library path)"
  else
    warn "/usr/lib/wsl/lib not found — is Docker Desktop / WSL2 GPU configured?"
  fi

  # 2. Use Ollama's bundled CUDA libs — no apt install needed
  _ollama_cuda=""
  for _d in /usr/local/lib/ollama/cuda_v12 /usr/local/lib/ollama/cuda_v11; do
    [[ -d "$_d" ]] && { _ollama_cuda="$_d"; break; }
  done

  if [[ -n "$_ollama_cuda" ]]; then
    # Register in ldconfig so other tools can find the libs
    _oll_conf="/etc/ld.so.conf.d/llm-setup-ollama-cuda.conf"
    grep -q "$_ollama_cuda" "$_oll_conf" 2>/dev/null \
      || { echo "$_ollama_cuda" | sudo tee "$_oll_conf" >/dev/null 2>&1; \
           sudo ldconfig 2>/dev/null || true; }
    [[ "$_ollama_cuda" == *cuda_v12* ]] && _CUDA_TAG="cu124" || _CUDA_TAG="cu118"
    ok "Ollama bundled CUDA: $_ollama_cuda  (tag: $_CUDA_TAG)"
  else
    # Ollama not yet installed — set tag from driver version, Ollama will bundle CUDA on install
    _CUDA_TAG=$(_cuda_to_tag "${_driver_cuda_ver:-12.0}")
    info "Ollama CUDA libs not found yet — will be available after Ollama installs"
    info "Tag set from driver: $_CUDA_TAG"
  fi

  # 3. Warn if a conflicting system toolkit is installed (common cause of segfaults)
  if command -v nvcc &>/dev/null; then
    _nvcc_ver=$(nvcc --version 2>/dev/null | grep -oP 'release \K[0-9.]+' | head -1)
    _nvcc_maj="${_nvcc_ver%%.*}"
    _drv_maj="${_driver_cuda_ver%%.*}"
    if [[ -n "$_drv_maj" && -n "$_nvcc_maj" ]] \
        && (( _nvcc_maj > _drv_maj )) 2>/dev/null; then
      warn "System CUDA toolkit $_nvcc_ver > driver max $_driver_cuda_ver — may cause segfaults"
      warn "Fix: sudo apt-get remove --purge 'cuda-toolkit-*'"
    else
      ok "System CUDA toolkit: nvcc $_nvcc_ver  (optional, not required for Ollama)"
    fi
  fi

  return 0
fi

# ── Native Linux ──────────────────────────────────────────────────────────────
if command -v nvcc &>/dev/null; then
  _cuda_ver=$(nvcc --version 2>/dev/null | grep -oP 'release \K[0-9.]+' | head -1)
  ok "CUDA already installed: $_cuda_ver"
  _CUDA_TAG=$(_cuda_to_tag "$_cuda_ver")
  info "Wheel tag: $_CUDA_TAG"
  return 0
fi

# Ollama-bundled CUDA?
for _d in /usr/local/lib/ollama/cuda_v12 /usr/local/lib/ollama/cuda_v11; do
  if [[ -d "$_d" ]]; then
    ok "Ollama-bundled CUDA: $_d"
    _cuda_conf="/etc/ld.so.conf.d/llm-setup-cuda.conf"
    grep -q "$_d" "$_cuda_conf" 2>/dev/null \
      || { echo "$_d" | sudo tee "$_cuda_conf" >/dev/null; sudo ldconfig 2>/dev/null; }
    [[ "$_d" == *cuda_v12* ]] && _CUDA_TAG="cu121" || _CUDA_TAG="cu118"
    return 0
  fi
done

(( HAVE_INTERNET )) || { warn "No internet — skipping CUDA install"; return 0; }

# Install via nvidia ubuntu repo
_ubuntu_short="${DISTRO_VERSION:-22.04}"
_ubuntu_short="${_ubuntu_short//./}"
_keyring_url="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu${_ubuntu_short}/x86_64/cuda-keyring_1.1-1_all.deb"
_keyring_deb="$TEMP_DIR/cuda-keyring.deb"

info "Installing CUDA keyring (ubuntu repo)…"
if retry 3 5 wget -q -O "$_keyring_deb" "$_keyring_url" >> "$LOG_FILE" 2>&1; then
  apt_wait dpkg -i "$_keyring_deb" >> "$LOG_FILE" 2>&1 || true
  apt_wait apt-get update -qq >> "$LOG_FILE" 2>&1 || true
  run_with_progress "cuda-toolkit-12-0 (~2 GB)" "$LOG_FILE" \
    sudo apt-get install -y -q cuda-toolkit-12-0 \
    || warn "CUDA toolkit install failed"
else
  run_with_progress "nvidia-cuda-toolkit (fallback)" "$LOG_FILE" \
    sudo apt-get install -y -q nvidia-cuda-toolkit || true
fi

if command -v nvcc &>/dev/null; then
  _cv=$(nvcc --version 2>/dev/null | grep -oP 'release \K[0-9.]+' | head -1)
  ok "CUDA installed: $_cv"
  _CUDA_TAG=$(_cuda_to_tag "$_cv")
else
  warn "nvcc not available — llama-cpp will use CPU build"
  _CUDA_TAG=""
fi
