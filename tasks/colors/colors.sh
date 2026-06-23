#!/usr/bin/env bash
set -euo pipefail

# NOTE: Formatting constants and functions are injected by mkTask
# shellcheck disable=SC2154

echo "Constants:"
echo "  ${BOLD}bold${RESET} ${DIM}dim${RESET} ${ITALIC}italic${RESET} ${UNDERLINE}underline${RESET}"
echo "  ${RED}red${RESET} ${GREEN}green${RESET} ${YELLOW}yellow${RESET} ${BLUE}blue${RESET}"

echo "Single-style functions:"
blue "  blue text"
bold "  bold text"
underline "  underlined text"

echo "Merged style+color functions:"
bold_blue "  bold blue text"
underline_red "  underlined red text"
dim_green "  dim green text"
