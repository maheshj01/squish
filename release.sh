#!/bin/bash
# release.sh — cut a squish release and update the Homebrew tap in one shot.
#
#   ./release.sh <version>          e.g. ./release.sh 0.2.0
#
# It bumps VERSION, commits, tags + pushes the source repo, computes the release
# tarball's sha256, then updates and pushes Formula/squish.rb in the tap repo.
#
# The tap repo is expected next to this one (../homebrew-tap); override with:
#   TAP_DIR=/path/to/homebrew-tap ./release.sh 0.2.0
set -euo pipefail

APP="squish"
OWNER="maheshj01"
SOURCE_REPO="squish"                 # GitHub repo holding the source + tags
FORMULA="Formula/$APP.rb"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAP_DIR="${TAP_DIR:-$REPO_ROOT/../homebrew-tap}"
cd "$REPO_ROOT"

ver="${1:-}"
[[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: ./release.sh <X.Y.Z>" >&2; exit 1; }
tag="v$ver"

# ---- preconditions --------------------------------------------------------
[[ -z "$(git status --porcelain)" ]] || { echo "error: working tree not clean — commit or stash first." >&2; exit 1; }
git rev-parse -q --verify "refs/tags/$tag" >/dev/null && { echo "error: tag $tag already exists (delete it or pick a new version)." >&2; exit 1; }
[[ -d "$TAP_DIR/.git" ]]      || { echo "error: tap repo not found at $TAP_DIR — set TAP_DIR=..." >&2; exit 1; }
[[ -f "$TAP_DIR/$FORMULA" ]]  || { echo "error: $TAP_DIR/$FORMULA missing." >&2; exit 1; }

echo "==> Releasing $APP $ver  (tap: $TAP_DIR)"

# ---- 1) bump VERSION, commit, push source --------------------------------
current="$(sed -n 's/^VERSION="\(.*\)"/\1/p' lib/common.sh)"
if [[ "$current" != "$ver" ]]; then
  sed -i '' "s/^VERSION=\".*\"/VERSION=\"$ver\"/" lib/common.sh
  git add lib/common.sh
  git commit -m "chore: release $ver"
fi
git push origin HEAD

# ---- 2) tag + push --------------------------------------------------------
git tag "$tag" -m "Release $ver"
git push origin "$tag"

# ---- 3) hash the release tarball (retry: GitHub may lag a moment) ---------
url="https://github.com/$OWNER/$SOURCE_REPO/archive/refs/tags/$tag.tar.gz"
echo "==> Hashing $url"
sha=""
for _ in 1 2 3 4 5; do
  if sha="$(curl -fsSL "$url" | shasum -a 256 | awk '{print $1}')" && [[ -n "$sha" ]]; then break; fi
  echo "   waiting for GitHub to publish the tarball…"; sleep 3
done
[[ -n "$sha" ]] || { echo "error: could not fetch $url" >&2; exit 1; }
echo "   sha256 $sha"

# ---- 4) update tap formula (url version + sha256), commit, push ----------
cd "$TAP_DIR"
sed -i '' -E "s#(archive/refs/tags/)v[0-9]+\.[0-9]+\.[0-9]+(\.tar\.gz)#\1$tag\2#" "$FORMULA"
sed -i '' -E "s/^([[:space:]]*sha256 )\".*\"/\1\"$sha\"/" "$FORMULA"
git add "$FORMULA"
git commit -m "$APP $ver"
git push origin HEAD

echo
echo "==> Released $APP $ver. Users update with:"
echo "    brew update && brew upgrade $APP        # or: brew install $OWNER/tap/$APP"
