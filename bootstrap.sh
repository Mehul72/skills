#!/usr/bin/env bash
# One-command install.
#
#   curl -fsSL https://raw.githubusercontent.com/<you>/skills/main/bootstrap.sh | bash
#
# Clones the library, installs the global layer for every agent that has one, and
# puts `skills` on your PATH. Safe to re-run; it pulls instead of re-cloning.
#
# Private repo? Clone it yourself, then run ./bootstrap.sh from inside the clone.
#
# Env: SKILLS_REPO   git URL to clone       (default: this file's origin)
#      SKILLS_DIR    where to clone         (default: ~/.agent-skills)
#      SKILLS_BIN    where to link `skills` (default: ~/.local/bin)

set -euo pipefail

REPO="${SKILLS_REPO:-https://github.com/CHANGE-ME/skills.git}"
DIR="${SKILLS_DIR:-$HOME/.agent-skills}"
BIN="${SKILLS_BIN:-$HOME/.local/bin}"

command -v git >/dev/null 2>&1 || { echo "error: git is required" >&2; exit 1; }

# Running from inside an existing clone? Use it and skip the network entirely.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
if [ -n "$HERE" ] && [ -f "$HERE/bin/skills" ]; then
  DIR="$HERE"
  echo "Using this clone: $DIR"
elif [ -d "$DIR/.git" ]; then
  echo "Updating $DIR"
  git -C "$DIR" pull --ff-only
else
  echo "Cloning $REPO -> $DIR"
  git clone --depth 1 "$REPO" "$DIR"
fi

mkdir -p "$BIN"
ln -sf "$DIR/bin/skills" "$BIN/skills"
echo "Linked $BIN/skills"
echo

"$DIR/bin/skills" install

echo
case ":$PATH:" in
  *":$BIN:"*) echo "Done. Run: skills doctor" ;;
  *) echo "Add $BIN to your PATH, then run: skills doctor"
     echo "    echo 'export PATH=\"$BIN:\$PATH\"' >> ~/.zshrc && exec zsh" ;;
esac
echo "In each work repo:  skills init"
