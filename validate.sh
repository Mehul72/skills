#!/usr/bin/env bash
# Check every skill before committing or installing.
#
#   ./validate.sh
#
# Catches: frontmatter that no YAML parser will accept (a plain scalar containing
# ": " is the common one, and it makes the skill fail to load), frontmatter mangled
# by a markdown formatter (a closing `---` read as a Setext heading underline
# rewrites `name:` into `## name:`), name/directory mismatch, em and en dashes, and
# cross-references to skills that do not exist.

set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 - <<'PY'
import glob, os, re, shutil, subprocess, sys

fail = []
names = {os.path.basename(os.path.dirname(p)) for p in glob.glob("skills/*/SKILL.md")}
blocks = {}   # path -> frontmatter text, for the real parser pass

def scalar_hazards(fm, path):
    """A plain (unquoted) YAML scalar cannot contain ': ' or ' #', and cannot end in
    ':'. Descriptions here are long prose and hit all three, so they are written as
    folded block scalars. A regex-only check misses this and the skill silently
    fails to load."""
    out = []
    for i, line in enumerate(fm.split("\n"), start=2):
        m = re.match(r"^([A-Za-z0-9_-]+):[ \t]+(\S.*)$", line)
        if not m:
            continue
        key, val = m.groups()
        if val[0] in "\"'" or re.match(r"^[>|][-+]?[0-9]*$", val):
            continue          # quoted or a block scalar header, both fine
        if ": " in val or val.endswith(":"):
            out.append(f"{path}:{i}: '{key}' is a plain scalar containing ': ', which "
                       f"no YAML parser accepts. Write it as '{key}: >-' with the text "
                       f"indented on the following lines")
        elif " #" in val:
            out.append(f"{path}:{i}: '{key}' is a plain scalar containing ' #', which "
                       f"starts a YAML comment. Write it as '{key}: >-'")
    return out

for p in sorted(glob.glob("skills/*/SKILL.md")):
    d = os.path.basename(os.path.dirname(p))
    t = open(p).read()
    if not t.startswith("---\n"):
        fail.append(f"{p}: missing opening ---"); continue
    m = re.match(r"^---\n(.*?)\n---\n", t, re.S)
    if not m:
        fail.append(f"{p}: missing closing --- (markdown formatter may have eaten it)"); continue
    fm = m.group(1)
    blocks[p] = fm
    if re.search(r"^##\s+\w+:", fm, re.M):
        fail.append(f"{p}: frontmatter key rewritten as a heading")
    n = re.search(r"^name:\s*(\S+)", fm, re.M)
    if not n:
        fail.append(f"{p}: no name")
    elif n.group(1) != d:
        fail.append(f"{p}: name '{n.group(1)}' does not match directory '{d}'")
    if not re.search(r"^description:\s*\S", fm, re.M):
        fail.append(f"{p}: no description")
    fail.extend(scalar_hazards(fm, p))

# References and agent definitions carry frontmatter too, and break the same way.
for p in sorted(glob.glob("skills/**/*.md", recursive=True)):
    if p in blocks: continue
    t = open(p).read()
    if not t.startswith("---\n"): continue
    m = re.match(r"^---\n(.*?)\n---\n", t, re.S)
    if not m:
        fail.append(f"{p}: opens with --- but has no closing ---"); continue
    blocks[p] = m.group(1)
    fail.extend(scalar_hazards(m.group(1), p))

# Parse for real, with whatever parser this machine has. The heuristic above exists
# for the machine that has neither.
parser = None
try:
    import yaml
    parser = "PyYAML"
    for p, fm in blocks.items():
        try:
            got = yaml.safe_load(fm)
        except Exception as e:
            fail.append(f"{p}: YAML: {str(e).splitlines()[0]}"); continue
        if p.endswith("/SKILL.md") and not (got or {}).get("description", "").strip():
            fail.append(f"{p}: description parses as empty")
