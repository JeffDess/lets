#!/usr/bin/env bash

# NOTE: Formatting constants and functions are injected by mkTask
# shellcheck disable=SC2154

echo "Constants:"
# editorconfig-checker-disable
echo "  ${BOLD}bold${RESET} ${DIM}dim${RESET} ${ITALIC}italic${RESET} ${UNDERLINE}underline${RESET}"
echo "  ${RED}red${RESET} ${GREEN}green${RESET} ${YELLOW}yellow${RESET} ${BLUE}blue${RESET}"
# editorconfig-checker-enable

echo "Single-style functions:"
blue "  blue text"
bold "  bold text"
underline "  underlined text"

echo "Merged style+color functions:"
bold_blue "  bold blue text"
underline_red "  underlined red text"
dim_green "  dim green text"

echo "Log helpers:"
error "something failed"
warn "watch out"
info "for your information"
debug "internal detail"
trace "very fine detail"
