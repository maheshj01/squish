#!/bin/bash
# config.sh — load, validate, and persist compression settings.
#
# Config is a flat KEY=VALUE file at $CONFIG_FILE. Values are validated on the
# way in (a bad value is rejected, never written) and read fresh on every run.

# Populate WATCH_DIR/CRF/... from defaults, then overlay the config file.
load_config() {
  WATCH_DIR="$DEFAULT_WATCH_DIR"
  CRF="$DEFAULT_CRF"
  PRESET="$DEFAULT_PRESET"
  AUDIO_BITRATE="$DEFAULT_AUDIO_BITRATE"
  NOTIFY="$DEFAULT_NOTIFY"

  [[ -f "$CONFIG_FILE" ]] || return 0
  local line key val
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"; val="${line#*=}"
    key="${key//[[:space:]]/}"
    case "$key" in
      WATCH_DIR|CRF|PRESET|AUDIO_BITRATE|NOTIFY) printf -v "$key" '%s' "$val" ;;
    esac
  done < "$CONFIG_FILE"
}

# Write current in-memory values back as a normalised config file.
save_config() {
  mkdir -p "$CONFIG_DIR"
  {
    printf '# %s config — edit with `%s config set KEY VALUE`\n' "$APP" "$APP"
    printf 'WATCH_DIR=%s\n'     "$WATCH_DIR"
    printf 'CRF=%s\n'           "$CRF"
    printf 'PRESET=%s\n'        "$PRESET"
    printf 'AUDIO_BITRATE=%s\n' "$AUDIO_BITRATE"
    printf 'NOTIFY=%s\n'        "$NOTIFY"
  } > "$CONFIG_FILE"
}

# Validate one key/value. Echoes a normalised value on success; dies on bad input.
# NOTE: callers run this in $(...) — the die() then exits only the subshell, so
# callers MUST check its exit status (`norm="$(validate ...)" || exit 1`).
validate() {
  local key="$1" val="$2"
  case "$key" in
    WATCH_DIR)
      [[ -n "$val" ]] || die "WATCH_DIR cannot be empty"
      case "$val" in "~"/*) val="$HOME/${val#\~/}" ;; "~") val="$HOME" ;; esac
      printf '%s' "$val" ;;
    CRF)
      [[ "$val" =~ ^[0-9]+$ ]] && (( val >= 0 && val <= 51 )) \
        || die "CRF must be an integer 0–51 (lower = better quality/bigger file)"
      printf '%s' "$val" ;;
    PRESET)
      case "$val" in
        ultrafast|superfast|veryfast|faster|fast|medium|slow|slower|veryslow|placebo)
          printf '%s' "$val" ;;
        *) die "PRESET must be one of: ultrafast superfast veryfast faster fast medium slow slower veryslow placebo" ;;
      esac ;;
    AUDIO_BITRATE)
      [[ "$val" =~ ^[0-9]+k?$ ]] || die "AUDIO_BITRATE looks like '128k' or '96k'"
      printf '%s' "$val" ;;
    NOTIFY)
      case "$val" in
        true|on|yes) printf '1' ;;
        false|off|no) printf '0' ;;
        0|1) printf '%s' "$val" ;;
        *) die "NOTIFY must be 0 or 1" ;;
      esac ;;
    *) die "unknown config key: $key (valid: ${KEYS[*]})" ;;
  esac
}

# `config <show|get|set|reset|path>`
cmd_config() {
  load_config
  local sub="${1:-show}"; shift || true
  case "$sub" in
    show|"")
      local src="defaults (no config file yet)"
      [[ -f "$CONFIG_FILE" ]] && src="$CONFIG_FILE"
      info "${c_dim}source: $src${c_reset}"
      local k
      for k in "${KEYS[@]}"; do printf '%s%-14s%s %s\n' "$c_bold" "$k" "$c_reset" "${!k}"; done
      ;;
    get)
      local k="${1:?usage: $APP config get KEY}"
      case " ${KEYS[*]} " in *" $k "*) printf '%s\n' "${!k}" ;; *) die "unknown key: $k" ;; esac
      ;;
    set)
      local k="${1:?usage: $APP config set KEY VALUE}" raw="${2:?usage: $APP config set KEY VALUE}"
      case " ${KEYS[*]} " in *" $k "*) ;; *) die "unknown key: $k (valid: ${KEYS[*]})" ;; esac
      local norm
      norm="$(validate "$k" "$raw")" || exit 1   # validate() dies in the subshell; propagate it
      printf -v "$k" '%s' "$norm"
      save_config
      ok "set $k=$norm"
      if [[ "$k" == WATCH_DIR ]]; then
        mkdir -p "$WATCH_DIR"
        reload_if_installed "watch folder changed"
      fi
      ;;
    reset)
      WATCH_DIR="$DEFAULT_WATCH_DIR"; CRF="$DEFAULT_CRF"; PRESET="$DEFAULT_PRESET"
      AUDIO_BITRATE="$DEFAULT_AUDIO_BITRATE"; NOTIFY="$DEFAULT_NOTIFY"
      save_config
      ok "config reset to defaults"
      cmd_config show
      reload_if_installed "config reset"
      ;;
    path) say "$CONFIG_FILE" ;;
    *) die "unknown config subcommand: $sub (show|get|set|reset|path)" ;;
  esac
}

# `folder [PATH]` — friendly alias for reading/setting WATCH_DIR.
cmd_folder() {
  load_config
  local new="${1:-}"
  [[ -n "$new" ]] || { info "current watch folder: $WATCH_DIR"; return 0; }
  cmd_config set WATCH_DIR "$new"
}
