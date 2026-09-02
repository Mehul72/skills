#!/usr/bin/env bash
# Install this skills library.
#
#   ./install.sh --user --link     # all projects, auto-updates on git pull  (recommended)
#   ./install.sh --user            # all projects, copied
#   ./install.sh                   # this repo only  (-> ./.claude/skills)
#   ./install.sh /path/to/repo     # that repo only
#   ./install.sh --list            # show what's available
#   ./install.sh --uninstall --user
#
# Flags
#   --user        install to ~/.claude  instead of a project's .claude
#   --link        symlink each skill back to this clone rather than copying, so
#                 `git pull` updates every skill with no reinstall
#   NO_HOOK=1     skip the per-turn UserPromptSubmit hook
#
# Never overwrites an existing CLAUDE.md, AGENTS.md, or hook. Merges the hook into
# settings.json without touching anything already configured there.

set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$LIB_DIR/skills"
TARGET=""; USER_MODE=0; LINK=0; UNINSTALL=0

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
    --user)      USER_MODE=1; shift ;;
    --link)      LINK=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help)   sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)          echo "unknown option: $1" >&2; exit 1 ;;
    *)           TARGET="$1"; shift ;;
  esac
done

if [ "$USER_MODE" = 1 ]; then
  [ -z "$TARGET" ] || { echo "error: --user takes no path" >&2; exit 1; }
  BASE="$HOME/.claude"; SCOPE="all projects"
else
  TARGET="${TARGET:-$PWD}"
  [ -d "$TARGET" ] || { echo "error: no such directory: $TARGET" >&2; exit 1; }
  BASE="$TARGET/.claude"; SCOPE="$TARGET"
fi
DEST="$BASE/skills"

if [ "$UNINSTALL" = 1 ]; then
  n=0
  for d in "$SRC_DIR"/*/; do
    name=$(basename "$d")
    [ -e "$DEST/$name" ] || [ -L "$DEST/$name" ] || continue
    rm -rf "$DEST/$name"; echo "  - $name"; n=$((n+1))
  done
  echo "removed $n skill(s) from $DEST"
  echo "left in place: CLAUDE.md, AGENTS.md, hooks, and settings.json. Remove by hand."
  exit 0
fi

mkdir -p "$DEST"
count=0
for d in "$SRC_DIR"/*/; do
  [ -f "$d/SKILL.md" ] || continue
  name=$(basename "$d")
  rm -rf "$DEST/$name"
  if [ "$LINK" = 1 ]; then ln -s "${d%/}" "$DEST/$name"; else cp -R "$d" "$DEST/$name"; fi
  count=$((count+1))
done
echo "installed $count skill(s) -> $DEST  ($SCOPE)$([ "$LINK" = 1 ] && echo ', symlinked')"

# Always-on layer. Skills load on demand; this loads every session.
place() {  # $1 = source file, $2 = destination, $3 = hint when it already exists
  [ -f "$1" ] || return 0
  if [ -e "$2" ]; then
    if cmp -s "$1" "$2"; then echo "  = $(basename "$2") (unchanged)"
    else cp "$1" "$2.from-skills-library"
         echo "  ! $(basename "$2") exists, wrote $(basename "$2").from-skills-library"
         echo "      $3"; fi
  else cp "$1" "$2"; echo "  + $2"; fi
}

if [ "$USER_MODE" = 1 ]; then
  # Claude Code reads ~/.claude/CLAUDE.md and supports @path imports. Point it at
  # the clone so `git pull` updates the rules too.
  if [ -e "$BASE/CLAUDE.md" ]; then
    if grep -qF "@$LIB_DIR/AGENTS.md" "$BASE/CLAUDE.md"; then
      echo "  = ~/.claude/CLAUDE.md already imports the library"
    else
      echo "  ! ~/.claude/CLAUDE.md exists. Add this line to it:"
      echo "      @$LIB_DIR/AGENTS.md"
    fi
  else
    printf '@%s/AGENTS.md\n' "$LIB_DIR" > "$BASE/CLAUDE.md"
    echo "  + ~/.claude/CLAUDE.md (imports $LIB_DIR/AGENTS.md)"
  fi
  echo "  i This installer only covers Claude Code. For Codex, Gemini CLI, and the"
  echo "    per-repo agents (Cursor, Copilot, Cline, Windsurf), use the launcher:"
  echo "      $LIB_DIR/bin/skills install     # global layer, every agent"
  echo "      $LIB_DIR/bin/skills init <repo> # per-repo files"
else
  place "$LIB_DIR/AGENTS.md" "$TARGET/AGENTS.md" \
    "merge it into your existing AGENTS.md"
  place "$LIB_DIR/CLAUDE.md" "$TARGET/CLAUDE.md" \
    "add the line '@AGENTS.md' to your existing CLAUDE.md"
fi

# Per-turn hook. Claude Code only; no other agent has an equivalent event.
if [ -d "$LIB_DIR/hooks" ] && [ "${NO_HOOK:-0}" != "1" ]; then
  if [ "$USER_MODE" = 1 ]; then
    HOOK_CMD="$LIB_DIR/hooks/inject-rules.sh"          # runs from the clone, auto-updates
    echo "  + hook -> $HOOK_CMD"
  else
    mkdir -p "$BASE/hooks"
    for f in "$LIB_DIR"/hooks/*; do
      b=$(basename "$f")
      if [ -e "$BASE/hooks/$b" ] && ! cmp -s "$f" "$BASE/hooks/$b"; then
        echo "  ! .claude/hooks/$b exists and differs, left alone"
      else
        cp "$f" "$BASE/hooks/$b"; chmod +x "$BASE/hooks/$b" 2>/dev/null || true
        echo "  + .claude/hooks/$b"
      fi
    done
    HOOK_CMD='${CLAUDE_PROJECT_DIR}/.claude/hooks/inject-rules.sh'
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$BASE/settings.json" "$HOOK_CMD" <<'PYEOF'
import json, os, sys
p, cmd = sys.argv[1], sys.argv[2]
try:
    cfg = json.load(open(p)) if os.path.exists(p) and os.path.getsize(p) else {}
except json.JSONDecodeError:
    print(f"  ! {p} is not valid JSON, hook not registered"); sys.exit(0)
ups = cfg.setdefault("hooks", {}).setdefault("UserPromptSubmit", [])
if any(cmd in json.dumps(e) for e in ups):
    print("  = hook already registered")
else:
    ups.append({"hooks": [{"type": "command", "command": cmd}]})
    os.makedirs(os.path.dirname(p), exist_ok=True)
    json.dump(cfg, open(p, "w"), indent=2); open(p, "a").write("\n")
    print(f"  + registered UserPromptSubmit hook in {p}")
PYEOF
  else
    echo "  ! python3 not found. Add to $BASE/settings.json by hand:"
    echo "      \"hooks\": { \"UserPromptSubmit\": [ { \"hooks\": [ { \"type\": \"command\","
    echo "        \"command\": \"$HOOK_CMD\" } ] } ] }"
  fi
fi

echo
echo "Verify in a Claude Code session: /context (memory files), /hooks, then type /"
