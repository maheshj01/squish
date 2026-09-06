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

# Copy the project (entry + lib + completion) to $INSTALL_DIR, symlink it onto
# PATH, and drop the zsh completion into place. Idempotent — safe to re-run.
_sync_code() {
  mkdir -p "$INSTALL_DIR/lib"
  cp "$SQUISH_ROOT/$APP" "$INSTALL_DIR/$APP"
  cp "$SQUISH_ROOT"/lib/*.sh "$INSTALL_DIR/lib/"
  chmod +x "$INSTALL_DIR/$APP"
  mkdir -p "$(dirname "$BIN_LINK")"
  ln -sf "$INSTALL_DIR/$APP" "$BIN_LINK"
  if [[ -f "$SQUISH_ROOT/completions/_$APP" ]]; then
    mkdir -p "$COMPLETION_DIR"
    cp "$SQUISH_ROOT/completions/_$APP" "$COMPLETION_DIR/_$APP"
  fi
}

# start = get everything in place (first run) and begin watching.
cmd_start() {
  load_config
  _sync_code
  mkdir -p "$WATCH_DIR" "$COMPRESSED_DIR"
  write_plist; agent_unload; agent_load
  is_loaded && ok "watching $WATCH_DIR" || warn "agent did not load — check: $LAUNCHD_LOG"
  case ":$PATH:" in *":$(dirname "$BIN_LINK"):"*) ;;
    *) warn "note: $(dirname "$BIN_LINK") is not on PATH — add:  export PATH=\"\$HOME/bin:\$PATH\"  to ~/.zshrc";; esac
  case ":${FPATH:-}:" in *":$COMPLETION_DIR:"*) ;;
    *) [[ -f "$COMPLETION_DIR/_$APP" ]] && info "${c_dim}tab-completion: add  fpath=($COMPLETION_DIR \$fpath); autoload -Uz compinit; compinit  to ~/.zshrc${c_reset}";; esac
}

# stop = stop watching (agent unloaded, plist removed). Code + config stay.
cmd_stop() {
  agent_unload
  rm -f "$PLIST"
  ok "stopped watching."
}

cmd_status() {
  load_config
  local watching; is_loaded && watching="${c_grn}yes${c_reset}" || watching="${c_yel}no — run: $APP start${c_reset}"
  printf '%swatching%s       %s\n' "$c_bold" "$c_reset" "$watching"
  printf '%swatch folder%s   %s\n' "$c_bold" "$c_reset" "$WATCH_DIR"
  printf '%soutput folder%s  %s\n' "$c_bold" "$c_reset" "$COMPRESSED_DIR"
  printf '%sCRF%s            %s\n' "$c_bold" "$c_reset" "$CRF"
  printf '%sPRESET%s         %s\n' "$c_bold" "$c_reset" "$PRESET"
  printf '%sAUDIO_BITRATE%s  %s\n' "$c_bold" "$c_reset" "$AUDIO_BITRATE"
  printf '%sNOTIFY%s         %s\n' "$c_bold" "$c_reset" "$NOTIFY"
  printf '%sconfig%s         %s\n' "$c_bold" "$c_reset" "$([[ -f "$CONFIG_FILE" ]] && echo "$CONFIG_FILE" || echo "(defaults)")"
  printf '%srun log%s        %s\n' "$c_bold" "$c_reset" "$RUN_LOG"
}

cmd_logs() {
  [[ -f "$RUN_LOG" ]] || die "no log yet at $RUN_LOG"
  if [[ "${1:-}" == "-f" ]]; then tail -f "$RUN_LOG"; else tail -n "${1:-40}" "$RUN_LOG"; fi
}
