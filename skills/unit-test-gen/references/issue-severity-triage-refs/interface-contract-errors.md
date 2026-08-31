# Interface & Contract Errors, P0-P3 Triage Rules

> This file is a referenced rule file for the `issue-severity-triage` Skill.
> It covers P0-P3 triage criteria (combining consequence severity, blast radius, and trigger probability) for **interface and contract problems** (2 sub-categories).
>
> **How to use this file:**
> 1) First complete the independent three-dimension assessment (SKILL.md §5) and table lookup (§6) to determine the preliminary priority.
> 2) Use this reference to cross-validate: find the closest sub-category and Typical Profile row below.
> 3) If the independent assessment differs from the reference anchor, explain the reason in the 【分类与参考验证】section.

---

## Function / API Call or Declaration Errors

| Priority | Typical Profile | Description | Example |
| --- | --- | --- | --- |
| **P0** | Catastrophic × Broad/Module × Certain | Core function contracts, core API versions, or key declaration conventions fundamentally misalign; structurally the misalignment sits on a cross-module or global path, and the affected path is a core business flow, after merging the core process is unavailable or the change goal is unachievable. | Calling the deprecated V1 payment interface instead of the new V2 interface, causing the payment process to fail. |
| **P1** | Severe × Module × Likely | Parameters, return values, default conventions, or version semantics are misused in important function calls; structurally scoped within a module but the affected path serves an important feature, under normal paths the defect persistently produces call failures or wrong results. | When calling `Update(id, data)`, it is written as `Update(data, id)`. |
| **P2** | Limited × Local × Unlikely | Partial inconsistency between declarations and implementations, incomplete branch returns, or unclear boundary conventions; structurally limited to a specific code path not on a core business flow, in specific branches returns wrong values or causes local feature anomalies, but the impact is limited. | A function querying user credits forgets to `return` in the branch where the user does not exist, causing it to return 0 by default. |
| **P3** | Minor × Contained × Rare | Calling style, declaration style, or compatibility choices are not stable enough; no active business path is affected, does not affect results but increases future maintenance costs. | Using a method marked as `@Deprecated` in a library. |

---

## Exception / Error Handling Errors

| Priority | Typical Profile | Description | Example |
| --- | --- | --- | --- |
| **P0** | Catastrophic × Module+ × Likely | Failure signals are ignored / swallowed or error propagation is broken on the core error handling path; structurally the suppressed error sits on a shared path or is exposed to multiple callers, and the affected path is a core business flow, the system treats critical failures as successes, causing core data inconsistency or core process interruption. | After updating the order status, not checking the `err` returned by `db.Exec(...)`. |
| **P1** | Severe × Module × Likely | Exceptions are not correctly exposed / classified / returned / terminated; structurally scoped within a module but the affected path serves an important feature, the failure path masquerades as success, causing the caller to misjudge and leading to persistent feature errors. | After the `try` block for initiating payment fails, the `catch` block only prints a log and the function returns normally. |
| **P2** | Limited × Local × Unlikely | Error classification, retry, fallback, or rollback strategies are not refined enough; structurally limited to a specific code path not on a core business flow, in specific scenarios causes extra delays or single task anomalies, but fallback mechanisms contain the impact. | The client still retries 3 times when the interface returns "invalid parameter". |
| **P3** | Minor × Contained × Rare | Non-standard exception mapping, encapsulation, logging, or layering; no active business path is affected, does not change runtime results but increases troubleshooting difficulty. | The Controller layer directly throws `java.sql.SQLException` upward. |

---

## Triage Examples

### Example 1: Swallowed DB error in order update → P0

**Defect**: `service/order.go:56`, After calling `db.Exec(...)` to update the order status, the returned `err` is not checked; the function returns nil regardless of success or failure.

```go
func UpdateOrderStatus(ctx context.Context, orderID string, status string) error {
    db.Exec("UPDATE orders SET status = ? WHERE id = ?", status, orderID) // err ignored
    return nil
}
```

| Dimension | Verdict | Evidence |
| :--- | :--- | :--- |
| Impact Severity | **Catastrophic** | The system treats a failed DB write as success; downstream logic (shipping, notification) proceeds on stale/incorrect state, persistent data inconsistency with no recovery mechanism (persistent data corruption → Catastrophic) |
| Blast Radius | **Module-level** | The order status update is called from multiple paths within the order module (payment callback, admin override, timeout handler); erroneous state implicitly spreads to all downstream reads, the order path is a core business flow |
| Trigger Probability | **Likely** | DB failures (network blip, lock timeout) are common in production; every occurrence silently corrupts order state (matches signal ⑤ reachable via normal operational conditions) |

**Priority**: Critical impact (Catastrophic × Module-level) × Likely → **P0**, block merge.

---

### Example 2: Swapped parameters in Update call → P1

**Defect**: `handler/user.go:42`, The arguments to `userRepo.Update(id, data)` are swapped as `userRepo.Update(data, id)`.

```go
func UpdateUserProfile(ctx context.Context, req *UpdateReq) error {
    return userRepo.Update(req.Data, req.UserID) // should be Update(req.UserID, req.Data)
}
```

| Dimension | Verdict | Evidence |
| :--- | :--- | :--- |
| Impact Severity | **Severe** | Every profile update writes to the wrong record or fails with a type mismatch; user data is persistently corrupted but recoverable via audit log (recoverable persistent data error → Severe) |
| Blast Radius | **Module-level** | The user profile update is an important user-facing feature; all profile edits pass through this single function, structurally scoped within the user module but affects all update operations |
| Trigger Probability | **Likely** | Every call to UpdateUserProfile passes swapped arguments (matches signal ⑤ reachable via normal input) |

**Priority**: High impact (Severe × Module-level) × Likely → **P1**, default block merge.
