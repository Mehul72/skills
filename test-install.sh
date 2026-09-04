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
hook_command() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["hooks"]["UserPromptSubmit"][0]["hooks"][0]["command"])' "$1"
}
hook_count() {
  python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["hooks"]["UserPromptSubmit"]))' "$1"
}
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

echo "Hook commands with spaces"
SPACED_LIB="$WORK/my libs"
mkdir -p "$SPACED_LIB"
cp -R bin hooks skills AGENTS.md CLAUDE.md install.sh "$SPACED_LIB/"

H=$(fresh_home hook-space)
HOME="$H" bash "$SPACED_LIB/bin/skills" install >/dev/null 2>&1
stored_hook=$(hook_command "$H/.claude/settings.json")
bash -c "$stored_hook" >/dev/null 2>&1
check "launcher hook runs from a spaced path" "0" "$?"
HOME="$H" bash "$SPACED_LIB/bin/skills" install >/dev/null 2>&1
check "launcher hook stays singular" "1" "$(hook_count "$H/.claude/settings.json")"

H=$(fresh_home hook-migrate); mkdir -p "$H/.claude"
python3 - "$H/.claude/settings.json" "$SPACED_LIB/hooks/inject-rules.sh" <<'PY'
import json, sys
path, command = sys.argv[1], sys.argv[2]
json.dump({"hooks": {"UserPromptSubmit": [{"hooks": [{"type": "command", "command": command}]}]}}, open(path, "w"))
PY
HOME="$H" bash "$SPACED_LIB/bin/skills" install >/dev/null 2>&1
stored_hook=$(hook_command "$H/.claude/settings.json")
bash -c "$stored_hook" >/dev/null 2>&1
check "launcher migrates an unquoted hook" "0" "$?"
check "migrated launcher hook stays singular" "1" "$(hook_count "$H/.claude/settings.json")"

H=$(fresh_home legacy-hook-space)
HOME="$H" bash "$SPACED_LIB/install.sh" --user --link >/dev/null 2>&1
stored_hook=$(hook_command "$H/.claude/settings.json")
bash -c "$stored_hook" >/dev/null 2>&1
check "legacy installer hook runs from a spaced path" "0" "$?"
HOME="$H" bash "$SPACED_LIB/install.sh" --user --link >/dev/null 2>&1
check "legacy installer hook stays singular" "1" "$(hook_count "$H/.claude/settings.json")"

PROJECT_WITH_SPACE="$WORK/project with space"
mkdir -p "$PROJECT_WITH_SPACE"
HOME="$H" bash "$SPACED_LIB/install.sh" "$PROJECT_WITH_SPACE" >/dev/null 2>&1
stored_hook=$(hook_command "$PROJECT_WITH_SPACE/.claude/settings.json")
env CLAUDE_PROJECT_DIR="$PROJECT_WITH_SPACE" bash -c "$stored_hook" >/dev/null 2>&1
check "project hook runs from a spaced repo path" "0" "$?"
HOME="$H" bash "$SPACED_LIB/install.sh" "$PROJECT_WITH_SPACE" >/dev/null 2>&1
check "project hook stays singular" "1" \
  "$(hook_count "$PROJECT_WITH_SPACE/.claude/settings.json")"

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
         .github/copilot-instructions.md .cursor/rules/skills.mdc; do
  check "wrote $f" "yes" "$([ -e "$REPO/$f" ] && echo yes || echo no)"
done
check "git status stays clean" "0" "$(git -C "$REPO" status --porcelain | wc -l | tr -d ' ')"
check "cursor rule points at the library" "1" \
  "$(grep -cF "$LIB/skills/<name>/SKILL.md" "$REPO/.cursor/rules/skills.mdc")"
check "cursor rule lists the skills" "1" \
  "$(grep -cF 'handoff' "$REPO/.cursor/rules/skills.mdc")"
# Cursor reads the root AGENTS.md natively, so copying the same rules into
# .cursor/rules as well would only occupy its context twice.
check "no second copy of the rules for cursor" "no" \
  "$([ -e "$REPO/.cursor/rules/agent-rules.mdc" ] && echo yes || echo no)"
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

# The cursor rule names every installed skill, so it goes stale the moment one is added.
# It gets its own stamp, under its own key, so refreshing it never touches AGENTS.md.
check "cursor rule stamped separately" "yes" \
  "$([ -f "$REPO2/.git/info/skills-init-cursor-skills.sha" ] && echo yes || echo no)"
mkdir -p "$COPY/skills/brand-new"
printf -- '---\nname: brand-new\n---\n' > "$COPY/skills/brand-new/SKILL.md"
out=$(HOME="$H" bash "$COPY/bin/skills" init "$REPO2" 2>&1)
check "a new skill reaches the cursor rule" "1" \
  "$(grep -c 'brand-new' "$REPO2/.cursor/rules/skills.mdc")"
check "refreshing it parks no backup" "0" \
  "$(find "$REPO2/.cursor" -name '*.from-skills-library' | wc -l | tr -d ' ')"

# Cursor reads AGENTS.md natively, so a repo that already has one of its own leaves the
# library no way in. .cursor/rules is the second channel, and the only one free.
echo "Repo with an AGENTS.md of its own"
H=$(fresh_home cursor); OWN="$WORK/own-agents"
mkdir -p "$OWN"; git -C "$OWN" init -q
printf 'house rules, hands off\n' > "$OWN/AGENTS.md"
out=$(HOME="$H" bash bin/skills init "$OWN" 2>&1)
check "their AGENTS.md untouched" "house rules, hands off" "$(cat "$OWN/AGENTS.md")"
check "backup offered"            "1" \
  "$(find "$OWN" -name 'AGENTS.md.from-skills-library' | wc -l | tr -d ' ')"
