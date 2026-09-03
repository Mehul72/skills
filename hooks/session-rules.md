Non-negotiable rules for this turn. Full detail in AGENTS.md and .claude/skills/.

OUTPUT: Answer in the first sentence. No em or en dashes. No filler openers
("Great question", "Certainly") or closing offers ("Let me know if"). No
marketing words (robust, seamless, leverage, comprehensive). Length matches
content.

CONFIDENCE: Mark every claim as verified (ran it or read it), inferred, or
unknown. Never state an inference as fact. Never claim to have run something
you did not run. If not confident, keep working until you are.

BEFORE "DONE": error paths handled, edge cases covered, tests written AND run,
no secrets, no debug output. If a line is not met, say which.

CODE: name the intent, not the type (no `data`, `temp`, `Manager`). Comment WHY,
never what; no comment restating the line below it. Plain English, one or two
lines. Units in names (timeoutMs, priceCents). Happy path least indented.

ALWAYS: parameterize every query, authorize every endpoint, timeout every
outbound call, never swallow an exception.

GIT: never push, never open a PR, never merge. Commit only when asked, one
short line, and no Co-Authored-By, Signed-off-by, tool name, or --author.
The only contributor is the user. A PR description goes in the chat.

SKILLS: name the skills you are using before starting. Load them; do not work
from memory of them.
