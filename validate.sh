#!/usr/bin/env bash
# Check every skill before committing or installing.
#
#   ./validate.sh
#
# Catches: frontmatter mangled by a markdown formatter (a closing `---` read as a
# Setext heading underline rewrites `name:` into `## name:`), name/directory
# mismatch, em and en dashes, and cross-references to skills that do not exist.

set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 - <<'PY'
import glob, os, re, sys

fail = []
names = {os.path.basename(os.path.dirname(p)) for p in glob.glob("skills/*/SKILL.md")}

for p in sorted(glob.glob("skills/*/SKILL.md")):
    d = os.path.basename(os.path.dirname(p))
    t = open(p).read()
    if not t.startswith("---\n"):
        fail.append(f"{p}: missing opening ---"); continue
    m = re.match(r"^---\n(.*?)\n---\n", t, re.S)
    if not m:
        fail.append(f"{p}: missing closing --- (markdown formatter may have eaten it)"); continue
    fm = m.group(1)
    if re.search(r"^##\s+\w+:", fm, re.M):
        fail.append(f"{p}: frontmatter key rewritten as a heading")
    n = re.search(r"^name:\s*(\S+)", fm, re.M)
    if not n:
        fail.append(f"{p}: no name")
    elif n.group(1) != d:
        fail.append(f"{p}: name '{n.group(1)}' does not match directory '{d}'")
    if not re.search(r"^description:\s*\S", fm, re.M):
        fail.append(f"{p}: no description")

files = glob.glob("skills/**/*.md", recursive=True)
files += [f for f in ("README.md", "AGENTS.md", "CLAUDE.md",
                      "hooks/session-rules.md") if os.path.exists(f)]
for f in files:
    t = open(f).read()
    for ch, label in (("—", "em dash"), ("–", "en dash")):
        if ch in t:
            line = t[:t.index(ch)].count("\n") + 1
            fail.append(f"{f}:{line}: {label} (response-style bans these)")

for f in sorted(glob.glob("skills/*/SKILL.md")) + ["AGENTS.md"]:
    if not os.path.exists(f): continue
    for m in re.finditer(r"(?:use|see|is|to|and) `([a-z]+(?:-[a-z]+)+)`", open(f).read()):
        c = m.group(1)
        if c not in names and c in {n for n in names} | set():
            fail.append(f"{f}: reference to missing skill '{c}'")

for f in ("bootstrap.sh", "install.sh", "validate.sh", "bin/skills",
          "hooks/inject-rules.sh"):
    if os.path.exists(f) and not os.access(f, os.X_OK):
        fail.append(f"{f}: not executable (chmod +x, and commit the mode bit)")

if fail:
    print(f"FAIL ({len(fail)} issue(s))")
    for x in fail: print("  " + x)
    sys.exit(1)
print(f"OK: {len(names)} skills, frontmatter valid, no em or en dashes")
PY
