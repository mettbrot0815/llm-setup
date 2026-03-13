#!/usr/bin/env bash
# steps/01-preflight.sh — sudo, OS, disk, internet checks

step "Preflight checks"

# ── sudo ──────────────────────────────────────────────────────────────────────
command -v sudo &>/dev/null || error "sudo is required: apt-get install sudo"
sudo -v            || error "sudo authentication failed"

# ── OS ────────────────────────────────────────────────────────────────────────
if [[ -f /etc/os-release ]]; then
  source /etc/os-release
  DISTRO_ID="${ID:-unknown}"
  DISTRO_VERSION="${VERSION_ID:-?}"
  DISTRO_CODENAME="${VERSION_CODENAME:-}"
else
  DISTRO_ID="unknown"; DISTRO_VERSION="?"; DISTRO_CODENAME=""
fi
info "OS: $DISTRO_ID $DISTRO_VERSION${DISTRO_CODENAME:+ ($DISTRO_CODENAME)}"

if [[ "$DISTRO_ID" != "ubuntu" && "$DISTRO_ID" != "debian" ]]; then
  warn "Detected: $DISTRO_ID — this script targets Ubuntu/Debian. Proceeding anyway."
fi

# ── Architecture ──────────────────────────────────────────────────────────────
ARCH=$(uname -m)
[[ "$ARCH" == "x86_64" ]] || warn "Architecture: $ARCH — only x86_64 is fully tested"
info "Arch: $ARCH"

# ── Disk space ────────────────────────────────────────────────────────────────
if (( FREE_DISK_GB < 20 )); then
  warn "Only ${FREE_DISK_GB} GB free — need ~20 GB for models + stack"
  ask_yes_no "Continue anyway?" || error "Free up disk space and re-run"
else
  ok "Disk: ${FREE_DISK_GB} GB free"
fi

# ── Internet ──────────────────────────────────────────────────────────────────
HAVE_INTERNET=0
if curl -sf --max-time 5 https://1.1.1.1 &>/dev/null \
   || curl -sf --max-time 5 https://8.8.8.8 &>/dev/null; then
  HAVE_INTERNET=1
  ok "Internet connectivity ✔"
else
  warn "No internet — will skip any steps that require downloads"
fi

# ── Required base tools ───────────────────────────────────────────────────────
# Install everything in ONE apt call — multiple sequential calls race for the
# dpkg lock, especially on fresh WSL where unattended-upgrades may start up.
info "Updating apt package index…"
apt_wait apt-get update -qq >> "$LOG_FILE" 2>&1 || warn "apt update had errors (non-fatal)"

_to_install=()
for _cmd_pkg in \
    "curl:curl" \
    "wget:wget" \
    "git:git" \
    "gcc:build-essential" \
    "zstd:zstd" \
    "lsof:lsof" \
    "python3:python3" \
    "python3:python3-pip" \
    "python3:python3-venv"; do
  _cmd="${_cmd_pkg%%:*}"
  _pkg="${_cmd_pkg##*:}"
  command -v "$_cmd" &>/dev/null \
    || dpkg -l "$_pkg" 2>/dev/null | grep -q '^ii' \
    || _to_install+=("$_pkg")
done
# Always ensure python3-venv variants — needed for venv creation on Ubuntu 24.04
_to_install+=("python3.12-venv" "python3.12-dev")