check "cursor still gets the rules" "yes" \
  "$([ -f "$OWN/.cursor/rules/agent-rules.mdc" ] && echo yes || echo no)"
contains "as an always-on rule" "alwaysApply: true" "$(cat "$OWN/.cursor/rules/agent-rules.mdc")"
check "carrying the routing table" "1" \
  "$(grep -c '^## Skill routing' "$OWN/.cursor/rules/agent-rules.mdc")"
check "git status stays clean"     "0" "$(git -C "$OWN" status --porcelain | wc -l | tr -d ' ')"

# The aliases still get linked, since the project's own rules beat none, but reporting
# that as a success hid the fact that five agents were getting nothing from the library.
check "no alias reported as configured" "0" \
  "$(printf '%s' "$out" | grep -c "AGENTS.md  (Cline)$")"
contains "the gap is named"      "carries none of the library's rules" "$out"
contains "and the merge is offered" "merge AGENTS.md.from-skills-library" "$out"

# Merging the parked copy into their own file makes the .cursor duplicate redundant.
# Deleting it for them would be overreach, so init says so instead.
cat "$OWN/AGENTS.md.from-skills-library" >> "$OWN/AGENTS.md"
out=$(HOME="$H" bash bin/skills init "$OWN" 2>&1)
contains "redundant copy called out after a merge" "duplicates the rules" "$out"
check "aliases stop warning once merged" "1" \
  "$(printf '%s' "$out" | grep -c '\.clinerules  (Cline)$')"
check "not deleted behind their back" "yes" \
  "$([ -f "$OWN/.cursor/rules/agent-rules.mdc" ] && echo yes || echo no)"

# run() used to eval its argument, so a path holding an apostrophe broke out of the
# quoting and a crafted one executed. Both are ordinary things to find in a directory name.
echo "Paths with shell punctuation"
H=$(fresh_home punct); QUOTED="$WORK/Bob's Projects"
mkdir -p "$QUOTED"; git -C "$QUOTED" init -q
HOME="$H" bash bin/skills init "$QUOTED" >/dev/null 2>&1; rc=$?
check "init survives an apostrophe"  "0"   "$rc"
check "and still writes AGENTS.md"   "yes" "$([ -f "$QUOTED/AGENTS.md" ] && echo yes || echo no)"
check "and the cursor rule"          "yes" "$([ -f "$QUOTED/.cursor/rules/skills.mdc" ] && echo yes || echo no)"

# The payload carries no slash, so mkdir cannot create the marker as a side effect, and
# the subshell cd means a successful injection would land it somewhere visible.
EVIL="$WORK/punct-evil"
mkdir -p "$EVIL/repo'\$(touch EXECUTED)'x"
git -C "$EVIL/repo'\$(touch EXECUTED)'x" init -q
( cd "$EVIL" && HOME="$H" bash "$LIB/bin/skills" init "$EVIL/repo'\$(touch EXECUTED)'x" >/dev/null 2>&1 )
check "a crafted directory name does not execute" "no" \
  "$([ -e "$EVIL/EXECUTED" ] && echo yes || echo no)"

echo "Dry run init"
H=$(fresh_home dryinit); DRYREPO="$WORK/dry-repo"
mkdir -p "$DRYREPO"; git -C "$DRYREPO" init -q
out=$(HOME="$H" bash bin/skills init "$DRYREPO" --dry-run 2>&1)
check "writes nothing into the repo" "0" \
  "$(find "$DRYREPO" -mindepth 1 -not -path "$DRYREPO/.git*" | wc -l | tr -d ' ')"
contains "still previews the redirected write" "write" "$out"

# validate.sh's cross-reference check was dead for its whole life: the condition read
# `c not in names and c in names`. Both halves of the replacement are pinned here, since
# a skill named in prose or in the routing table but absent on disk loads as nothing.
echo "Skill cross-references"
VAL="$WORK/validate-prose"
mkdir -p "$VAL"; cp -R validate.sh skills AGENTS.md "$VAL/"
printf '\nSee `totally-made-up-skill` for more.\n' >> "$VAL/skills/adr/SKILL.md"
out=$(cd "$VAL" && bash validate.sh 2>&1); rc=$?
check "prose reference to a missing skill fails" "1" "$rc"
contains "and the name is reported" "totally-made-up-skill" "$out"

VAL2="$WORK/validate-table"
mkdir -p "$VAL2"; cp -R validate.sh skills AGENTS.md "$VAL2/"
sed 's/| `grilling` |/| `griling` |/' "$VAL2/AGENTS.md" > "$VAL2/AGENTS.new"
mv "$VAL2/AGENTS.new" "$VAL2/AGENTS.md"
out=$(cd "$VAL2" && bash validate.sh 2>&1); rc=$?
check "a routing table typo fails" "1" "$rc"
contains "even for a single word skill" "griling" "$out"

echo "Init outside a git repo"
H=$(fresh_home nogit); PLAIN="$WORK/plain"; mkdir -p "$PLAIN"
out=$(HOME="$H" bash bin/skills init "$PLAIN" 2>&1); rc=$?
check "exits clean without git" "0" "$rc"
check "still writes AGENTS.md"  "yes" "$([ -f "$PLAIN/AGENTS.md" ] && echo yes || echo no)"
contains "says why nothing was excluded" "not a git repo yet" "$out"

echo
if [ "$fail" -gt 0 ]; then echo "FAIL: $fail failed, $pass passed"; exit 1; fi
echo "OK: $pass checks passed"
