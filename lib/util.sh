#!/usr/bin/env bash
# lib/util.sh — retry, apt_wait, ollama helpers

retry() {
  local n=$1 delay=$2; shift 2
  local attempt=1
  while true; do
    "$@" && return 0
    (( attempt >= n )) && { warn "Failed after $n attempts: $*"; return 1; }
    warn "Attempt $attempt/$n failed — retrying in ${delay}s…"
    sleep "$delay"
    attempt=$(( attempt + 1 ))
  done
}

apt_wait() {
  # Wait for dpkg/apt locks to be free, then run apt with sudo.
  # Uses lsof to check actual lock holders (more reliable than flock --nonblock
  # which can race when multiple apt calls follow each other quickly).
  local _waited=0 _lock_files=(
    /var/lib/dpkg/lock-frontend
    /var/lib/dpkg/lock
    /var/cache/apt/archives/lock
  )
  while true; do
    local _busy=0
    for _lf in "${_lock_files[@]}"; do
      if lsof "$_lf" &>/dev/null 2>&1; then _busy=1; break; fi
    done
    (( _busy == 0 )) && break
    (( _waited == 0 )) && info "Waiting for dpkg lock to be released…"
    (( _waited >= 180 )) && { warn "dpkg lock held >3 min — proceeding anyway"; break; }
    sleep 3; _waited=$(( _waited + 3 ))
  done
  # Extra grace period — dpkg sometimes holds the lock file open briefly after release
  (( _waited > 0 )) && sleep 2
  sudo DEBIAN_FRONTEND=noninteractive "$@"
}

ollama_has_model() {
  ollama show "$1" &>/dev/null
}

is_wsl2() { (( IS_WSL2 )); }