if (( ${#_to_install[@]} > 0 )); then
  run_with_progress "apt: ${_to_install[*]}" "$LOG_FILE" \
    sudo apt-get install -y -q "${_to_install[@]}"
  (( $? == 0 )) && : || warn "Some packages failed to install — may be fine if already present"
fi
ok "Base tools ready"

# ── uv (Python package manager — needed for uvx) ──────────────────────────────
if ! command -v uv &>/dev/null && [[ ! -x "$HOME/.local/bin/uv" ]]; then
  if (( HAVE_INTERNET )); then
    info "Installing uv…"
    curl -fsSL https://astral.sh/uv/install.sh | sh >> "$LOG_FILE" 2>&1 \
      && ok "uv installed" \
      || warn "uv install failed (non-fatal)"
    # Put uv on PATH for rest of this session
    export PATH="$HOME/.local/bin:$PATH"
  else
    warn "No internet — uv skipped"
  fi
else
  ok "uv already installed"
fi

# The uv installer adds 'source ~/.local/bin/env' to .bashrc — this is a binary,
# not a shell script, and causes "-bash: cannot execute binary file" on every login.
# Remove it. uv/uvx work fine without it since we export PATH directly.
if grep -q '\.local/bin/env' "$HOME/.bashrc" 2>/dev/null; then
  sed -i '/\.local\/bin\/env/d' "$HOME/.bashrc"
  info "Removed uv's binary 'source' line from ~/.bashrc (caused login errors)"
fi

# ── Background model catalog refresh ──────────────────────────────────────────
# Refresh the Ollama model cache silently in the background so step 06 and
# step 11 see an up-to-date list without adding any wall-clock time.
if (( HAVE_INTERNET )); then
  _cache="$CONFIG_DIR/models-cache.sh"
  _cache_age=99999
  [[ -f "$_cache" ]] && _cache_age=$(( $(date +%s) - $(date -r "$_cache" +%s 2>/dev/null || echo 0) ))
  if (( _cache_age > 86400 )); then  # older than 1 day → refresh
    (
      _json=$(curl -sf --connect-timeout 5 --max-time 15 \
        -H "Accept: application/json" \
        "https://ollama.com/api/models?sort=featured&p=1&per_page=100" 2>/dev/null || true)
      [[ -z "$_json" ]] && exit 0
      python3 - "$_json" << 'PYEOF' > "$_cache.tmp" 2>/dev/null && mv "$_cache.tmp" "$_cache"
import sys, json, re

data = json.loads(sys.argv[1])
models = data if isinstance(data, list) else data.get("models", data.get("data", []))

def vram_for(p):
    if p<=2: return "CPU"
    if p<=4: return "3"
    if p<=8: return "5"
    if p<=12: return "8"
    if p<=15: return "9"
    if p<=23: return "13"
    if p<=30: return "16"
    if p<=35: return "20"
    if p<=72: return "40"
    return "80"

def layers_for(p):
    if p<=1: return "28"
    if p<=8: return "36"
    if p<=12: return "46"
    if p<=15: return "48"
    if p<=23: return "48"
    if p<=35: return "64"
    if p<=72: return "80"
    return "80"

def size_gb(p): return str(max(1, round(p*0.6))) if p>0 else "1"
def quant(p): return "Q8" if p<=2 else "Q4"
def caps(n):
    c=["tools"]
    if any(x in n.lower() for x in ["r1","think","reason"]): c.append("think")
    elif "qwen3" in n.lower(): c.append("think")
    return ",".join(c)

seen=set(); rows=[]
for m in models:
    name=m.get("name","") or m.get("model_name","")
    if not name or name in seen: continue
    seen.add(name)
    p=0
    pm=re.search(r"[:\-_](\d+(?:\.\d+)?)b",name.lower())
    if pm:
        try: p=float(pm.group(1))
        except: pass
    tag=name if ":" in name else name+":latest"
    display=re.sub(r"[:\-_]"," ",name).title().strip()
    rows.append(f'"{tag:<23} | {display:<24} | {quant(p):<3} | {vram_for(p):<3} | {size_gb(p):<2} | {layers_for(p):<3} | {caps(name)}"')

if rows:
    print("# llm-setup model cache — auto-generated")
    from datetime import datetime, timezone
    print(f"# Generated: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}")
    print("_MODELS=(")
    for r in rows[:60]: print(r)
    print(")")
PYEOF
    ) >> "$LOG_FILE" 2>&1 &
    disown $! 2>/dev/null || true
    info "Model catalog refresh started in background…"
  fi
fi
