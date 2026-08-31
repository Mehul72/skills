#!/usr/bin/env bash
# UserPromptSubmit hook. Fires once per turn, before the model sees the prompt.
# stdout is injected as additional context.
#
# Instruction files (AGENTS.md, CLAUDE.md) load once at session start and then
# persist in context. They do not disappear, but attention to them decays over a
# long conversation. This re-states the hardest rules every turn to counter that.
#
# Keep it short. This cost is paid on every single message.

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES="$DIR/session-rules.md"
[ -f "$RULES" ] || exit 0
cat "$RULES"
