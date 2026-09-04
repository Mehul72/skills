#!/usr/bin/env bash
# Check the installer against throwaway HOME directories.
#
#   ./test-install.sh
#
# Every case runs with HOME pointed at a scratch dir, so nothing here can touch the
# real ~/.claude, ~/.codex, or ~/.gemini. Covers what validate.sh cannot: where the
# install actually writes, what it refuses to overwrite, and whether the npm handoff
# leaves anything pointing into a cache directory that npx later deletes.

set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$PWD"

WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/skills-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
check() {  # check LABEL EXPECTED ACTUAL
  if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok   %s\n' "$1"
  else fail=$((fail+1)); printf '  FAIL %s\n         want: %s\n         got:  %s\n' "$1" "$2" "$3"; fi
}
contains() {  # contains LABEL NEEDLE HAYSTACK
  case "$3" in *"$2"*) pass=$((pass+1)); printf '  ok   %s\n' "$1" ;;
    *) fail=$((fail+1)); printf '  FAIL %s\n         missing: %s\n' "$1" "$2" ;; esac
}

# fresh_home NAME - a scratch HOME carrying Codex's own bundled skills, which the
# installer shares a directory with and must never disturb.
fresh_home() {
  local h="$WORK/$1"
  rm -rf "$h"; mkdir -p "$h/.codex/skills/.system/skill-creator"
  echo "codex-owned" > "$h/.codex/skills/.system/skill-creator/SKILL.md"
  printf '%s' "$h"
}
count() { ls -1 "$1" 2>/dev/null | wc -l | tr -d ' '; }
expected=$(ls -1d skills/*/ | wc -l | tr -d ' ')

echo "Fresh install"
H=$(fresh_home fresh)
: > "$H/.codex/AGENTS.md"          # the empty placeholder Codex writes on first run
out=$(HOME="$H" bash bin/skills install 2>&1)
check "skills -> ~/.claude/skills"  "$expected" "$(count "$H/.claude/skills")"
check "skills -> ~/.codex/skills"   "$expected" "$(count "$H/.codex/skills")"
check "codex .system untouched"     "codex-owned" "$(cat "$H/.codex/skills/.system/skill-creator/SKILL.md")"
check "a skill resolves through the symlink" "name: handoff" "$(sed -n 2p "$H/.codex/skills/handoff/SKILL.md")"
check "empty placeholder replaced"  "$LIB/AGENTS.md" "$(readlink "$H/.codex/AGENTS.md")"
check "no backup for an empty file" "0" "$(find "$H" -name '*.from-skills-library' | wc -l | tr -d ' ')"
check "launcher linked"             "$LIB/bin/skills" "$(readlink "$H/.local/bin/skills")"

echo "Re-running install changes nothing"
again=$(HOME="$H" bash bin/skills install 2>&1)
check "config reported unchanged" "0" "$(printf '%s' "$again" | grep -c 'exists and differs')"
check "still one launcher"        "$LIB/bin/skills" "$(readlink "$H/.local/bin/skills")"

echo "Existing user config is never clobbered"
H=$(fresh_home keep)
echo "my own rules" > "$H/.codex/AGENTS.md"
out=$(HOME="$H" bash bin/skills install 2>&1)
check "user content intact" "my own rules" "$(cat "$H/.codex/AGENTS.md")"
check "backup written"      "1" "$(find "$H/.codex" -name 'AGENTS.md.from-skills-library' | wc -l | tr -d ' ')"

echo "Dry run"
H=$(fresh_home dry)
HOME="$H" bash bin/skills install --dry-run >/dev/null 2>&1
check "nothing outside the seeded .codex" "0" \
  "$(find "$H" -mindepth 1 -not -path "$H/.codex*" | wc -l | tr -d ' ')"

echo "Uninstall"
H=$(fresh_home gone)
HOME="$H" bash bin/skills install >/dev/null 2>&1
HOME="$H" bash bin/skills uninstall >/dev/null 2>&1
check "~/.claude/skills emptied" "0" "$(count "$H/.claude/skills")"
check "~/.codex/skills emptied"  "0" "$(count "$H/.codex/skills")"
check "codex .system survived"   "codex-owned" "$(cat "$H/.codex/skills/.system/skill-creator/SKILL.md")"
HOME="$H" bash bin/skills uninstall >/dev/null 2>&1
check "uninstall is idempotent" "0" "$?"

# npx unpacks into a cache directory it later deletes. Anything left pointing there
# is a symlink that breaks the next time npm cleans up, so the install has to copy
# itself to $HOME first and hand off.
echo "npm handoff"
H=$(fresh_home npm)
PKG="$H/npmcache/_npx/cafe1234/node_modules/@mehul72/skills"
mkdir -p "$PKG"
cp -R bin hooks skills "$PKG/"
cp AGENTS.md CLAUDE.md package.json bootstrap.sh install.sh validate.sh "$PKG/"
out=$(HOME="$H" bash "$PKG/bin/skills" install 2>&1)
check "library copied to ~/.agent-skills" "yes" "$([ -d "$H/.agent-skills/skills" ] && echo yes || echo no)"
check "skills -> ~/.codex/skills"   "$expected" "$(count "$H/.codex/skills")"
check "links point at the stable home" "$H/.agent-skills/skills/handoff" "$(readlink "$H/.codex/skills/handoff")"
check "nothing points into the npx cache" "0" \
  "$(find "$H/.claude" "$H/.codex" "$H/.local" -type l -lname '*_npx*' 2>/dev/null | wc -l | tr -d ' ')"
check "launcher survives the cache"  "$H/.agent-skills/bin/skills" "$(readlink "$H/.local/bin/skills")"
mkdir -p "$H/.agent-skills/skills/removed-upstream"
mkdir -p "$H/.agent-skills/user-owned-directory"
printf '\nrefreshed npm payload\n' >> "$PKG/skills/handoff/SKILL.md"
HOME="$H" bash "$PKG/bin/skills" install >/dev/null 2>&1
check "npm refresh replaces stale skills" "no" \
  "$([ -e "$H/.agent-skills/skills/removed-upstream" ] && echo yes || echo no)"
check "npm refresh installs the new payload" "1" \
  "$(grep -cF 'refreshed npm payload' "$H/.agent-skills/skills/handoff/SKILL.md")"
check "npm refresh keeps unmanaged entries" "yes" \
  "$([ -d "$H/.agent-skills/user-owned-directory" ] && echo yes || echo no)"

INTERRUPT_BIN="$WORK/interrupt-bin"
mkdir -p "$INTERRUPT_BIN"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  '"${SKILLS_TEST_REAL_MV:?}" "$@"' \
  'rc=$?' \
  'if [ "$rc" -eq 0 ] && [ "${1:-}" = "${SKILLS_TEST_INTERRUPT_SOURCE:-}" ]; then' \
  '  kill -TERM "$PPID"' \
  'fi' \
  'exit "$rc"' > "$INTERRUPT_BIN/mv"
chmod +x "$INTERRUPT_BIN/mv"
printf '\ninterrupted npm payload\n' >> "$PKG/skills/handoff/SKILL.md"
env HOME="$H" PATH="$INTERRUPT_BIN:$PATH" SKILLS_TEST_REAL_MV="$(command -v mv)" \
  SKILLS_TEST_INTERRUPT_SOURCE="$H/.agent-skills/skills" \
  bash "$PKG/bin/skills" install >/dev/null 2>&1
interrupt_rc=$?
check "interrupted npm refresh exits nonzero" "nonzero" \
  "$([ "$interrupt_rc" -ne 0 ] && echo nonzero || echo zero)"
check "interrupted npm refresh restores the previous payload" "0" \
  "$(grep -cF 'interrupted npm payload' "$H/.agent-skills/skills/handoff/SKILL.md")"
check "interrupted npm refresh leaves no dangling links" "0" \
  "$(find "$H/.claude" "$H/.codex" "$H/.local" -type l ! -exec test -e {} \; -print | wc -l | tr -d ' ')"
check "interrupted npm refresh removes staging directories" "0" \
  "$(find "$H" -maxdepth 1 -type d -name '.agent-skills.*' | wc -l | tr -d ' ')"

rm -rf "$PKG/skills"
HOME="$H" bash "$PKG/bin/skills" install >/dev/null 2>&1
refresh_rc=$?
check "failed npm refresh exits nonzero" "nonzero" "$([ "$refresh_rc" -ne 0 ] && echo nonzero || echo zero)"
check "failed npm refresh keeps the installed library" "yes" \
  "$([ -d "$H/.agent-skills/skills" ] && echo yes || echo no)"
check "failed npm refresh leaves no dangling skill links" "0" \
  "$(find "$H/.claude" "$H/.codex" "$H/.local" -type l ! -exec test -e {} \; -print | wc -l | tr -d ' ')"
rm -rf "$H/npmcache"
check "skills still resolve after the cache is wiped" "name: handoff" \
  "$(sed -n 2p "$H/.codex/skills/handoff/SKILL.md")"

echo "PATH advice"
H=$(fresh_home path)
out=$(env -i HOME="$H" PATH=/usr/bin:/bin bash bin/skills install 2>&1)
contains "warns when the launcher is unreachable" "is not on your PATH" "$out"
mkdir -p "$H/.local/bin"
out=$(HOME="$H" PATH="$H/.local/bin:$PATH" bash bin/skills install 2>&1)
contains "confirms once the bin dir is on PATH" "is on your PATH" "$out"
# npx puts its own bin on PATH only for the length of one command.
out=$(HOME="$H" PATH="$WORK/x/_npx/aa/node_modules/.bin:/usr/bin:/bin" bash bin/skills install 2>&1)
contains "does not count npx's throwaway bin" "is not on your PATH" "$out"

echo "Repo init"
H=$(fresh_home repo); REPO="$WORK/project"
mkdir -p "$REPO"; git -C "$REPO" init -q
HOME="$H" bash bin/skills init "$REPO" >/dev/null 2>&1
for f in AGENTS.md CLAUDE.md GEMINI.md CONVENTIONS.md .clinerules .windsurfrules \
         .github/copilot-instructions.md; do
  check "wrote $f" "yes" "$([ -e "$REPO/$f" ] && echo yes || echo no)"
done
check "git status stays clean" "0" "$(git -C "$REPO" status --porcelain | wc -l | tr -d ' ')"
check "AGENTS.md no longer points at a repo-relative skills path" "0" \
  "$(grep -cF 'Full detail lives in `.claude/skills/`' "$REPO/AGENTS.md")"

# A repo set up before a library update has to be able to pick the update up. The
# copy init wrote is indistinguishable from a hand written one without a record of
# what init put there, so the refresh path and the do-not-clobber path are both tested.
echo "Re-init after the library changes"
H=$(fresh_home reinit); REPO2="$WORK/stale"
COPY="$WORK/lib-v2"; cp -R "$LIB" "$COPY"; rm -rf "$COPY/.git"
mkdir -p "$REPO2"; git -C "$REPO2" init -q
HOME="$H" bash "$COPY/bin/skills" init "$REPO2" >/dev/null 2>&1
check "stamp recorded" "yes" "$([ -f "$REPO2/.git/info/skills-init.sha" ] && echo yes || echo no)"

printf '\n<!-- library update -->\n' >> "$COPY/AGENTS.md"
out=$(HOME="$H" bash "$COPY/bin/skills" init "$REPO2" 2>&1)
check "unedited copy refreshed" "1" "$(grep -c 'library update' "$REPO2/AGENTS.md")"
check "no backup parked for it" "0" "$(find "$REPO2" -name '*.from-skills-library' | wc -l | tr -d ' ')"

printf '\n<!-- my own rule -->\n' >> "$REPO2/AGENTS.md"
printf '\n<!-- second library update -->\n' >> "$COPY/AGENTS.md"
out=$(HOME="$H" bash "$COPY/bin/skills" init "$REPO2" 2>&1)
check "hand edit survives"  "1" "$(grep -c 'my own rule' "$REPO2/AGENTS.md")"
check "hand edit not overwritten" "0" "$(grep -c 'second library update' "$REPO2/AGENTS.md")"
check "backup offered instead" "1" "$(find "$REPO2" -name 'AGENTS.md.from-skills-library' | wc -l | tr -d ' ')"

out=$(HOME="$H" bash "$COPY/bin/skills" init "$REPO2" --force 2>&1)
check "--force takes the update" "1" "$(grep -c 'second library update' "$REPO2/AGENTS.md")"

echo "Init outside a git repo"
H=$(fresh_home nogit); PLAIN="$WORK/plain"; mkdir -p "$PLAIN"
out=$(HOME="$H" bash bin/skills init "$PLAIN" 2>&1); rc=$?
check "exits clean without git" "0" "$rc"
check "still writes AGENTS.md"  "yes" "$([ -f "$PLAIN/AGENTS.md" ] && echo yes || echo no)"
contains "says why nothing was excluded" "not a git repo yet" "$out"

echo
if [ "$fail" -gt 0 ]; then echo "FAIL: $fail failed, $pass passed"; exit 1; fi
echo "OK: $pass checks passed"
