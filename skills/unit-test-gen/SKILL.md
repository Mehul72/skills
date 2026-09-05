---
name: unit-test-gen
description: >-
  Generate, fix, and maintain unit tests for Go, JS/TS, Python, Java, and C++ projects.
  Carries per-language conventions (naming, mocking, framework choice, run commands), a
  file and function filtering pass, and a defect severity taxonomy. Use when a file or
  package has no tests, when backfilling coverage across several functions, or when an
  existing suite is failing or stale. For one or two obvious cases against code you
  already understand, write them directly instead; this skill is sized for the larger
  job. Trigger on "写单测", "生成单测", "补充测试", "修复测试", "保鲜测试", "提升覆盖率",
  "write/generate/add/fix unit tests", "freshness tests", "improve coverage", or
  "unit test".
allowed-tools:
- Read
- Write
- Edit
- Grep
- Bash
- Glob
metadata:
  version: 1.1.3
---

Not for: judging whether existing tests are any good, or whether a change is ready to ship, which is `code-quality`. This skill generates and fixes tests.

## Is this job big enough for the protocol?

The protocol below has real setup cost: a language prompt of five to six thousand tokens,
a workflow document, and a scratch directory, all read before the first test is written.
That buys consistency across a suite. It is a bad trade for a couple of test cases.

**Write the tests directly, and skip the rest of this document, when:**

- One or two cases against a function whose behavior is already clear from the code
- Adding a case to a suite that already exists, already passes, and has a style to copy
- The user asked a question about testing rather than asking for tests

**Use the protocol when:**

- A file or package has no tests at all
- Coverage work spans more than a few functions, or more than one file
- A suite is failing or stale and finding out why is part of the job
- The user asked for this skill by name

When you skip the protocol, say so in one line before writing, so the choice is visible
and the user can overrule it. When you follow it, follow it in order: the routing in
Step 1 determines which workflow Step 2 reads, so the steps are not independent.

---

## Setup

`SKILL_ROOT` is the directory holding this `SKILL.md`. `PROJECT_ROOT` is the root of the
project under test.

Do these before analysing any source, because the language prompt changes how targets are
extracted:

1. **Detect LANG** from target file extension (`.go`→go, `.py`→python, `.java`→java, `.js/.ts/.tsx`→javascript, `.cpp/.cc/.h`→cpp)
2. **Read** `${SKILL_ROOT}/assets/${LANG}/prompt.md`, internalize language-specific rules
3. **Create a scratch dir** for this run's bookkeeping:
   ```bash
   TMP_ROOT=$(mktemp -d) && mkdir -p "$TMP_ROOT/targets" "$TMP_ROOT/results" && echo "$TMP_ROOT"
   ```
4. **Record `TMP_ROOT`**, all targets/results JSON below is written under it

---

## Execution Protocol

Work as the test generation and maintenance tool. The steps below run in order; sub-steps
marked `[CONDITIONAL]` apply only when their condition holds.

---

## STEP 1: Requirements & Target Analysis

Work through the sub-steps in order.

### 1.1 Gather Context

- [ ] Read `${SKILL_ROOT}/assets/${LANG}/prompt.md` (if not already done in Immediate First Actions)
- [ ] Check for project conventions (`AGENTS.md`, `CLAUDE.md`) in project root → read unit-test-relevant parts if found
- [ ] Determine **MODE**:
  - User said "修复"/"fix"/"跑不过"/"编译失败"/"测试挂了"/"修复单测" → `MODE=fix_only`
  - Otherwise → `MODE=default`
- [ ] Determine **DEFECT_DETECTION**:
  - User said "深度缺陷检测"/"deep defect"/"代码审查"/"code review"/"漏洞检测"/"安全审查" → `DEFECT_DETECTION=deep`
  - Otherwise → `DEFECT_DETECTION=basic`

### 1.2 Environment Setup [SILENT]

> ⚠️ **[SILENT] means: execute but do NOT show output to user. [SILENT] does NOT mean optional.**

- [ ] Confirm `TMP_ROOT` is set to a valid, existing path (created in Immediate First Actions)

### 1.3 Determine Target Functions

- [ ] If user explicitly specified functions/files → use those
- [ ] Else if workspace has uncommitted git changes → extract from those
- [ ] Else if user has a file open in IDE → use that file
- [ ] Else → ASK the user (do not guess)
- [ ] Read `references/target-filter/AGENT.md` → apply file-level filtering rules
- [ ] Extract function signatures per language-specific prompt rules
- [ ] Record: total function count and total file count

### 1.4 Workflow Routing (Hard Rules, NOT Model Judgment)

```
IF (function_count >= 20) OR (file_count >= 8):
    WORKFLOW = "pipeline"
ELSE:
    WORKFLOW = "lite"
```

### 1.5 Gate check

Step 2 reads these; an unset one sends it down the wrong branch. Confirm each before
continuing: `SKILL_ROOT`, `PROJECT_ROOT`, `LANG`, `TMP_ROOT`, `MODE`, `DEFECT_DETECTION`,
`WORKFLOW`.

### 1.6 [CONDITIONAL] Pipeline Setup (only if WORKFLOW=pipeline)

- [ ] Write `${TMP_ROOT}/task.json` with `workflow: "pipeline"`
- [ ] Read language prompt for targets JSON structure
- [ ] Write target function list to `${TMP_ROOT}/targets/` per `references/output-contract/FORMATS.md`

---

## STEP 2: Execute Workflow

**Read the workflow document FIRST, then execute per its instructions:**

- If `WORKFLOW=lite` → Read `references/workflow-lite/AGENT.md` → execute its full flow
- If `WORKFLOW=pipeline` → Read `references/workflow-pipeline/AGENT.md` → execute its full flow (dispatch Writer + Fixer)