except ImportError:
    if shutil.which("ruby"):
        parser = "ruby"
        RUBY = r'''
require "yaml"
ARGV.each do |p|
  m = File.read(p).match(/\A---\n(.*?)\n---\n/m)
  next unless m
  begin
    y = YAML.safe_load(m[1])
    d = y.is_a?(Hash) ? y["description"].to_s : ""
    puts "#{p}\tdescription parses as empty" if d.strip.empty? && p.end_with?("/SKILL.md")
  rescue => e
    puts "#{p}\tYAML: #{e.message.lines.first.strip}"
  end
end
'''
        r = subprocess.run(["ruby", "-E", "UTF-8", "-e", RUBY, *sorted(blocks)],
                           capture_output=True, text=True)
        for line in r.stdout.splitlines():
            path, _, msg = line.partition("\t")
            fail.append(f"{path}: {msg}")
        if r.returncode != 0 and r.stderr.strip():
            fail.append(f"ruby: {r.stderr.strip().splitlines()[0]}")

files = glob.glob("skills/**/*.md", recursive=True)
files += [f for f in ("README.md", "AGENTS.md", "CLAUDE.md",
                      "hooks/session-rules.md") if os.path.exists(f)]
for f in files:
    t = open(f).read()
    for ch, label in (("—", "em dash"), ("–", "en dash")):
        if ch in t:
            line = t[:t.index(ch)].count("\n") + 1
            fail.append(f"{f}:{line}: {label} (response-style bans these)")

# A skill named in prose but not on disk loads as nothing, and the routing table in
# AGENTS.md is entirely such names. The trigger words are the ones this library uses to
# introduce a skill; "and" is not among them, because it introduces list items and a run
# of HTML attributes reads exactly like a reference. Checked against the corpus: dropping
# it loses no real match and removes the only false positive.
for f in sorted(glob.glob("skills/*/SKILL.md")) + ["AGENTS.md"]:
    if not os.path.exists(f): continue
    t = open(f).read()
    # Case-insensitive: "See `observability`" starts six sentences in this library, and a
    # case-sensitive trigger silently skipped every one of them.
    for m in re.finditer(r"(?:use|see|is|to|in|through) `([a-z]+(?:-[a-z]+)+)`", t, re.I):
        c = m.group(1)
        if c not in names:
            fail.append(f"{f}:{t[:m.start()].count(chr(10)) + 1}: "
                        f"reference to a skill that does not exist: '{c}'")

# Every backticked name in an AGENTS.md table row is a skill name: the routing and
# escalation tables hold nothing else. This is the case that matters most, since those
# tables are how an agent decides what to load, and it is the one the prose rule above
# cannot reach, both because a table cell has no trigger word and because the prose
# pattern requires a hyphen, which single-word skills like `grilling` do not have.
if os.path.exists("AGENTS.md"):
    row_name = re.compile(r"`([a-z][a-z0-9]*(?:-[a-z0-9]+)*)`")
    for i, line in enumerate(open("AGENTS.md").read().split("\n"), start=1):
        if not line.lstrip().startswith("|"): continue
        for c in row_name.findall(line):
            if c not in names:
                fail.append(f"AGENTS.md:{i}: routing table names a skill "
                            f"that does not exist: '{c}'")

for f in ("bootstrap.sh", "install.sh", "validate.sh", "test-install.sh",
          "bin/skills", "hooks/inject-rules.sh"):
    if os.path.exists(f) and not os.access(f, os.X_OK):
        fail.append(f"{f}: not executable (chmod +x, and commit the mode bit)")

if fail:
    print(f"FAIL ({len(fail)} issue(s))")
    for x in fail: print("  " + x)
    sys.exit(1)
checked = f"parsed by {parser}" if parser else "no YAML parser found, heuristic only"
print(f"OK: {len(names)} skills, {len(blocks)} frontmatter blocks valid ({checked}), "
      f"no em or en dashes")
PY
