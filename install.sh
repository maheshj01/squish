#!/bin/bash
# install.sh — manual / dev installer for squish (non-Homebrew).
#
# Homebrew users don't need this: `brew install <tap>/squish` places the files,
# then `squish start`. This script does the same placement by hand:
#   - copies the CLI + lib to ~/.local/share/squish
#   - symlinks ~/bin/squish onto your PATH
#   - installs the zsh completion to ~/.zsh/completions
#   - then runs `squish start` to create the folders and begin watching.
set -euo pipefail

APP="squish"
SRC="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.local/share/$APP"
BIN_DIR="$HOME/bin"
COMPLETION_DIR="$HOME/.zsh/completions"

command -v ffmpeg >/dev/null 2>&1 || echo "warning: ffmpeg not found — install it with:  brew install ffmpeg" >&2

echo "installing $APP -> $INSTALL_DIR"
mkdir -p "$INSTALL_DIR/lib" "$BIN_DIR" "$COMPLETION_DIR"
cp "$SRC/$APP" "$INSTALL_DIR/$APP"
cp "$SRC"/lib/*.sh "$INSTALL_DIR/lib/"
chmod +x "$INSTALL_DIR/$APP"
ln -sf "$INSTALL_DIR/$APP" "$BIN_DIR/$APP"
[[ -f "$SRC/completions/_$APP" ]] && cp "$SRC/completions/_$APP" "$COMPLETION_DIR/_$APP"

# Start watching (creates the default folders too).
"$INSTALL_DIR/$APP" start

echo
echo "done. If needed, add these to ~/.zshrc (one time):"
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) echo '  export PATH="$HOME/bin:$PATH"' ;; esac
case ":${FPATH:-}:" in *":$COMPLETION_DIR:"*) ;; *) echo "  fpath=($COMPLETION_DIR \$fpath); autoload -Uz compinit; compinit" ;; esac
echo "then:  squish status"