### Before writing any test code

- [ ] `TMP_ROOT` exists. If not, go back to Setup
- [ ] The workflow AGENT.md has been read. If not, read it now
- [ ] The file about to change is a test file. Modifying production code here is forbidden, without exception

---

## STEP 3: Output

### 3.1 Artifact check and summary

Follow the output logic in the workflow-specific AGENT.md:

- **pipeline** → Aggregate `final_report.json`, complete artifact check, conversation summary from `results/`
- **lite** → Aggregate `final_report.json`, lite artifact check, conversation summary from `results/`

> Output SHOULD be compact, omit defects section if no defects found.

---

## Hard Constraints

These hold whenever the protocol runs, and when you skip the protocol and write tests
directly. They are about not corrupting the codebase or misreporting results, so no
argument about scale relaxes them.

| # | Constraint | Consequence of Violation |
|---|-----------|------------------------|
| 1 | **Only modify test files**. NEVER modify production code | Entire run is invalid |
| 2 | **No premature completion**. Fix or remove failing tests before finishing | Exceptions: must-skip scenarios; confirmed production defects (default mode only) |
| 3 | **Tool output is truth**, Compile/test pass status is determined ONLY by command output | Subjective inference = violation |
| 4 | **Report what changed**. Finish with the artifact check and summary from Step 3 | Output without a summary = violation |
| 5 | **Conservative defect determination**, Default to test issue; only flag production defect with conclusive evidence | False positives = violation |
| 6 | **[SILENT] ≠ [OPTIONAL]**, Steps marked silent MUST still be executed | Skipping silent steps = violation |

---

## Abnormal Termination

**Immediately terminate** (clean up and exit) if:

1. `TMP_ROOT` cannot be created → Missing environment dependencies
2. Unsupported language detected → Inform user: "Language X is not supported. Supported: Go, Python, Java, JS/TS, C++. You can ask me to generate tests directly without this Skill." → Exit skill (do not block autonomous generation)
3. Cannot identify language → Ask user. If unsupported → rule #2
4. No testable functions found → Inform user and wrap up

---

## Rule Priority

When rules conflict, apply this priority (highest first):

1. User explicit instructions
2. Project unit test conventions
3. Existing test style in the codebase
4. Language-specific rules (`assets/<lang>/prompt.md`)
5. This document

---

## Architecture Reference

```
┌───────────────────────────────────┐
│       Orchestrator (this doc)      │
│       Requirements / Routing       │
└────────────────┬──────────────────┘
                 │
      ┌──────────┴──────────┐
      ▼                     ▼
┌──────────────────┐  ┌──────────────────┐
│   workflow-lite  │  │ workflow-pipeline │
│   Single Agent   │  │ Multi-Agent       │
└──────────────────┘  └────────┬─────────┘
                          ┌────┴────┐
                          ▼         ▼
                      Writer     Fixer
                     (+ Reviewer)
```

---

## Skill Composition (Reference Only. Read On-Demand)

| Path                                         | Purpose |
|----------------------------------------------|---------|
| `assets/<lang>/prompt.md`                    | Language-specific rules and conventions |
| `references/workflow-lite/AGENT.md`          | Lite workflow execution flow |
| `references/workflow-pipeline/AGENT.md`      | Pipeline workflow execution flow |
| `references/test-writer/AGENT.md`            | Test generation agent instructions |
| `references/test-fixer/AGENT.md`             | Test fix agent instructions |
| `references/output-contract/ARTIFACTS.md`    | Artifact checklist |
| `references/output-contract/FORMATS.md`      | JSON format definitions |
| `references/code-reviewer/AGENT.md`          | Deep defect detection (when `DEFECT_DETECTION=deep`) |
| `references/target-filter/AGENT.md`          | File/function filtering rules |
| `references/issue-severity-triage/AGENT.md`  | Defect severity classification (on-demand) |
| `references/issue-severity-triage-refs/build-environment-errors.md` | Severity anchors: build & environment errors (on-demand) |
| `references/issue-severity-triage-refs/completeness-errors.md` | Severity anchors: completeness errors (on-demand) |
| `references/issue-severity-triage-refs/concurrency-resource-errors.md` | Severity anchors: concurrency & resource errors (on-demand) |
| `references/issue-severity-triage-refs/control-flow-errors.md` | Severity anchors: control flow errors (on-demand) |
| `references/issue-severity-triage-refs/data-persistence-errors.md` | Severity anchors: data persistence errors (on-demand) |
| `references/issue-severity-triage-refs/data-type-errors.md` | Severity anchors: data & type errors (on-demand) |
| `references/issue-severity-triage-refs/interface-contract-errors.md` | Severity anchors: interface & contract errors (on-demand) |
| `references/issue-severity-triage-refs/maintainability-issues.md` | Severity anchors: maintainability issues (on-demand) |
| `references/issue-severity-triage-refs/security-vulnerabilities.md` | Severity anchors: security vulnerabilities (on-demand) |

---

## Language Extension

Each `assets/<lang>/prompt.md` MUST provide:

| # | Content | Consumer |
|---|---------|----------|
| 1 | Minimum execution unit definition | Orchestrator |
| 2 | targets/results JSON structure | Orchestrator, Writer, Fixer |
| 3 | Target function extraction method | Orchestrator |
| 4 | Supplementary file filtering rules | Orchestrator |
| 5 | Test file naming/organization conventions | Writer |
| 6 | Mock/assertion framework selection | Writer |
| 7 | Compilation and execution commands | Writer, Fixer |
| 8 | Scheduling strategy (optional) | Orchestrator |

