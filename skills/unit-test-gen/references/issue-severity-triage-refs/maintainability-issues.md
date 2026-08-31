# Maintainability Issues, P0-P3 Triage Rules

> This file is a referenced rule file for the `issue-severity-triage` Skill.
> It covers P0-P3 triage criteria (combining consequence severity, blast radius, and trigger probability) for **code maintainability problems** (naming/spelling, hardcoded non-secret values, logging/comments/docs, testing/debugging, 4 sub-categories).
>
> **How to use this file:**
> 1) First complete the independent three-dimension assessment (SKILL.md §5) and table lookup (§6) to determine the preliminary priority.
> 2) Use this reference to cross-validate: find the closest sub-category and Typical Profile row below.
> 3) If the independent assessment differs from the reference anchor, explain the reason in the 【分类与参考验证】section.
>
> **Note**: Credential / secret exposure (hardcoded passwords, keys, tokens) has been moved to [security-vulnerabilities.md](./security-vulnerabilities.md). This file only covers non-secret hardcoded values.

---

## Naming / Spelling / Punctuation Errors

| Priority | Typical Profile | Description | Example |
| --- | --- | --- | --- |
| **P2** | Limited × Local × Unlikely | Names, identifiers, or copy semantics are severely misleading, sufficient to stably induce incorrect understanding in extensions, reuse, or troubleshooting; structurally the affected symbol is an exported interface or shared within a module, but not on a core business path, does not directly constitute a runtime failure currently, but brings real risks to local feature evolution. | A function named `isValid()` actually performs a data deletion operation. |
| **P3** | Minor × Contained × Rare | Non-standard naming, spelling errors, inconsistent capitalization, or inconsistent punctuation style; no active business path is affected, mainly affects readability and consistency without changing runtime results. | Variable named `usr` instead of `user`, or `calculateprice` instead of `calculatePrice`. |

---

## Hardcoded Non-Secret Values in Code

> For hardcoded credentials / secrets / keys, see [security-vulnerabilities.md → Credential / Secret Exposure](./security-vulnerabilities.md).

| Priority | Typical Profile | Description | Example |
| --- | --- | --- | --- |
| **P1** | Severe × Module × Likely | Important environment configurations, critical external dependencies, or key access parameters are hardcoded in business code; structurally scoped within a module but the affected configuration path serves important features, persistently causes important features to be unavailable or significantly increases delivery risk during deployment or environment switching. | Directly hardcoding `http://service-a.prod.internal` in the code instead of obtaining the service address through a configuration center. |
| **P2** | Limited × Local × Unlikely | Business rule thresholds, policy parameters, or local configurations are scattered as hardcoded values; structurally limited to specific code paths not on core business flows, when rules change causes local behavior inconsistency or configuration drift, but fallback mechanisms limit the impact. | The risk control pass threshold `5` is scattered hardcoded in multiple service methods, making it prone to missing changes when rules are adjusted. |
| **P3** | Minor × Contained × Rare | A few non-critical constants, weakly expressive magic values, or local default values are hardcoded; no active business path is affected, mainly affects readability and maintainability without causing deterministic functional errors. | Hardcoded page size `pageSize = 10` in code, or `if (user.status == 3)` without a constant name explanation. |

---

## Logging / Comments / Documentation / Convention Errors

| Priority | Typical Profile | Description | Example |
| --- | --- | --- | --- |
| **P2** | Limited × Local × Unlikely | Key business processes or important troubleshooting paths are missing necessary log context; structurally limited to specific code paths but the affected path serves an important diagnostic flow, significantly increases problem location difficulty or delays recovery, though does not directly change online execution results. | When payment fails, only printing "operation failed" without any associated order ID or user ID. |
| **P3** | Minor × Contained × Rare | Log levels, comment content, documentation descriptions, or convention details are not accurate, complete, or consistent enough; no active business path is affected, mainly affects team understanding and repository consistency. | A log that should be `DEBUG` level is set to `ERROR`, or comments have slight deviations from the code. |

---

## Testing / Debugging Issues

| Priority | Typical Profile | Description | Example |
| --- | --- | --- | --- |
| **P2** | Limited × Local × Unlikely | Test case logic errors, key assertion distortion, missing boundary coverage, or debug residuals interfering with verification results; structurally limited to test/CI paths not on production business flows, causes local real defects to be missed, manifesting as online or regression problems later. | A test should check `a > 0`, but incorrectly asserts `a >= 0`, allowing a boundary bug through. |
| **P3** | Minor × Contained × Rare | General deficiencies in test stability, coverage, naming organization, readability, or debug cleanup; no active production path is affected, mainly affects development efficiency and code cleanliness without directly corresponding to deterministic production failures. | Tests depending on external services fail intermittently, or submitted code retains `System.out.println("debug here")`. |

---

## Triage Examples

### Example 1: Hardcoded service URL in business code → P1

**Defect**: `service/payment.go:15`, The payment service URL is hardcoded directly in the code instead of being read from configuration.

```go
func CallPaymentService(ctx context.Context, req *PayReq) (*PayResp, error) {
    resp, err := httpClient.Post("http://service-a.prod.internal/api/pay", req)
    return resp, err
}
```

| Dimension | Verdict | Evidence |
| :--- | :--- | :--- |
| Impact Severity | **Severe** | The payment feature becomes completely unavailable in any environment other than production (staging, testing, disaster recovery), persistent feature failure during environment switching (persistent feature failure → Severe) |
| Blast Radius | **Module-level** | The hardcoded URL is used by all payment calls within the module; any environment change affects every payment operation, structurally scoped within the payment module but affects an important user-facing feature |
| Trigger Probability | **Likely** | Triggered on every deployment to a non-production environment (matches signal ⑤ reachable via normal operational conditions) |

**Priority**: High impact (Severe × Module-level) × Likely → **P1**, default block merge.

---

### Example 2: Misleading variable naming → P3

**Defect**: `service/user.go:67`, The function `isValid()` actually performs a deletion, severely misleading by its name.

```go
func (u *User) isValid() bool {
    db.Delete(&User{}, u.ID)
    return true
}
```

| Dimension | Verdict | Evidence |
| :--- | :--- | :--- |
| Impact Severity | **Minor** | The naming issue itself does not change runtime behavior (note: the deletion logic is a separate independent defect); it only affects readability and maintainability (readability / maintainability degradation → Minor) |
| Blast Radius | **Module-level** | The method is exported and called from multiple places within the module; it serves as a shared interface whose misleading name could propagate misuse across callers |
| Trigger Probability | **Rare** | The misleading name can only introduce new defects when a future maintainer misuses it; currently no runtime error is produced (matches signal ⑫ current callers do not trigger) |

**Priority**: Low impact (Minor × Module-level) × Rare → **P3**, does not block merge.
