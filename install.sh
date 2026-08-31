#!/usr/bin/env bash
# Install skills from this library into a target repository.
#
#   ./install.sh                 # install into the current directory
#   ./install.sh /path/to/repo   # install into <repo>/.claude/skills
#   ./install.sh --list          # show what's available
#   NO_HOOK=1 ./install.sh       # skip the per-turn hook
#
# Installs skills into <repo>/.claude/skills, plus AGENTS.md and CLAUDE.md at the
# repo root, and a per-turn UserPromptSubmit hook in .claude/hooks.
# Existing root files and hooks are never overwritten.

set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$LIB_DIR/skills"
TARGET=""

describe() {  # first line of the YAML description, folded scalars included
  awk '/^---$/{c++;next}
       c==1 && f && /^[[:space:]]/ {sub(/^[[:space:]]+/,""); print; exit}
       c==1 && /^description:/ {sub(/^description:[[:space:]]*/,"");
                                gsub(/^[>|][-+]?[[:space:]]*$/,"");
                                if (length($0)) {print; exit} else {f=1}}' "$1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list)
      for d in "$SRC_DIR"/*/; do
        [ -f "$d/SKILL.md" ] || continue
        printf "  %-22s %s\n" "$(basename "$d")" "$(describe "$d/SKILL.md" | cut -c1-90)"
      done
      exit 0 ;;
    -h|--help)  sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)         echo "unknown option: $1" >&2; exit 1 ;;
    *)          TARGET="$1"; shift ;;
  esac
done

TARGET="${TARGET:-$PWD}"
[ -d "$TARGET" ] || { echo "error: no such directory: $TARGET" >&2; exit 1; }
DEST="$TARGET/.claude/skills"
mkdir -p "$DEST"

count=0
for d in "$SRC_DIR"/*/; do
  [ -f "$d/SKILL.md" ] || continue
  name=$(basename "$d")
  rm -rf "$DEST/$name"
  cp -R "$d" "$DEST/$name"
  echo "  + $name"
  count=$((count + 1))
done

echo "installed $count skill(s) -> $DEST"

# Always-on layer. Skills load on demand; these load every session, which is what
# makes the routing and output rules apply without being asked for.
install_root_file() {  # $1 = filename, $2 = hint shown when we skip
  local src="$LIB_DIR/$1" dst="$TARGET/$1"
  [ -f "$src" ] || return 0
  if [ -e "$dst" ]; then
    if cmp -s "$src" "$dst"; then
      echo "  = $1 (unchanged)"
    else
      cp "$src" "$TARGET/$1.from-skills-library"
      echo "  ! $1 exists, wrote $1.from-skills-library instead"
      echo "      $2"
    fi
  else
    cp "$src" "$dst"
    echo "  + $1"
  fi
}

install_root_file AGENTS.md \
  "merge it in, or add its contents to your existing AGENTS.md"
install_root_file CLAUDE.md \
  "add the line '@AGENTS.md' to your existing CLAUDE.md"

# Per-turn hook. Instruction files load once per session; this re-states the hard
# rules on every prompt. Claude Code only. Other agents have no equivalent event.
HOOKS_SRC="$LIB_DIR/hooks"
if [ -d "$HOOKS_SRC" ] && [ "${NO_HOOK:-0}" != "1" ]; then
  HOOKS_DST="$TARGET/.claude/hooks"
  mkdir -p "$HOOKS_DST"
  for f in "$HOOKS_SRC"/*; do
    b=$(basename "$f")
    if [ -e "$HOOKS_DST/$b" ] && ! cmp -s "$f" "$HOOKS_DST/$b"; then
      echo "  ! .claude/hooks/$b exists and differs, left alone"
    else
      cp "$f" "$HOOKS_DST/$b"; chmod +x "$HOOKS_DST/$b" 2>/dev/null || true
      echo "  + .claude/hooks/$b"
    fi
  done

  SETTINGS="$TARGET/.claude/settings.json"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$SETTINGS" <<'PYEOF'
import json, os, sys
p = sys.argv[1]
cmd = "${CLAUDE_PROJECT_DIR}/.claude/hooks/inject-rules.sh"
try:
    cfg = json.load(open(p)) if os.path.exists(p) and os.path.getsize(p) else {}
except json.JSONDecodeError:
    print("  ! .claude/settings.json is not valid JSON, hook not registered")
    sys.exit(0)
hooks = cfg.setdefault("hooks", {})
ups = hooks.setdefault("UserPromptSubmit", [])
if any(cmd in json.dumps(e) for e in ups):
    print("  = hook already registered in .claude/settings.json")
else:
    ups.append({"hooks": [{"type": "command", "command": cmd}]})
    os.makedirs(os.path.dirname(p), exist_ok=True)
    json.dump(cfg, open(p, "w"), indent=2)
    open(p, "a").write("\n")
    print("  + registered UserPromptSubmit hook in .claude/settings.json")
PYEOF
  else
    echo "  ! python3 not found. Register the hook manually in .claude/settings.json:"
    echo '      "hooks": { "UserPromptSubmit": [ { "hooks": [ { "type": "command",'
    echo '        "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/inject-rules.sh" } ] } ] }'
  fi
fi
