---
name: workflow-pipeline
description: Pipeline Workflow, Multi-agent orchestration mode, suitable for large-scale batch generation scenarios. The Orchestrator dispatches Test Writer and Test Fixer subagents, processing execution units serially, and producing a complete chain of intermediate artifacts.
---

# Pipeline Workflow

This document defines the complete execution flow for **pipeline mode**. When the Orchestrator determines `workflow = pipeline`, it reads this document and executes accordingly.

Pipeline mode uses a multi-agent orchestration architecture. The Orchestrator dispatches Test Writer and Test Fixer subagents, producing a complete chain of intermediate artifacts (targets/ → results/ → final_report.json).

## Table of Contents

- [Preconditions](#preconditions)
- [Architecture](#architecture)
- [Execution Flow](#execution-flow)
  - [Step 2: Execute Language-Specific Task Pipeline Per Requirements](#step-2-execute-language-specific-task-pipeline-per-requirements)
  - [Step 3: Artifact Check and Output Summary](#step-3-artifact-check-and-output-summary)

---

## Preconditions

The following conditions have been completed by the Orchestrator (SKILL.md Step 1) before entering this workflow:

- `${TMP_ROOT}/task.json` has been written (with `workflow: "pipeline"`)
- `${TMP_ROOT}/targets/` directory has been created, containing the target function list
- Language-specific prompt determined (`assets/${LANG}/prompt.md`)
- `MODE` (`default` / `fix_only`) and `DEFECT_DETECTION` (`basic` / `deep`) determined

---

## Architecture

```
                  ┌───────────────────────────────────┐
                  │       Orchestrator (SKILL.md)      │
                  │       Analysis / Dispatch / Report │
                  └────────────────┬──────────────────┘
                                   │ Dispatch per scenario, per unit
                       ┌───────────┴───────────┐
                       ▼                       ▼
    ┌────────────────────────────┐  ┌────────────────────────────┐
    │        Test Writer         │  │        Test Fixer          │
    │        (Generate tests)    │  │        (Verify-and-fix)    │
    │                            │  │                            │
    │   ┌────────────────────┐   │  │                            │
    │   │   Code Reviewer    │   │  │                            │
    │   │   (Optional, dual) │   │  │                            │
    │   └────────────────────┘   │  │                            │
    │                            │  │                            │
    └────────────────────────────┘  └────────────────────────────┘
```

---

## Execution Flow

### Step 2: Execute Language-Specific Task Pipeline Per Requirements

Combine the language-specific rules in `assets/${LANG}/prompt.md` to execute the corresponding pipeline based on `MODE`.

Iterate through all files under `${TMP_ROOT}/targets/` (`ls targets/`); each file represents one minimum execution unit. By default, process units **serially one by one**:

**`default`**: For each execution unit, first dispatch Test Writer to generate tests and write to `${TMP_ROOT}/results/<unit_name>.json`, then dispatch Test Fixer to verify/fix and update the same file. Only proceed to the next unit after the current unit's Writer + Fixer are both complete.

**`fix_only`**: Skip Test Writer. For each execution unit, directly dispatch Test Fixer to read `${TMP_ROOT}/targets/<unit_name>.json`, verify/fix existing tests, and write results to `${TMP_ROOT}/results/<unit_name>.json` per the results specification.

> The language-specific prompt can override the default serial strategy and define a more efficient scheduling approach. For example, Go's prompt defines a "serial by package, per-file Writer within a package → unified Fixer" strategy.
> For detailed workflows of each agent, see `references/test-writer/AGENT.md` and `references/test-fixer/AGENT.md`.

---

### Step 3: Artifact Check and Output Summary


1. Aggregate from `results/` to generate the summary-only `${TMP_ROOT}/final_report.json` (format in `references/output-contract/FORMATS.md` §4). The `summary` field MUST be a **plain-text string** (e.g., `"Generated 3 test files covering 8 functions with 87% pass rate; found 2 defects"`), MUST NOT be a JSON object or structured data. Then verify artifact file completeness per the check flow in `references/output-contract/ARTIFACTS.md`.

2. Read `final_report.json` and provide a **concise** summary in the conversation organized by test file dimension. See the "Conversation Output Rules" in `references/output-contract/FORMATS.md` for display rules.

    > Output SHOULD be compact, omit the defects section if no defects are found.
