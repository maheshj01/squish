#!/bin/bash
# worker.sh — the compression itself: the launchd watch pass (cmd_run) and the
# synchronous one-shot (cmd_compress). Both share the helpers below so the
# encode settings and behaviour stay identical. Originals are never touched.

# bytes -> human size, e.g. "6.4 MB" / "812 KB"
_human() { awk -v b="$1" 'BEGIN{ if(b>=1048576) printf "%.1f MB",b/1048576; else printf "%.0f KB",b/1024 }'; }

# Is this extension one we compress?
_is_video() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    mov|mp4|m4v|avi|mkv|webm|mpg|mpeg|wmv|flv) return 0 ;;
    *) return 1 ;;
  esac
}

# Echo the ffmpeg path, or return 1. launchd gives us almost no PATH, so we look
# in the usual Homebrew locations before falling back to PATH.
_find_ffmpeg() {
  local c
  for c in /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg "$(command -v ffmpeg 2>/dev/null)"; do
    [[ -x "$c" ]] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

# Encode SRC -> DST (mp4), ffmpeg output to FFLOG, using ffmpeg at FFMPEG.
# Writes to a hidden temp file and moves it into place, so DST is never partial.
# Uses CRF / PRESET / AUDIO_BITRATE from the loaded config.
_encode() {
  local src="$1" dst="$2" fflog="$3" ffmpeg="$4"
  # temp keeps an .mp4 extension AND we pass -f mp4, so ffmpeg always knows the
  # container regardless of the destination's name.
  local tmp; tmp="$(dirname "$dst")/.$(basename "$dst").partial.mp4"
  mkdir -p "$(dirname "$dst")" "$(dirname "$fflog")"
  rm -f "$tmp"
  if "$ffmpeg" -nostdin -y -i "$src" \
       -c:v libx264 -crf "$CRF" -preset "$PRESET" -pix_fmt yuv420p \
       -c:a aac -b:a "$AUDIO_BITRATE" -movflags +faststart \
       -f mp4 "$tmp" > "$fflog" 2>&1
  then mv -f "$tmp" "$dst"; return 0
  else local rc=$?; rm -f "$tmp"; return "$rc"; fi
}

# ==========================================================================
# compress — one file, synchronously. Prints the output path on stdout.
#   squish compress <file> [--destination DIR|FILE.mp4]
# Without --destination it lands in COMPRESSED_DIR/<name>/<name>.mp4, same as
# the watcher. Human messages go to stderr; stdout is just the output path.
# ==========================================================================
cmd_compress() {
  load_config
  local src="" dest=""
  while (( $# )); do
    case "$1" in
      -d|--destination) dest="${2:?--destination needs a path}"; shift 2 ;;
      --destination=*)  dest="${1#*=}"; shift ;;
      -h|--help)        info "usage: $APP compress <file> [--destination DIR]"; return 0 ;;
      -*)               die "unknown option: $1 (usage: $APP compress <file> [--destination DIR])" ;;
      *) [[ -z "$src" ]] && src="$1" || die "one file at a time (usage: $APP compress <file> [--destination DIR])"; shift ;;
    esac
  done

  [[ -n "$src" ]] || die "usage: $APP compress <file> [--destination DIR]"
  [[ -f "$src" ]] || die "no such file: $src"
  local name base ext; name="$(basename "$src")"; base="${name%.*}"; ext="${name##*.}"
  _is_video "$ext" || die "not a video file: .$ext"

  local ffmpeg; ffmpeg="$(_find_ffmpeg)" || die "ffmpeg not found — brew install ffmpeg"

  local dst fflog
  if [[ -n "$dest" ]]; then
    case "$dest" in "~"/*) dest="$HOME/${dest#\~/}" ;; "~") dest="$HOME" ;; esac
    if [[ "$dest" == *.mp4 ]]; then dst="$dest"; else dst="${dest%/}/${base}.mp4"; fi
  else
    dst="$COMPRESSED_DIR/$base/${base}.mp4"     # default: same layout as the watcher
  fi
  fflog="${dst%.mp4}.log"

  local before after pct
  before="$(stat -f%z "$src")"
  info "compressing $name ($(_human "$before")) → $dst"
  if _encode "$src" "$dst" "$fflog" "$ffmpeg"; then
    after="$(stat -f%z "$dst")"; pct=$(( 100 - (after * 100 / before) ))
    ok "done — $(_human "$before") → $(_human "$after")  (${pct}% smaller)"
    say "$dst"                                   # stdout: the output path
  else
    die "ffmpeg failed — see $fflog"
  fi
}

# ==========================================================================
# run — the watch pass launchd triggers (and you can run by hand).
# ==========================================================================
cmd_run() {
  load_config
  local OUT_DIR="$COMPRESSED_DIR"
  local LOG="$RUN_LOG"
  mkdir -p "$OUT_DIR" "$(dirname "$LOG")"

  log() { printf '%s  %s\n' "$(date '+%H:%M:%S')" "$*" >> "$LOG"; }
  notify() {
    (( NOTIFY )) || return 0
    local t=${1//\\/\\\\}; t=${t//\"/\\\"}; local m=${2//\\/\\\\}; m=${m//\"/\\\"}
    /usr/bin/osascript -e "display notification \"$m\" with title \"$t\"" 2>/dev/null || true
  }

  log "──── run started (pid $$, user $(whoami)) ────"

  local FFMPEG; FFMPEG="$(_find_ffmpeg)" || {
    log "FATAL: ffmpeg not found. fix: brew install ffmpeg"
    notify "Compression error" "ffmpeg not found"; return 1
  }
  log "ffmpeg: $FFMPEG   (crf=$CRF preset=$PRESET audio=$AUDIO_BITRATE)"

  [[ -d "$WATCH_DIR" ]] || { log "FATAL: watch dir missing: $WATCH_DIR"; return 1; }
  log "watching: $WATCH_DIR"
  log "contents:"; /bin/ls -la "$WATCH_DIR" 2>&1 | sed 's/^/    /' >> "$LOG"

  # lock: WatchPaths fires repeatedly during a single copy
  if ! mkdir "$LOCK" 2>/dev/null; then
    log "EXIT: another run holds the lock ($LOCK)."; return 0
  fi
  trap 'rmdir "$LOCK" 2>/dev/null' RETURN

  wait_until_stable() {
    local f="$1" last=-1 cur tries=0
    while (( tries < 150 )); do
      cur=$(stat -f%z "$f" 2>/dev/null) || { log "    stat failed (file vanished?)"; return 1; }
      if [[ "$cur" == "$last" && "$cur" != "0" ]]; then
        log "    stable at $cur bytes after $(( tries * 2 ))s"; return 0
      fi
      last="$cur"; sleep 2; (( tries++ ))
    done
    log "    still growing after 5 minutes, giving up"; return 1
  }

  # A file can be dropped WHILE we're mid-encode. We hold the lock the whole
  # time, so after each full scan we rescan and repeat until a pass compresses
  # nothing new — anything that arrived mid-run is caught in this same session.
  shopt -s nullglob nocaseglob
  local processed=0 pass=0 pass_n src name ext base clip_dir dst fflog before after pct
  while :; do
    pass=$(( pass + 1 )); pass_n=0
    for src in "$WATCH_DIR"/*; do
      [[ -f "$src" ]] || continue
      name=$(basename "$src"); ext="${name##*.}"; base="${name%.*}"
      case "$name" in .DS_Store|.*) continue ;; esac
      _is_video "$ext" || { (( pass == 1 )) && log "skip '$name': .$ext is not a video type"; continue; }
      # each video gets its own subfolder: compressed/<base>/{<base>.mp4,<base>.log}
      clip_dir="$OUT_DIR/$base"; dst="$clip_dir/${base}.mp4"; fflog="$clip_dir/${base}.log"
      [[ -e "$dst" ]] && { (( pass == 1 )) && log "skip '$name': already compressed"; continue; }

      log "FOUND: $name"
      wait_until_stable "$src" || { log "skip '$name': file never settled"; continue; }

      before=$(stat -f%z "$src")
      log "encoding '$name' ($(_human "$before")) -> compressed/$base/$(basename "$dst")"
      log "  ffmpeg output: $fflog"
      if _encode "$src" "$dst" "$fflog" "$FFMPEG"; then
        after=$(stat -f%z "$dst"); pct=$(( 100 - (after * 100 / before) ))
        log "OK: $(basename "$dst") — $(_human "$after"), ${pct}% smaller"
        notify "Compression done" "$base — ${pct}% smaller"
        processed=$(( processed + 1 )); pass_n=$(( pass_n + 1 ))
      else
        log "FAILED: '$name' — ffmpeg error. Last lines:"
        tail -5 "$fflog" 2>/dev/null | sed 's/^/    /' >> "$LOG"
        notify "Compression failed" "$base"
      fi
    done
    (( pass_n > 0 )) || break   # a full pass added nothing new — done
    log "rescan: $pass_n compressed in pass $pass — checking for files dropped meanwhile…"
  done
  log "run finished: $processed compressed in $pass pass(es)"
}
