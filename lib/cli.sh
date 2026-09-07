#!/bin/bash
# cli.sh — help text and the top-level command dispatcher.
#
# Design: read state through `status`, change it through `config`. Keep the
# surface small. Adding a command = a function in the right module + one line
# here and in cmd_help() (and a line in completions/_squish for tab-completion).

cmd_version() { say "$APP $VERSION"; }

cmd_help() {
  cat >&2 <<EOF
${c_bold}$APP${c_reset} $VERSION — watch a folder and auto-compress videos with ffmpeg.

${c_bold}usage:${c_reset} $APP <command>

  ${c_bold}status${c_reset}              show active status and configuration
  ${c_bold}compress${c_reset} <file>     compress one file now [--destination DIR]
  ${c_bold}convert${c_reset} <file>      convert one file to a gif [--destination DIR]
  ${c_bold}start${c_reset}               start watching (sets everything up on first run)
  ${c_bold}stop${c_reset}                stop watching
  ${c_bold}config set${c_reset} K V      change a setting
  ${c_bold}config reset${c_reset}        restore defaults
  ${c_bold}clean${c_reset} [clips|compressed]  empty the folders (asks y/N; both if unspecified)
  ${c_bold}logs${c_reset} [N|-f]         show the run log (last N lines, or follow)
  ${c_bold}help${c_reset}                show this
  ${c_bold}version${c_reset}             print version

${c_bold}config keys${c_reset}  ${KEYS[*]}
             CRF 0–51 (lower=better) · PRESET ultrafast…veryslow · NOTIFY 0/1
EOF
}

cli_main() {
  local cmd="${1:-help}"; shift || true
  case "$cmd" in
    status)               cmd_status "$@" ;;
    compress)             cmd_compress "$@" ;;
    convert)              cmd_convert "$@" ;;
    start)                cmd_start "$@" ;;
    stop)                 cmd_stop "$@" ;;
    config)               cmd_config "$@" ;;
    clean)                cmd_clean "$@" ;;
    logs)                 cmd_logs "$@" ;;
    run)                  cmd_run "$@" ;;          # internal: launchd calls this
    version|-v|--version) cmd_version ;;
    help|-h|--help)       cmd_help ;;
    *) info "unknown command: $cmd"; cmd_help; exit 1 ;;
  esac
}
