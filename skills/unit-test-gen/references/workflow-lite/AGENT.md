---
name: workflow-lite
description: Lite Workflow, Single-agent lightweight mode, suitable for quick generation of a small number of local functions. No multi-agent dispatching, no targets directory or task.json. Generation and verification are completed directly within the main agent.
---

# Lite Workflow

This document defines the execution flow for **lite mode**. When the Orchestrator determines `workflow = lite`, it reads this document and executes accordingly.

Lite mode is a single-agent direct-output mode. It does not use multi-agent orchestration, does not write task.json or targets directory. The main agent directly completes test generation (or fixing) and verification, producing results JSON and final_report.json as the final output.

## Table of Contents

- [Preconditions](#preconditions)
- [Knowledge Loading](#knowledge-loading)
- [Execution Flow](#execution-flow)
  - [Step 2: Direct Generation and Verification](#step-2-direct-generation-and-verification)
  - [Step 3: Artifact Check and Output Summary](#step-3-artifact-check-and-output-summary)
- [Key Differences from Pipeline Mode](#key-differences-from-pipeline-mode)

---

## Preconditions

The following conditions have been completed by the Orchestrator (SKILL.md Step 1) before entering this workflow:

- Environment setup complete (TMP_ROOT created)
- Language-specific prompt determined (`assets/${LANG}/prompt.md`)
- Target function list determined (in memory, not written to targets directory)
- `MODE` (`default` / `fix_only`) and `DEFECT_DETECTION` (`basic` / `deep`) determined
- The following variables are available: `SKILL_ROOT`, `PROJECT_ROOT`, `TMP_ROOT`, `LANG`, `MODE`, `DEFECT_DETECTION`

---

## Knowledge Loading

In lite mode, documents are read **on-demand**. Do not read everything at the start. Each step specifies which documents to read:

| # | Document | When to Read | Content to Obtain |
|---|------|---------|---------|
| 1 | `assets/${LANG}/prompt.md` | Before Step 2 starts (during pre-check) | Language-specific rules: test conventions, mock framework, compile/run commands, code style, pre-check requirements, results JSON structure |
| 2 | `references/test-writer/AGENT.md` | When generating tests | Generation strategy: strategy decisions, defect discovery, assertion & scenario naming conventions, hard constraints |
| 3 | `references/test-fixer/AGENT.md` | When performing verify-and-fix | Verify-and-fix strategy: verify-and-fix loop, failure triage flow, fix strategy, reflection mechanism, exit conditions |
| 4 | `references/code-reviewer/AGENT.md` | Only when `DEFECT_DETECTION=deep` | Deep defect mining checklist |
| 5 | `references/issue-severity-triage/AGENT.md` | Only when defects are found | Three-dimension classification flow (Impact Severity × Blast Radius × Trigger Probability → P0-P3) |
| 6 | `references/issue-severity-triage-refs/<category>.md` | Only when classification needs cross-validation; read the single file matching `bug_type` | P0-P3 anchors and secondary sub-categories for that category |

> In lite mode, there is no distinction between Writer/Fixer/Reviewer agent roles, but the rules and constraints defined in the corresponding documents MUST be **followed**.

---

## Execution Flow

### Step 2: Direct Generation and Verification

Do not write to the targets directory or dispatch subagents. Complete the work directly in the main agent based on `MODE`:

#### default Mode

For each function in the target function list:

1. **Pre-check**: Read `assets/${LANG}/prompt.md` and complete environment detection and project test pattern learning per the language-specific prompt's requirements (execute once for the first function)
2. **Context analysis**: Read the target function source code and its dependency context (see the context analysis requirements in the language-specific prompt)
3. **Generate tests**: Read `references/test-writer/AGENT.md` and generate test code per its workflow
   - Execute generation strategy decision (no existing tests → generate from scratch; existing tests → incremental supplement)
   - Perform defect discovery (basic mode: natural discovery; deep mode: read `references/code-reviewer/AGENT.md` and systematically review per the checklist)
   - Generate test code and write to the test file
4. **Verify-and-fix**: Read `references/test-fixer/AGENT.md` and verify/fix per its workflow
   - Execute the compile check → run tests → failure triage → fix loop
   - Follow the verify-and-fix round limit defined in the language-specific prompt
   - Follow the Fixer's failure triage flow and defect determination criteria

> Steps 3-4 above are organized per the minimum execution unit granularity defined in the language-specific prompt. For example, Go uses packages as units, functions within the same package are generated individually first, then compiled and verified/fixed together.

#### fix_only Mode

Skip the generation step; directly perform verify-and-fix on existing tests for the target functions:

1. **Pre-check**: Read `assets/${LANG}/prompt.md`, same as default mode
2. **Locate existing tests**: Find existing test files and test functions corresponding to target functions
3. **Verify-and-fix**: Read `references/test-fixer/AGENT.md` and verify/fix per its workflow

---

### Step 3: Artifact Check and Output Summary


1. **Write results JSON** (one-time write): After all target functions' generation and verify-and-fix are complete, write execution results in one batch to `${TMP_ROOT}/results/<unit_name>.json`. The JSON structure is consistent with the results format defined in the language-specific prompt, containing function-level fields such as `status`, `test_file`, `test_function`, `defects` (field definitions in `references/output-contract/FORMATS.md`).

2. **Aggregate final_report.json**: Iterate through all JSON files under `${TMP_ROOT}/results/` and generate the summary-only `${TMP_ROOT}/final_report.json` (format in `references/output-contract/FORMATS.md` §4). The `summary` field MUST be a **plain-text string** (e.g., `"Generated 1 test file covering 3 functions with 100% pass rate"`), MUST NOT be a JSON object or structured data. Test-file and defect details remain in `results/`.

3. **Perform lite artifact check**: Check `${TMP_ROOT}/results/` and `${TMP_ROOT}/final_report.json` according to the lite-mode rules in `references/output-contract/ARTIFACTS.md`. If `final_report.json` has `gen_success=false`, no new or modified test files are required, but `failed_reason` MUST be a non-empty string.

4. **Conversation output summary**: Read `final_report.json` for run-level status and summary, aggregate test-file and defect details from `results/`, and provide a concise conversation summary organized by test file dimension. See the "Conversation Output Rules" in `references/output-contract/FORMATS.md` for display rules.

    > Output SHOULD be compact, omit the defects section if no defects are found.

---

## Key Differences from Pipeline Mode

| Dimension | Lite | Pipeline |
|------|------|----------|
| Agent architecture | Single agent completes directly | Orchestrator dispatches Writer + Fixer |
| task.json | Not needed | Required |
| targets/ directory | Not needed | Required |
| results/ directory | Required | Required |
| final_report.json | Required | Required |
| Artifact check | Check results + final_report.json | Full artifact check (see ARTIFACTS.md) |
