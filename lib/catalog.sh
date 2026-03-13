#!/usr/bin/env bash
# lib/catalog.sh — model table, auto-select, picker, layer calc

declare -A _M  # active model — fields: tag name quant vram size_gb layers caps gpu_layers cpu_layers

# ── Model catalog ─────────────────────────────────────────────────────────────
# llm-models-refresh fetches a live list from ollama.com and writes to:
#   ~/.config/llm-setup/models-cache.sh
# If that cache is <= 7 days old, it overrides the built-in list below.
# Run "llm-models-refresh" at any time to pull the latest models.

# tag | name | quant | vram_gb (CPU=no GPU needed) | size_gb | layers | caps
_MODELS=(
"qwen3:0.6b             | Qwen3 0.6B               | Q8  | CPU | 1  | 28  | tools,think"
"qwen3:1.7b             | Qwen3 1.7B               | Q8  | CPU | 2  | 28  | tools,think"
"qwen3:4b               | Qwen3 4B                 | Q4  | 3   | 3  | 36  | tools,think"
"qwen2.5:3b             | Qwen2.5 3B               | Q6  | 2   | 2  | 36  | tools"
"deepseek-r1:7b         | DeepSeek-R1 7B           | Q4  | 5   | 5  | 28  | think"
"qwen3:8b               | Qwen3 8B                 | Q4  | 5   | 5  | 36  | tools,think"
"gemma3:9b              | Gemma 3 9B               | Q4  | 5   | 6  | 42  | tools"
"gemma3:12b             | Gemma 3 12B              | Q4  | 8   | 8  | 46  | tools"
"mistral-nemo:latest    | Mistral Nemo 12B         | Q4  | 7   | 7  | 40  | tools"
"qwen3:14b              | Qwen3 14B                | Q4  | 9   | 9  | 40  | tools,think"
"deepseek-r1:14b        | DeepSeek-R1 14B          | Q4  | 9   | 9  | 40  | think"
"qwen2.5:14b            | Qwen2.5 14B              | Q4  | 9   | 9  | 48  | tools"
"mistral-small:22b      | Mistral Small 22B        | Q4  | 13  | 13 | 48  | tools"
"gemma3:27b             | Gemma 3 27B              | Q4  | 16  | 16 | 62  | tools"
"qwen3:30b-a3b          | Qwen3 30B-A3B (MoE)      | Q4  | 16  | 18 | 48  | tools,think"
"qwen3:32b              | Qwen3 32B                | Q4  | 19  | 19 | 64  | tools,think"
"deepseek-r1:32b        | DeepSeek-R1 32B          | Q4  | 19  | 19 | 64  | think"
"qwen2.5:32b            | Qwen2.5 32B              | Q4  | 19  | 19 | 64  | tools"
"llama3.3:70b           | Llama 3.3 70B            | Q4  | 40  | 40 | 80  | tools"
)

# Load cached catalog if fresh (overrides built-in list above)
_MODELS_CACHE="${CONF_DIR:-$HOME/.config/llm-setup}/models-cache.sh"
if [[ -f "$_MODELS_CACHE" ]]; then
  _cache_age=$(( $(date +%s) - $(date -r "$_MODELS_CACHE" +%s 2>/dev/null || echo 0) ))
  if (( _cache_age < 604800 )); then  # 7 days
    source "$_MODELS_CACHE" 2>/dev/null || true
  fi
fi
unset _MODELS_CACHE _cache_age

_parse_row() {
  IFS='|' read -r _t _n _q _v _s _l _c <<< "$1"
  _M[tag]=$(echo "$_t" | xargs)
  _M[name]=$(echo "$_n" | xargs)
  _M[quant]=$(echo "$_q" | xargs)
  _M[vram]=$(echo "$_v" | xargs)
  _M[size_gb]=$(echo "$_s" | xargs)
  _M[layers]=$(echo "$_l" | xargs)
  _M[caps]=$(echo "$_c" | xargs)
}

_calc_layers() {
  if (( HAS_GPU )); then
    _M[gpu_layers]=$(gpu_layers_for "${_M[size_gb]}" "${_M[layers]}")
    _M[cpu_layers]=$(( _M[layers] - _M[gpu_layers] ))
    (( _M[cpu_layers] < 0 )) && _M[cpu_layers]=0
  else
    _M[gpu_layers]=0
    _M[cpu_layers]="${_M[layers]}"
  fi
}

_caps_label() {
  local caps="$1" out=""
  [[ "$caps" == *tools*  ]] && out+="[TOOLS] "
  [[ "$caps" == *think*  ]] && out+="[THINK] "
  echo "${out% }"
}

