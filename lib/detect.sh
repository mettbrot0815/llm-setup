#!/usr/bin/env bash
# lib/detect.sh — hardware detection (GPU, VRAM, RAM, CPU, WSL2)

detect_hardware() {
  # ── WSL2 ──────────────────────────────────────────────────────────────────
  IS_WSL2=0
  grep -qi microsoft /proc/version 2>/dev/null && IS_WSL2=1

  # ── RAM ───────────────────────────────────────────────────────────────────
  TOTAL_RAM_GB=$(awk '/^MemTotal/{printf "%d", $2/1024/1024}' /proc/meminfo 2>/dev/null)
  TOTAL_RAM_GB="${TOTAL_RAM_GB:-4}"
  (( TOTAL_RAM_GB < 1 )) && TOTAL_RAM_GB=1
  RAM_FOR_LAYERS_GB=$(( TOTAL_RAM_GB > 3 ? TOTAL_RAM_GB - 3 : 1 ))

  # ── CPU ───────────────────────────────────────────────────────────────────
  CPU_NAME=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "Unknown")
  HW_THREADS=$(nproc 2>/dev/null || echo 4)
  # Use physical cores if possible
  _phys=$(lscpu 2>/dev/null | awk '/^Core\(s\) per socket/{print $NF}')
  _sock=$(lscpu 2>/dev/null | awk '/^Socket\(s\)/{print $NF}')
  _phys="${_phys:-0}"
  _sock="${_sock:-0}"
  if [[ "$_phys" =~ ^[0-9]+$ ]] && [[ "$_sock" =~ ^[0-9]+$ ]]; then
    HW_THREADS=$(( _phys * _sock ))
  fi
  (( HW_THREADS < 1  )) && HW_THREADS=1
  (( HW_THREADS > 16 )) && HW_THREADS=16

  # ── NVIDIA ────────────────────────────────────────────────────────────────
  HAS_NVIDIA=0; GPU_VRAM_GB=0; GPU_VRAM_MIB=0; GPU_NAME=""; NVIDIA_DRIVER=""
  if command -v nvidia-smi &>/dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 | xargs)
    NVIDIA_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 | xargs)
    _vram_mib=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')
    if [[ "$_vram_mib" =~ ^[0-9]+$ ]] && (( _vram_mib > 512 )); then
      HAS_NVIDIA=1
      GPU_VRAM_MIB=$_vram_mib
      GPU_VRAM_GB=$(( _vram_mib / 1024 ))
    fi
  fi

  # ── AMD ───────────────────────────────────────────────────────────────────
  HAS_AMD=0
  if [[ $HAS_NVIDIA -eq 0 ]]; then
    for _f in /sys/class/drm/card*/device/mem_info_vram_total; do
      [[ -f "$_f" ]] || continue
      _vram_bytes=$(cat "$_f" 2>/dev/null || echo 0)
      _vram_mib=$(( _vram_bytes / 1024 / 1024 ))
      if (( _vram_mib > 512 )); then
        HAS_AMD=1
        GPU_VRAM_MIB=$_vram_mib
        GPU_VRAM_GB=$(( _vram_mib / 1024 ))
        GPU_NAME=$(cat "$(dirname "$_f")/product_name" 2>/dev/null | xargs || echo "AMD GPU")
        break
      fi
    done
  fi

  HAS_GPU=$(( HAS_NVIDIA || HAS_AMD ))
  GPU_TYPE="CPU-only"
  (( HAS_NVIDIA )) && GPU_TYPE="NVIDIA"
  (( HAS_AMD    )) && GPU_TYPE="AMD/ROCm"

  # VRAM usable = total minus ~1.5 GB OS overhead
  VRAM_USABLE_MIB=$(( GPU_VRAM_MIB > 1536 ? GPU_VRAM_MIB - 1536 : 0 ))

  # Batch size based on VRAM
  if   (( GPU_VRAM_GB >= 24 )); then BATCH=2048
  elif (( GPU_VRAM_GB >= 16 )); then BATCH=1024
  elif (( GPU_VRAM_GB >= 8  )); then BATCH=512
  elif (( GPU_VRAM_GB >= 4  )); then BATCH=256
  else                               BATCH=128
  fi

  FREE_DISK_GB=$(df -BG "$HOME" 2>/dev/null | awk 'NR==2{gsub("G",""); print $4}' || echo 0)

  # ── WSL2: ensure /usr/lib/wsl/lib (libcuda.so stub) is first ─────────────
  WSL_CUDA_FIXED=0
  if (( IS_WSL2 && HAS_NVIDIA )); then
    _wsl_lib="/usr/lib/wsl/lib"
    if [[ -d "$_wsl_lib" ]]; then
      _wsl_conf="/etc/ld.so.conf.d/00-wsl-cuda.conf"
      if [[ ! -f "$_wsl_conf" ]] || ! grep -q "$_wsl_lib" "$_wsl_conf" 2>/dev/null; then
        echo "$_wsl_lib" | sudo tee "$_wsl_conf" >/dev/null 2>&1 && sudo ldconfig 2>/dev/null || true
      fi
      export LD_LIBRARY_PATH="${_wsl_lib}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
      WSL_CUDA_FIXED=1
    fi
  fi
}

gpu_layers_for() {
  local size_gb=$1 num_layers=$2
  local mib_per_layer=$(( (size_gb * 1024) / (num_layers > 0 ? num_layers : 1) ))
  (( mib_per_layer < 1 )) && mib_per_layer=1
  local layers=$(( VRAM_USABLE_MIB / mib_per_layer ))
  (( layers > num_layers )) && layers=$num_layers
  (( layers < 0 )) && layers=0
  echo "$layers"
}

print_hw_summary() {
  echo -e "  ${BCYAN}╭─────────────────────────  HARDWARE  ────────────────────────╮${NC}"
  printf   "  ${BCYAN}│${NC}  %-14s  %-41s${BCYAN}│${NC}\n" "CPU"      "${CPU_NAME:0:41}"
  printf   "  ${BCYAN}│${NC}  %-14s  %-41s${BCYAN}│${NC}\n" "RAM"      "${TOTAL_RAM_GB} GB"
  printf   "  ${BCYAN}│${NC}  %-14s  %-41s${BCYAN}│${NC}\n" "GPU"      "${GPU_NAME:-None}  (${GPU_VRAM_GB} GB VRAM)"
  printf   "  ${BCYAN}│${NC}  %-14s  %-41s${BCYAN}│${NC}\n" "Platform" "$( (( IS_WSL2 )) && echo WSL2 || echo Linux )"
  printf   "  ${BCYAN}│${NC}  %-14s  %-41s${BCYAN}│${NC}\n" "Free disk" "${FREE_DISK_GB} GB"
  (( IS_WSL2 && WSL_CUDA_FIXED )) && \
    printf "  ${BCYAN}│${NC}  %-14s  %-41s${BCYAN}│${NC}\n" "CUDA stub" "/usr/lib/wsl/lib  (pinned first)"
  echo -e "  ${BCYAN}╰────────────────────────────────────────────────────────────╯${NC}"
}
