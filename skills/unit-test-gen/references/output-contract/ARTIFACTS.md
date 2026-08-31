# Skill Artifact Checklist and Check Rules

This document defines the files that **MUST be produced** after each execution of the unit-test-gen Skill. Artifact requirements differ by workflow mode (`lite` / `pipeline`).

## Table of Contents

- [Artifact Overview](#artifact-overview)
- [Artifact Matrix by Workflow and Mode](#artifact-matrix-by-workflow-and-mode)
- [Orchestrator Artifact Check Flow](#orchestrator-artifact-check-flow)
- [Artifact Retention and Cleanup](#artifact-retention-and-cleanup)
- [JSON Format Specification](#json-format-specification)

---

## Artifact Overview

All intermediate artifacts are stored under `${TMP_ROOT}/`; test files are written to the corresponding directory in `${PROJECT_ROOT}`.

| # | Artifact | Path | Producer | pipeline | lite | Description |
|---|------|------|--------|:--------:|:----:|------|
| 1 | `task.json` | `${TMP_ROOT}/task.json` | Orchestrator | ✅ |, | Task-level global configuration (lang, mode, workflow, etc.) |
| 2 | `targets/` directory | `${TMP_ROOT}/targets/<unit_name>.json` | Orchestrator | ✅ |, | Target function list (one file per minimum execution unit) |
| 3 | `results/` directory | `${TMP_ROOT}/results/<unit_name>.json` | Writer → Fixer / Main Agent | ✅ | ✅ | Execution results (status, defects, etc.) |
| 4 | `final_report.json` | `${TMP_ROOT}/final_report.json` | Orchestrator / Main Agent | ✅ | ✅ | Summary-only report aggregated from results |
| 5 | Test files | `${PROJECT_ROOT}/.../*_test.*` | Writer + Fixer / Main Agent | ✅ | Conditionally required* | At least one test file created or modified |

---

## Artifact Matrix by Workflow and Mode

### Pipeline Mode

| Artifact | fix_only | default |
|------|:--------:|:-------:|
| `task.json` | ✅ | ✅ |
| `targets/` directory | ✅ | ✅ |
| `results/` directory | ✅ (status only) | ✅ (with defects) |
| `final_report.json` | ✅ | ✅ |
| Test files | ✅ (modified) | ✅ (new/modified) |

### Lite Mode

| Artifact | fix_only | default |
|------|:--------:|:-------:|
| `results/` directory | ✅ (status only) | ✅ (with defects) |
| `final_report.json` | ✅ | ✅ |
| Test files | Conditionally required* (modified) | Conditionally required* (new/modified) |

> `*` In lite mode, if `final_report.json` has `gen_success=false`, the run may produce no new or modified test files. In that case, `failed_reason` MUST be a non-empty string.

---

## Orchestrator Artifact Check Flow

### Pipeline Mode

Before outputting the report in Step 3, the Orchestrator SHOULD perform the following checks:

```
1. Confirm ${TMP_ROOT}/task.json exists and is non-empty
2. Confirm ${TMP_ROOT}/targets/ directory exists and contains at least one .json file
3. Confirm ${TMP_ROOT}/results/ directory exists and contains at least one .json file
4. Check based on MODE:
   - If MODE = default:
     - Confirm at least one function in results/ has status of generated / passed / failed (Writer has generated)
5. Confirm ${TMP_ROOT}/final_report.json exists and is non-empty
6. Read final_report.json:
   - Confirm gen_success is a boolean
   - Confirm summary is a string
   - If gen_success = false, confirm failed_reason is a non-empty string
7. If gen_success = true, confirm results/ contains at least one function with status `generated` / `passed` / `failed` and a valid `test_file` field
```

### Lite Mode

```
1. Confirm ${TMP_ROOT}/results/ directory exists and contains at least one .json file
2. Confirm ${TMP_ROOT}/final_report.json exists and is non-empty
3. Read final_report.json:
   - If gen_success = true:
     - Confirm at least one test file has been created or modified
     - Confirm results/ contains at least one function with status `generated` / `passed` / `failed` and a valid `test_file` field
   - If gen_success = false:
     - Allow no new or modified test files
     - Confirm failed_reason is a non-empty string
```

If any required artifact is missing:
- Mark `⚠️ Incomplete artifacts` in the output report and list the missing files
- Still output available information (extract from existing artifacts as much as possible)

---

## Artifact Retention and Cleanup

- The `${TMP_ROOT}` directory is **not proactively cleaned up** after Skill execution completes, to facilitate subsequent packaging and uploading
- Packaging scope: all `.json` files under `${TMP_ROOT}/` (including `targets/` and `results/` subdirectories)
- The Orchestrator SHOULD inform the actual `TMP_ROOT` path at the end of the output report, enabling external tools to locate artifacts

---

## JSON Format Specification

For detailed format definitions, field descriptions, and complete examples of each JSON file, see `references/output-contract/FORMATS.md`.
