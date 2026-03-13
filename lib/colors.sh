#!/usr/bin/env bash
# lib/colors.sh — standalone colors for tool scripts (no ui.sh dependency)
if [[ -t 1 ]]; then
  RED=$'\033[0;31m'  GREEN=$'\033[0;32m'  YELLOW=$'\033[1;33m'
  CYAN=$'\033[0;36m' BOLD=$'\033[1m'      DIM=$'\033[2m'        NC=$'\033[0m'
  BGREEN=$'\033[1;32m' BYELLOW=$'\033[1;33m' BCYAN=$'\033[1;36m' BRED=$'\033[1;31m'
else
  RED='' GREEN='' YELLOW='' CYAN='' BOLD='' DIM='' NC=''
  BGREEN='' BYELLOW='' BCYAN='' BRED=''
fi
