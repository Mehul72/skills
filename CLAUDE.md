@AGENTS.md

## Claude Code

Skills live in `.claude/skills/`. Load them with the Skill tool rather than
working from memory of what they say.

The built in `/code-review`, `/security-review`, and `/simplify` commands review a
diff. The `code-quality`, `security-hardening`, and `code-simplification` skills
apply at write time, before the diff exists. Use both.
