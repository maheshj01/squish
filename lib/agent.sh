#!/bin/bash
# agent.sh — the launchd side: generate the plist, (un)load it, install/uninstall.
#
# The watch folder is baked into the plist's WatchPaths, so any change to
# WATCH_DIR must regenerate + reload the agent — reload_if_installed() does that.

is_installed() { [[ -f "$PLIST" ]]; }
is_loaded()    { launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; }

# Generate the plist from the current config. launchd calls the *installed*
# entry point ($INSTALL_DIR/$APP) so it keeps working if the repo moves.
write_plist() {
  load_config
  mkdir -p "$(dirname "$PLIST")"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/$APP</string>
        <string>run</string>
    </array>
    <key>WatchPaths</key>
    <array>
        <string>$WATCH_DIR</string>
    </array>
    <key>RunAtLoad</key>
    <false/>
    <key>ProcessType</key>
    <string>Background</string>
    <key>Nice</key>
    <integer>10</integer>
    <key>StandardOutPath</key>
    <string>$LAUNCHD_LOG</string>
    <key>StandardErrorPath</key>
    <string>$LAUNCHD_LOG</string>
</dict>
</plist>
EOF
}

agent_load()   { launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || true; }
agent_unload() { launchctl bootout   "gui/$(id -u)/$LABEL" 2>/dev/null || true; }

reload_if_installed() {
  is_installed || return 0
  info "${c_dim}reloading agent ($1)…${c_reset}"
  write_plist; agent_unload; agent_load
}

# Copy the whole project (entry + lib) to $INSTALL_DIR and symlink it onto PATH.
_sync_code() {
  mkdir -p "$INSTALL_DIR/lib"
  cp "$SQUISH_ROOT/$APP" "$INSTALL_DIR/$APP"
  cp "$SQUISH_ROOT"/lib/*.sh "$INSTALL_DIR/lib/"
  chmod +x "$INSTALL_DIR/$APP"
  mkdir -p "$(dirname "$BIN_LINK")"
  ln -sf "$INSTALL_DIR/$APP" "$BIN_LINK"
}

cmd_install() {
  load_config
  _sync_code
  mkdir -p "$WATCH_DIR"
  write_plist; agent_unload; agent_load
  ok "installed."
  info "  cli:   $BIN_LINK -> $INSTALL_DIR/$APP"
  info "  agent: $PLIST"
  info "  watch: $WATCH_DIR"
  is_loaded && ok "agent is loaded and watching." || warn "agent did not load — check: $LAUNCHD_LOG"
  case ":$PATH:" in *":$(dirname "$BIN_LINK"):"*) ;; *) warn "note: $(dirname "$BIN_LINK") is not on your PATH — add it to ~/.zshrc";; esac
}

cmd_uninstall() {
  agent_unload
  rm -f "$PLIST"
  ok "agent unloaded and plist removed."
  info "  (code at $INSTALL_DIR, symlink $BIN_LINK, and config were left in place)"
}

cmd_status() {
  load_config
  printf '%swatch folder%s   %s\n' "$c_bold" "$c_reset" "$WATCH_DIR"
  printf '%soutput folder%s  %s\n' "$c_bold" "$c_reset" "$COMPRESSED_DIR"
  printf '%sconfig file%s    %s\n' "$c_bold" "$c_reset" "$([[ -f "$CONFIG_FILE" ]] && echo "$CONFIG_FILE" || echo "(defaults)")"
  printf '%srun log%s        %s\n' "$c_bold" "$c_reset" "$RUN_LOG"
  printf '%sinstalled%s      %s\n' "$c_bold" "$c_reset" "$([[ -x "$INSTALL_DIR/$APP" ]] && echo "$INSTALL_DIR/$APP" || echo "no")"
  printf '%splist%s          %s\n' "$c_bold" "$c_reset" "$(is_installed && echo "$PLIST" || echo "not installed")"
  printf '%sagent loaded%s   %s\n' "$c_bold" "$c_reset" "$(is_loaded && echo yes || echo no)"
}

cmd_start()   { is_installed || die "not installed — run: $APP install"; agent_load;   ok "agent loaded."; }
cmd_stop()    { agent_unload; ok "agent unloaded."; }
cmd_restart() { is_installed || die "not installed — run: $APP install"; agent_unload; agent_load; ok "agent reloaded."; }

cmd_logs() {
  [[ -f "$RUN_LOG" ]] || die "no log yet at $RUN_LOG"
  if [[ "${1:-}" == "-f" ]]; then tail -f "$RUN_LOG"; else tail -n "${1:-40}" "$RUN_LOG"; fi
}
