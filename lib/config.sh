#!/bin/bash
# config.sh — load, validate, and persist compression settings.
#
# Config is a flat KEY=VALUE file at $CONFIG_FILE. Values are validated on the
# way in (a bad value is rejected, never written) and read fresh on every run.

# Populate WATCH_DIR/CRF/... from defaults, then overlay the config file.
load_config() {
  WATCH_DIR="$DEFAULT_WATCH_DIR"
  COMPRESSED_DIR="$DEFAULT_COMPRESSED_DIR"
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
      WATCH_DIR|COMPRESSED_DIR|CRF|PRESET|AUDIO_BITRATE|NOTIFY) printf -v "$key" '%s' "$val" ;;
    esac
  done < "$CONFIG_FILE"
}

# Write current in-memory values back as a normalised config file.
save_config() {
  mkdir -p "$CONFIG_DIR"
  {
    printf '# %s config — edit with `%s config set KEY VALUE`\n' "$APP" "$APP"
    printf 'WATCH_DIR=%s\n'      "$WATCH_DIR"
    printf 'COMPRESSED_DIR=%s\n' "$COMPRESSED_DIR"
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
    WATCH_DIR|COMPRESSED_DIR)
      [[ -n "$val" ]] || die "$key cannot be empty"
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
# The write side. Reading is `status`, so config only writes: `set` and `reset`.
cmd_config() {
  load_config
  local sub="${1:-}"; shift || true
  case "$sub" in
    set)
      local k="${1:?usage: $APP config set KEY VALUE}" raw="${2:?usage: $APP config set KEY VALUE}"
      case " ${KEYS[*]} " in *" $k "*) ;; *) die "unknown key: $k (valid: ${KEYS[*]})" ;; esac
      local norm
      norm="$(validate "$k" "$raw")" || exit 1   # validate() dies in the subshell; propagate it
      printf -v "$k" '%s' "$norm"
      save_config
      ok "set $k=$norm"
      case "$k" in
        WATCH_DIR)                      # baked into the plist -> reload the agent
          mkdir -p "$WATCH_DIR"
          reload_if_installed "watch folder changed" ;;
        COMPRESSED_DIR) mkdir -p "$COMPRESSED_DIR" ;;   # not in the plist, no reload
      esac
      ;;
    reset)
      WATCH_DIR="$DEFAULT_WATCH_DIR"; COMPRESSED_DIR="$DEFAULT_COMPRESSED_DIR"
      CRF="$DEFAULT_CRF"; PRESET="$DEFAULT_PRESET"
      AUDIO_BITRATE="$DEFAULT_AUDIO_BITRATE"; NOTIFY="$DEFAULT_NOTIFY"
      save_config
      ok "config reset to defaults (run '$APP status' to see them)"
      reload_if_installed "config reset"
      ;;
    ""|*) die "usage: $APP config set KEY VALUE   |   $APP config reset" ;;
  esac
}
