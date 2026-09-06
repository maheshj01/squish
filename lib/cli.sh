#!/bin/bash
# cli.sh — help text and the top-level command dispatcher.
#
# Adding a feature: write its function in the right lib module, then add one
# line to the case in cli_main() and a line to cmd_help().

cmd_version() { say "$APP $VERSION"; }

cmd_help() {
  cat >&2 <<EOF
${c_bold}$APP${c_reset} $VERSION — watch a folder and auto-compress videos with ffmpeg.

${c_bold}usage:${c_reset} $APP <command> [args]

${c_bold}setup${c_reset}
  install                 install to ~/.local/share/$APP, symlink ~/bin/$APP, load agent
  uninstall               unload the agent and remove its plist
  status                  show config + whether the agent is loaded

${c_bold}target folder${c_reset}
  folder                  print the current watch folder
  folder <path>           set the watch folder (updates + reloads the agent)

${c_bold}compression config${c_reset}
  config show             print effective settings and where they come from
  config get <key>        print one value
  config set <key> <val>  update a value  (keys: ${KEYS[*]})
  config reset            restore all defaults
  config path             print the config file path

${c_bold}agent control${c_reset}
  start | stop | restart  load / unload / reload the agent
  logs [N] | logs -f      show last N log lines (default 40), or follow

${c_bold}other${c_reset}
  version                 print version
  run                     the worker launchd calls (safe to run by hand)

${c_bold}keys${c_reset}  WATCH_DIR  CRF(0–51)  PRESET  AUDIO_BITRATE  NOTIFY(0/1)
EOF
}

cli_main() {
  local cmd="${1:-help}"; shift || true
  case "$cmd" in
    run)                 cmd_run "$@" ;;
    config)              cmd_config "$@" ;;
    folder|set-folder)   cmd_folder "$@" ;;
    install)             cmd_install "$@" ;;
    uninstall)           cmd_uninstall "$@" ;;
    status)              cmd_status "$@" ;;
    start)               cmd_start "$@" ;;
    stop)                cmd_stop "$@" ;;
    restart|reload)      cmd_restart "$@" ;;
    logs)                cmd_logs "$@" ;;
    version|-v|--version) cmd_version ;;
    help|-h|--help)      cmd_help ;;
    *) info "unknown command: $cmd"; cmd_help; exit 1 ;;
  esac
}
