#!/bin/bash
# worker.sh — the compression pass launchd triggers (and you can run by hand).
#
# Originals are never touched. Output goes to <watch>/outputs/<name>_output.mp4.
# The guards exist because launchd's WatchPaths is blunt: it fires repeatedly
# during a single copy, and before the file has finished writing.

cmd_run() {
  load_config
  # Results live OUTSIDE the watch folder — writing inside it would re-fire
  # WatchPaths and loop the agent. Each video gets its own subfolder under
  # COMPRESSED_DIR (the compressed file + its ffmpeg log). The run log lives
  # under ~/Library/Logs.
  local OUT_DIR="$COMPRESSED_DIR"
  local LOG="$RUN_LOG"
  mkdir -p "$OUT_DIR" "$(dirname "$LOG")"

  log() { printf '%s  %s\n' "$(date '+%H:%M:%S')" "$*" >> "$LOG"; }
  human() { awk -v b="$1" 'BEGIN{ if(b>=1048576) printf "%.1f MB",b/1048576; else printf "%.0f KB",b/1024 }'; }
  notify() {
    (( NOTIFY )) || return 0
    local t=${1//\\/\\\\}; t=${t//\"/\\\"}; local m=${2//\\/\\\\}; m=${m//\"/\\\"}
    /usr/bin/osascript -e "display notification \"$m\" with title \"$t\"" 2>/dev/null || true
  }

  log "──── run started (pid $$, user $(whoami)) ────"

  # ffmpeg — launchd gives us almost no PATH, so look in the usual places.
  local FFMPEG="" c
  for c in /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg "$(command -v ffmpeg 2>/dev/null)"; do
    [[ -x "$c" ]] && { FFMPEG="$c"; break; }
  done
  if [[ -z "$FFMPEG" ]]; then
    log "FATAL: ffmpeg not found. fix: brew install ffmpeg"
    notify "Compression error" "ffmpeg not found"; return 1
  fi
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

  shopt -s nullglob nocaseglob
  local candidates=0 processed=0 src name ext base clip_dir dst tmp fflog before after pct
  for src in "$WATCH_DIR"/*; do
    [[ -f "$src" ]] || continue
    name=$(basename "$src"); ext="${name##*.}"; base="${name%.*}"
    case "$name" in .DS_Store|.*) continue ;; esac
    case "$(echo "$ext" | tr '[:upper:]' '[:lower:]')" in
      mov|mp4|m4v|avi|mkv|webm|mpg|mpeg|wmv|flv) ;;
      *) log "skip '$name': .$ext is not a video type"; continue ;;
    esac
    candidates=$(( candidates + 1 ))
    # each video gets its own subfolder: compressed/<base>/{<base>.mp4,<base>.log}
    clip_dir="$OUT_DIR/$base"; dst="$clip_dir/${base}.mp4"
    [[ -e "$dst" ]] && { log "skip '$name': already compressed"; continue; }

    log "FOUND: $name"
    wait_until_stable "$src" || { log "skip '$name': file never settled"; continue; }

    mkdir -p "$clip_dir"
    tmp="$clip_dir/.${base}.partial.mp4"; fflog="$clip_dir/${base}.log"; rm -f "$tmp"
    before=$(stat -f%z "$src")
    log "encoding '$name' ($(human "$before")) -> compressed/$base/$(basename "$dst")"
    log "  ffmpeg output: $fflog"
    if "$FFMPEG" -nostdin -y -i "$src" \
         -c:v libx264 -crf "$CRF" -preset "$PRESET" -pix_fmt yuv420p \
         -c:a aac -b:a "$AUDIO_BITRATE" -movflags +faststart \
         "$tmp" > "$fflog" 2>&1
    then
      mv -f "$tmp" "$dst"; after=$(stat -f%z "$dst"); pct=$(( 100 - (after * 100 / before) ))
      log "OK: $(basename "$dst") — $(human "$after"), ${pct}% smaller"
      notify "Compression done" "$base — ${pct}% smaller"; processed=$(( processed + 1 ))
    else
      local rc=$?; rm -f "$tmp"
      log "FAILED: '$name' — ffmpeg exit $rc. Last lines:"
      tail -5 "$fflog" 2>/dev/null | sed 's/^/    /' >> "$LOG"
      notify "Compression failed" "$base"
    fi
  done
  log "run finished: $candidates video file(s) seen, $processed compressed"
}
