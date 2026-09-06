#!/bin/bash
# clean.sh — empty the clips and/or compressed folders, with a y/N confirm.
#
#   squish clean             clips AND compressed
#   squish clean clips       just the watched inputs
#   squish clean compressed  just the compressed outputs
# The folders themselves are kept; only their contents are removed.

# Delete everything inside a directory (never the directory itself, never "/").
_empty_dir() {
  local d="$1"
  [[ -n "$d" && "$d" != "/" && -d "$d" ]] || return 0
  find "$d" -mindepth 1 -delete 2>/dev/null || true
}

# Count entries (incl. hidden) under a directory.
_count() { [[ -d "$1" ]] && { find "$1" -mindepth 1 2>/dev/null | wc -l | tr -d ' '; } || echo 0; }

cmd_clean() {
  load_config
  local target="${1:-all}"
  local -a dirs=(); local label=""
  case "$target" in
    clips)      dirs=("$WATCH_DIR");                   label="clips (input videos)" ;;
    compressed) dirs=("$COMPRESSED_DIR");              label="compressed outputs" ;;
    all|"")     dirs=("$WATCH_DIR" "$COMPRESSED_DIR"); label="clips AND compressed" ;;
    *) die "usage: $APP clean [clips|compressed]" ;;
  esac

  local d total=0 n
  for d in "${dirs[@]}"; do
    n="$(_count "$d")"
    printf '%s%s%s  (%s item%s)\n' "$c_dim" "$d" "$c_reset" "$n" "$([[ "$n" == 1 ]] || echo s)" >&2
    total=$(( total + n ))
  done
  (( total > 0 )) || { info "nothing to clean."; return 0; }

  confirm "Delete $total item(s) from $label? This cannot be undone." \
    || { info "cancelled."; return 0; }
  for d in "${dirs[@]}"; do _empty_dir "$d"; done
  ok "cleaned $label."
}
