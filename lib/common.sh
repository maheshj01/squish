#!/bin/bash
# common.sh — constants, paths, and output helpers shared by every module.
#
# Sourced by the `squish` entry point before any other lib. Everything here is
# global on purpose; keep it dependency-free so other modules can rely on it.

APP="squish"
VERSION="0.3.0"
LABEL="com.mahesh.squish"

# ---- install locations (stable; launchd points here) ----------------------
INSTALL_DIR="$HOME/.local/share/$APP"          # where the code lives once installed
BIN_LINK="$HOME/bin/$APP"                       # convenience symlink on PATH
COMPLETION_DIR="$HOME/.zsh/completions"         # zsh tab-completion drop-in
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LAUNCHD_LOG="$HOME/Library/Logs/$APP.launchd.log"

# ---- runtime paths --------------------------------------------------------
CONFIG_DIR="$HOME/.config/$APP"
CONFIG_FILE="$CONFIG_DIR/config"
LOCK="/tmp/$APP.lock"
# The run log MUST live outside the watch folder: anything written inside the
# watched path re-fires WatchPaths and the agent loops on itself.
RUN_LOG="$HOME/Library/Logs/$APP.log"

# ---- defaults: the single source of truth for `config reset` --------------
# Everything lives under one media home: ~/Movies/squish/{clips,compressed}.
#   clips/       — the watch folder (videos are dropped here)
#   compressed/  — one subfolder per video, holding the result + its log
# NOTE: keep these OUT of ~/Desktop, ~/Documents, ~/Downloads — those are
# TCC-protected and a headless launchd agent is silently denied access there.
# ~/Movies is not protected, so the agent can read/write without a prompt.
# COMPRESSED_DIR must stay OUTSIDE the watch folder, or writing results would
# re-fire WatchPaths and loop the agent (that's why it's a sibling of clips/).
DEFAULT_WATCH_DIR="$HOME/Movies/squish/clips"
DEFAULT_COMPRESSED_DIR="$HOME/Movies/squish/compressed"
DEFAULT_CRF=23
DEFAULT_PRESET=medium
DEFAULT_AUDIO_BITRATE=128k
DEFAULT_NOTIFY=1

# recognised config keys, in display order
KEYS=(WATCH_DIR COMPRESSED_DIR CRF PRESET AUDIO_BITRATE NOTIFY)

# ---- output helpers -------------------------------------------------------
# Colours only when stderr is a TTY, so piped/logged output stays clean.
if [[ -t 2 ]]; then
  c_reset=$'\033[0m'; c_bold=$'\033[1m'; c_dim=$'\033[2m'
  c_red=$'\033[31m'; c_grn=$'\033[32m'; c_yel=$'\033[33m'
else
  c_reset=""; c_bold=""; c_dim=""; c_red=""; c_grn=""; c_yel=""
fi

say()  { printf '%s\n' "$*"; }                                   # stdout: data
info() { printf '%s\n' "$*" >&2; }                               # stderr: chatter
ok()   { printf '%s%s%s\n' "$c_grn" "$*" "$c_reset" >&2; }
warn() { printf '%s%s%s\n' "$c_yel" "$*" "$c_reset" >&2; }
die()  { printf '%s%s%s\n' "$c_red" "$*" "$c_reset" >&2; exit 1; }
