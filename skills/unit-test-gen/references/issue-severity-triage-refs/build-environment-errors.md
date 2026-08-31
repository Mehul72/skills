# Build & Environment Errors, P0-P3 Triage Rules

> This file is a referenced rule file for the `issue-severity-triage` Skill.
> It covers P0-P3 triage criteria (combining consequence severity, blast radius, and trigger probability) for **build and environment problems** (2 sub-categories).
>
> **How to use this file:**
> 1) First complete the independent three-dimension assessment (SKILL.md §5) and table lookup (§6) to determine the preliminary priority.
> 2) Use this reference to cross-validate: find the closest sub-category and Typical Profile row below.
> 3) If the independent assessment differs from the reference anchor, explain the reason in the 【分类与参考验证】section.

---

## Syntax / Compilation Errors

| Priority | Typical Profile | Description | Example |
| --- | --- | --- | --- |
| **P0** | Catastrophic × Broad × Certain | Broken basic syntax or compilation prerequisites; structurally sits on the global build path blocking all downstream workflows, the code cannot compile, package, or deploy. | `if (x > 0 { ... }`, missing a closing parenthesis. |
| **P1** | Severe × Module × Likely | Violates compilation, static checking, or quality gates enforced in the repository; structurally scoped within a module but the affected gate blocks the integration pipeline, persistently causes the change to fail at the integration stage, blocking delivery. | A function exceeds 100 lines, violating Linter rules enforced as build gate. |
| **P2** | Limited × Local × Unlikely | Compile-time noise, static check warnings, or secondary defects in build configuration; structurally limited to specific code paths not on a core business flow, may not block running but masks effective signals and affects troubleshooting efficiency. | `import "fmt"` but the `fmt` package is not used. |
| **P3** | Minor × Contained × Rare | Format, style, or writing convention inconsistencies; no active business path is affected, does not change runtime results. | Using Tab instead of spaces for indentation, or inconsistent brace newline style. |

---

## Dependency / Version Management Errors

| Priority | Typical Profile | Description | Example |
| --- | --- | --- | --- |
| **P0** | Catastrophic × Broad × Certain | Basic dependency closure or build toolchain prerequisites are broken; structurally sits on the global build/startup path affecting all branches and CI runs, no deployable artifacts can be produced, blocking all downstream workflows. | `package-lock.json` is corrupted or severely inconsistent with `package.json`, causing `npm install` to fail on every CI run. |
| **P1** | Severe × Module × Likely | Version conflicts, ABI/API incompatibility, or transitive dependency drift in important dependencies; structurally scoped within a module but the affected path serves an important feature, under normal startup or common operations it persistently throws exceptions causing important capabilities to be unavailable. | Two libraries in `pom.xml` depend on different incompatible versions of the same transitive dependency, causing `ClassNotFoundException` on the payment module's startup path. |
| **P2** | Limited × Local × Unlikely | Code, scripts, or configurations depend on specific local environments, directory structures, or platform differences; structurally limited to specific deployment paths not on core business flows, only manifests in specific deployment targets under certain conditions, with production and primary development environments unaffected. | Hardcoded local file path `/Users/user/data.csv` in a seed data loader, which only fails when running outside the original developer's machine. |
| **P3** | Minor × Contained × Rare | Dependency declarations, lock files, or tool configurations are not clean or self-explanatory; no active build or business path is affected, impact is confined to increased upgrade and troubleshooting costs with no runtime effect. | An `indirect` dependency exists in `go.mod` but no code uses it anymore. |

---

## Triage Examples

### Example 1: Corrupted lock file causes complete CI build failure → P0

**Defect**: `package-lock.json` is severely inconsistent with `package.json`; `npm install` exits with an error in the CI environment.

```
npm ERR! Invalid: lock file's @vue/compiler-sfc@3.4.0 does not satisfy @vue/compiler-sfc@^3.5.0
```

| Dimension | Verdict | Evidence |
| :--- | :--- | :--- |
| Impact Severity | **Catastrophic** | The build pipeline fails completely; no deployable artifacts can be produced (build failure → Catastrophic) |
| Blast Radius | **Broad** | Affects the entire repository's CI/CD pipeline; builds on all branches and PRs fail, structurally this is a global initialization path that blocks all downstream workflows |
| Trigger Probability | **Certain** | Any `npm install` execution immediately errors out (matches signal ② exposed at build stage) |

**Priority**: Critical impact (Catastrophic × Broad) × Certain → **P0**, block merge.

---

### Example 2: Hardcoded local file path in code → P2

**Defect**: `utils/data_loader.go:15`, The data-loading function hardcodes a developer's local path.

```go
func LoadSeedData() ([]byte, error) {
    return os.ReadFile("/Users/dev/data/seed.csv")
}
```

| Dimension | Verdict | Evidence |
| :--- | :--- | :--- |
| Impact Severity | **Severe** | The feature is completely unavailable in all environments other than the developer's local machine (CI, staging, production) (persistent feature failure → Severe) |
| Blast Radius | **Local** | Only a single call site `LoadSeedData` is affected; no shared state or external side effects involved; not on a core business path |
| Trigger Probability | **Unlikely** | Only triggered in specific deployment scenarios that require loading seed data; works fine in the development environment (matches signal ⑨ multiple conditions must hold simultaneously) |

**Priority**: Medium impact (Severe × Local) × Unlikely → **P2**, merge with follow-up issue.
