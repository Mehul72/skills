# JSON Artifact Format Definitions

This document defines field specifications and complete examples for each intermediate artifact JSON file. All agents **MUST strictly follow** the formats defined here when writing.

## Table of Contents

- [1. task.json](#1-taskjson)
- [2. targets Directory](#2-targets-directory)
- [3. results Directory](#3-results-directory)
- [4. final_report.json](#4-final_reportjson)
- [Write Specifications](#write-specifications)
- [Conversation Output Rules](#conversation-output-rules)

---

## 1. task.json

**Producer**: Orchestrator (Step 1)
**Consumer**: Test Writer, Test Fixer, Code Reviewer
**Applicable workflow**: Pipeline mode only. Lite mode does not generate task.json.

Task-level global configuration, spanning the entire Skill lifecycle.

### Field Descriptions

| Field | Type | Required | Description |
|------|------|:----:|------|
| `lang` | string | ✅ | Project language: `go` / `python` / `java` / `javascript` / `cpp` |
| `mode` | string | ✅ | Execution mode: `fix_only` / `default` |
| `defect_detection` | string | ✅ | Defect detection level: `basic` / `deep` |
| `workflow` | string | ✅ | Workflow mode: `pipeline` (lite mode does not generate this file) |
| `skill_root` | string | ✅ | Absolute path to the Skill root directory |
| `project_root` | string | ✅ | Absolute path to the project root directory |
| `tmp_root` | string | ✅ | Absolute path to the temporary directory |
| `start_time_ms` | number | ✅ | Task start timestamp (milliseconds), used as runtime metadata |

### Example

```json
{
  "lang": "go",
  "mode": "default",
  "defect_detection": "basic",
  "workflow": "pipeline",
  "skill_root": "/path/to/skill",
  "project_root": "/path/to/project",
  "tmp_root": "/tmp/ut_abc123",
  "start_time_ms": 1719800000000
}
```

---

## 2. targets Directory

**Path**: `${TMP_ROOT}/targets/<unit_name>.json`
**Producer**: Orchestrator (Step 1)
**Consumer**: Test Writer, Test Fixer (read-only)
**Applicable workflow**: Pipeline mode only. Lite mode does not generate a targets directory.

Target function list; each file represents **one minimum execution unit**, the granularity of work that one Writer (or Fixer) processes completely. `ls targets/` gives the complete list of execution units.

> The minimum execution unit definition (granularity, file naming rules, internal JSON structure) is declared by the language-specific prompt (`assets/${LANG}/prompt.md`). For example, Go's minimum execution unit is "package", Python may be "single file", Java may be "class".

### Common Conventions

- Each JSON file ultimately contains a `functions` array (which may be nested under language-defined intermediate layers); each function has at least `function` (function name) and `line` (start line number)
- Other fields (e.g., package path, file path, receiver) are defined by the language-specific prompt
- Contains only basic information, **no generation results**

---

## 3. results Directory

**Path**: `${TMP_ROOT}/results/<unit_name>.json`
**File naming**: Mirrors targets (same filename)
**Producer**: Test Writer (creates, status=`generated`/`filtered`) → Test Fixer (updates, status=`passed`/`failed`/`skipped`)
**Consumer**: Test Fixer (reads Writer results), Orchestrator (aggregates for report)

Execution results; file naming corresponds one-to-one with targets. Created by Writer then updated by Fixer, recording each function's complete lifecycle. Internal JSON structure mirrors targets, with status, defects, and other result fields added at the function level.

### status Enum

| Status | Meaning | Set By | Description |
|------|------|--------|------|
| `filtered` | Filtered out | Writer | Does not meet generation conditions; includes `filter_reason` and `filter_reason_detail` |
| `generated` | Generated, pending verification | Writer | Test code generated, awaiting Fixer verification |
| `passed` | Verification passed | Fixer | Test compiles and runs successfully (assertion failures from defect-probing test cases are expected behavior and still count as passed) |
| `failed` | Verification failed | Fixer | Compilation failure / runtime failure / still fails after fixing; includes `error_log` |
| `skipped` | Skipped | Fixer | Cannot test (missing dependencies, environment issues, etc.); includes `reason` |

### Common Function-Level Result Fields

Regardless of how the language organizes the JSON structure, each function's result object contains the following fields:

| Field | Type | Required | Description |
|------|------|:----:|------|
| `function` | string | ✅ | Function name |
| `status` | string | ✅ | Status enum, see table above |
| `reason` | string | ❌ | Reason when `skipped` |
| `filter_reason` | string | ❌ | Filter reason enum when `filtered`: `simple_function` (function too simple to test) / `untestable` (untestable) / `other` |
| `filter_reason_detail` | string | ❌ | Specific filtering description when `filtered` (brief text) |
| `test_file` | string | ❌ | Test file relative path (required when `generated` / `passed` / `failed`) |
| `test_function` | string | ❌ | Test function name (required when `generated` / `passed` / `failed`) |
| `defects` | array | ❌ | List of discovered defects; omit when no defects |
| `defects[].severity` | string | ✅ | Severity: `p0` / `p1` / `p2` / `p3` |
| `defects[].description` | string | ✅ | Defect description |
| `defects[].evidence` | string | ✅ | Specific evidence description of the defect (filled by Writer during analysis) |
| `defects[].bug_type` | string | ✅ | Defect type enum: `Logic Errors` / `Boundary Errors` / `Error Handling` / `Concurrency` / `Resource` / `Security` / `Business Gaps` / `Other Type` |
| `defects[].bug_range` | [][]int | ✅ | Defect location in business source code, format: `[[start_line, start_col, end_line, end_col]]` |
| `defects[].file_path` | string | ✅ | Business source file path (relative to `PROJECT_ROOT`) |
| `defects[].target_func` | string | ✅ | Target function name under test |
| `defects[].expect_outcome` | string | ✅ | Expected test execution result description |
| `defects[].location` | string | ✅ | Code location (e.g., `line 30-33`) |
| `defects[].scenario` | string | ✅ | Test scenario name that exposes this defect |
| `error_log` | string | ❌ | Error log when `failed` |

> The specific JSON outer structure (how to organize file and function hierarchy) is defined by the language-specific prompt and remains consistent with targets.

---

## 4. final_report.json

**Producer**: Orchestrator / Main Agent (Step 3, aggregated from results)
**Consumer**: Orchestrator / Main Agent (Step 3 conversation display)
**Applicable workflow**: Pipeline mode and lite mode.

The Orchestrator / Main Agent iterates through all files under `results/` and generates a lightweight final report containing only run-level summary fields. Test-file and defect details remain in `results/` and MUST NOT be copied into `final_report.json`.

### Field Descriptions

| Field | Type | Required | Description |
|------|------|:----:|------|
| `gen_success` | boolean | ✅ | Whether this unit-test generation run succeeded. If this run generated or modified test cases in code files, set this to `true` |
| `summary` | string | ✅ | Final generation summary as a **plain-text sentence** (MUST be a string, MUST NOT be a JSON object or structured data). Example: `"Generated 2 test files and 10 cases with 90% pass rate; found 1 p0 defect"` |
| `failed_reason` | string | ✅ | Main failure reason summary. If `gen_success=false`, this MUST be a non-empty string; if successful, use an empty string. Assertion failures caused by discovered production defects do not count as generation failure |

### Example

```json
{
  "gen_success": true,
  "summary": "Generated 2 test files and 10 cases with 90% pass rate; found 1 p0 defect",
  "failed_reason": ""
}
```

---

## Conversation Output Rules

The Orchestrator / Main Agent reads `final_report.json` in Step 3 for the run-level status and summary, then aggregates test-file and defect details from `results/` for conversation display. `final_report.json` is summary-only and MUST NOT be used as the source for test-file or defect details.

### Display Template

```
### Test Generation Summary

**Test Files**:

| File | Cases | Passed | Failed |
|------|:------:|:----:|:----:|
| `service/user/auth_test.go` | 6 | 5 | 1 |
| `service/user/profile_test.go` | 4 | 4 | 0 |

**Defects Found**: 1

1. 🔴 **p0** `service/user/auth.go:30-33`
   In the Login function, user field is accessed after err != nil; error judgment direction is reversed
   Exposing test case: `TestLogin/valid_credentials_returns_token_normally`
```

### Display Rules

1. Build the test files table and defects section from `results/`, not from `final_report.json`
2. Defects with `severity` of `p3` are not displayed in the conversation (unless explicitly requested by the user)
3. Omit the defects section if no defects are found; only display the test files table
4. Defects are sorted by severity descending (p0 → p1 → p2)
5. Severity markers: 🔴 p0/p1, 🟡 p2

---

## Write Specifications

1. **Encoding**: UTF-8, no BOM
2. **Formatting**: Use indented formatted JSON when writing (2-space indent) for debugging and manual inspection
3. **Empty arrays**: For artifact schemas that define array fields, write empty array `[]` when no data; do not omit the field
4. **Paths**: All file paths are relative to `PROJECT_ROOT`
5. **Write permissions** (pipeline mode): `targets/` directory is written only by the Orchestrator; `results/` directory is created by Writer and updated by Fixer; `final_report.json` is aggregated from results by the Orchestrator in Step 3
6. **Write permissions** (lite mode): `results/` directory and `final_report.json` are written by the main agent in Step 3
7. **File naming**: File naming rules for targets and results are defined by the language-specific prompt; both directories maintain consistent naming
