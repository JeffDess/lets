#!/usr/bin/env bash
# shellcheck disable=SC2154

WSLU_URL=https://wslutiliti.es/wslu/install.html

open_url() {
  if [[ $(uname -s) == Darwin ]]; then
    open "$1"
  elif [[ -r /proc/version ]] && grep -qi microsoft /proc/version; then
    if command -v wslview &>/dev/null; then
      wslview "$1"
    else
      info "Please install wslview: $WSLU_URL"
      error "Unable to open: $1"
      return 1
    fi
  else
    xdg-open "$1"
  fi
}

info "Opening $url in your browser"
open_url "$url"