auto_select_model() {
  local best=0 i vram
  for (( i=0; i<${#_MODELS[@]}; i++ )); do
    _parse_row "${_MODELS[$i]}"
    vram="${_M[vram]}"
    if [[ "$vram" == "CPU" ]] || \
       { [[ "$vram" =~ ^[0-9]+$ ]] && (( HAS_GPU && GPU_VRAM_GB >= vram )); }; then
      best=$i
    fi
  done
  _parse_row "${_MODELS[$best]}"
  _calc_layers
}

pick_model() {
  echo ""
  echo -e "  ${DIM}┌────┬───────────────────────────────┬──────┬───────┬──────────────────┐${NC}"
  printf  "  │ %2s │ %-31s │ %-4s │ %-5s │ %-16s │\n" "#" "Model" "Q" "VRAM" "Caps"
  echo -e "  ${DIM}├────┼───────────────────────────────┼──────┼───────┼──────────────────┤${NC}"

  local i color vram_disp
  for (( i=0; i<${#_MODELS[@]}; i++ )); do
    _parse_row "${_MODELS[$i]}"
    vram_disp="${_M[vram]}"; [[ "$vram_disp" != "CPU" ]] && vram_disp="${vram_disp}GB"
    color=""
    if [[ "${_M[vram]}" == "CPU" ]] || \
       { [[ "${_M[vram]}" =~ ^[0-9]+$ ]] && (( HAS_GPU && GPU_VRAM_GB >= _M[vram] )); }; then
      color="${GREEN}"
    fi
    printf "  │${color} %2d${NC} │ %-31s │ %-4s │ %-5s │ %-16s │\n" \
      "$(( i+1 ))" "${_M[name]:0:31}" "${_M[quant]}" "$vram_disp" "$(_caps_label "${_M[caps]}")"
  done
  echo -e "  ${DIM}└────┴───────────────────────────────┴──────┴───────┴──────────────────┘${NC}"
  echo ""
  echo -e "  ${DIM}Green = fits your hardware (${GPU_VRAM_GB} GB VRAM / ${TOTAL_RAM_GB} GB RAM)${NC}"
  echo ""

  local choice
  read -r -p "  Choice [1-${#_MODELS[@]}]: " choice
  # Strip escape sequences (arrow keys, function keys send ESC+[...)
  choice=$(echo "$choice" | tr -dc '0-9')
  if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#_MODELS[@]} )); then
    _parse_row "${_MODELS[$(( choice-1 ))]}"
    _calc_layers
    ok "Selected: ${_M[name]}"
  else
    warn "Invalid choice — keeping auto-selected model"
  fi
}

print_model_card() {
  echo ""
  echo -e "  ${BCYAN}╭─────────────────────────  MODEL  ───────────────────────────╮${NC}"
  printf   "  ${BCYAN}│${NC}  %-14s  %-41s${BCYAN}│${NC}\n" "Model"      "${_M[name]:0:41}"
  printf   "  ${BCYAN}│${NC}  %-14s  %-41s${BCYAN}│${NC}\n" "Ollama tag" "${_M[tag]:0:41}"
  printf   "  ${BCYAN}│${NC}  %-14s  %-41s${BCYAN}│${NC}\n" "Size"       "${_M[size_gb]} GB  (${_M[quant]})"
  printf   "  ${BCYAN}│${NC}  %-14s  %-41s${BCYAN}│${NC}\n" "GPU layers" "${_M[gpu_layers]} / ${_M[layers]}"
  printf   "  ${BCYAN}│${NC}  %-14s  %-41s${BCYAN}│${NC}\n" "Threads"    "$HW_THREADS"
  printf   "  ${BCYAN}│${NC}  %-14s  %-41s${BCYAN}│${NC}\n" "Batch"      "$BATCH"
  echo -e  "  ${BCYAN}╰────────────────────────────────────────────────────────────╯${NC}"
}

save_model_config() {
  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_DIR/model.conf" << CONF
OLLAMA_TAG="${_M[tag]}"
MODEL_NAME="${_M[name]}"
MODEL_CAPS="${_M[caps]}"
MODEL_SIZE_GB="${_M[size_gb]}"
MODEL_LAYERS="${_M[layers]}"
GPU_LAYERS="${_M[gpu_layers]}"
CPU_LAYERS="${_M[cpu_layers]}"
HW_THREADS="$HW_THREADS"
BATCH="$BATCH"
CONF
}
