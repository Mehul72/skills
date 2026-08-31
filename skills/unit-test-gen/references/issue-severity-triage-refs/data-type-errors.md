# Data & Type Errors, P0-P3 Triage Rules

## Table of Contents

- [Null Pointer / Null Reference Errors](#null-pointer--null-reference-errors)
- [Parameter Validation Errors](#parameter-validation-errors)
- [Numeric Overflow / Truncation / Precision Errors](#numeric-overflow--truncation--precision-errors)
- [Type Errors](#type-errors)
- [Collection / Array / String Errors](#collection--array--string-errors)
- [Triage Examples](#triage-examples)

> This file is a referenced rule file for the `issue-severity-triage` Skill.
> It covers P0-P3 triage criteria (combining consequence severity, blast radius, and trigger probability) for **data and type problems** (5 sub-categories).
>
> **How to use this file:**
> 1) First complete the independent three-dimension assessment (SKILL.md §5) and table lookup (§6) to determine the preliminary priority.
> 2) Use this reference to cross-validate: find the closest sub-category and Typical Profile row below.
> 3) If the independent assessment differs from the reference anchor, explain the reason in the 【分类与参考验证】section.

---

## Null Pointer / Null Reference Errors

| Priority | Typical Profile | Description | Example |
| --- | --- | --- | --- |
| **P0** | Catastrophic × Module+ × Likely | Deterministic lifecycle defect on a nullable object/reference/dependency: entering the path causes an unrecovered crash or breaks through the core flow; structurally reaches multiple callers or sits on a shared path, and the affected path is a core business flow, makes core requests fail or core data corrupt. | In payment callback logic, immediately performing a status update on an order object that is explicitly nil. |
| **P1** | Severe × Module × Likely | Nullable constraint not correctly expressed or consumed; structurally scoped within a module but the affected path serves an important feature, under normal inputs the defect persistently produces runtime exceptions or failures in the affected function module, but does not terminate the process. | When querying user personal information, if the database returns no result, the code accesses fields of the return object directly without null check, every such query fails. |
| **P2** | Limited × Local × Unlikely | Insufficient null handling only triggers single-request failures or partial result anomalies under specific boundary inputs; structurally limited to a single code path not on a core business flow, fallback or isolation mechanisms prevent the impact from spreading. | In a background report generation feature, chain-calling `data.summary.count` where `summary` is nil for certain report types. |
| **P3** | Minor × Contained × Rare | Nullable constraint expression is unclear or null-check responsibility is unassigned, but no runtime fault is formed; no active business path is affected, only readability / maintainability impact. | A utility function `Format(user *User)` neither performs a null check nor states in its contract that `user` cannot be nil. |

---

## Parameter Validation Errors

| Priority | Typical Profile | Description | Example |
| --- | --- | --- | --- |
| **P0** | Catastrophic × Module+ × Likely | Missing validation at core business input boundaries directly lets illegal input through; structurally the unguarded entry point serves multiple callers or a shared path, and the affected path is a core business flow, causing core data corruption or loss of control of core processes. | A transfer function does not validate that the amount must be greater than zero, allowing negative amounts to be passed in. |
| **P1** | Severe × Module × Likely | Key parameter format / range / combination / business legality validation is insufficient; structurally scoped within a module but the affected path serves an important feature, under normal erroneous inputs the defect persistently causes request failures or obviously wrong results. | The user registration interface does not validate username length or format, every malformed input passes through. |
| **P2** | Limited × Local × Unlikely | Incomplete validation dimensions or missing boundary conditions; structurally limited to a specific code path not on a core business flow, under specific input combinations causes local logic anomalies or resource waste, but fallback mechanisms limit the impact. | The `pageSize` parameter of a list query interface has no maximum value limit, allowing one million records to be queried at once. |
| **P3** | Minor × Contained × Rare | Validation logic is scattered / duplicated / inconsistent in expression; no active business path is affected, does not change runtime results but increases maintenance cost when rules change. | Multiple functions each implement `userID` format validation independently with inconsistent error message copy. |

---

## Numeric Overflow / Truncation / Precision Errors

| Priority | Typical Profile | Description | Example |
| --- | --- | --- | --- |
| **P0** | Catastrophic × Module+ × Likely | Numeric range, precision, type, or conversion strategy has fundamental defects in core numeric paths (settlement, accounting, inventory, quotas); structurally the defective calculation sits on a shared path or serves multiple callers, and the affected path is a core business flow, directly causes cumulative deviation of core data or unacceptable business consequences. | Using `float64` to define order amounts and perform addition/subtraction operations. |
| **P1** | Severe × Module × Likely | Overflow, truncation, narrowing conversions, or precision loss in important feature calculations; structurally scoped within a module but the affected path serves an important feature, under common input ranges persistently produces obviously wrong results affecting important judgments. | Directly converting a 64-bit timestamp (`long`) to a 32-bit integer (`int`). |
| **P2** | Limited × Local × Unlikely | Imprecise numeric processing strategies in boundary values or non-core calculation scenarios; structurally limited to a specific code path not on a core business flow, causes local deviations or threshold misjudgments, but the overall impact is limited. | Calculating the completion rate `5 / 10` yields 0 (integer division). |
| **P3** | Minor × Contained × Rare | Numeric semantics expression is unclear or type choices are not self-explanatory; no active business path is affected, does not directly cause wrong results but increases misreading risk. | `if (user.status == 3)`, where the meaning of `3` is unclear. |

---

## Type Errors

| Priority | Typical Profile | Description | Example |
| --- | --- | --- | --- |
| **P0** | Catastrophic × Broad/Module × Certain/Likely | Type constraints are fundamentally wrong in core protocols, message bodies, or persistence contracts; structurally the mistyped field sits on a cross-module or global path, and the affected path is a core business flow, directly causes type errors, deserialization failures, or core process unavailability. | The order status consumer program casts the `status` in the core message to an incompatible type, causing a panic during consumption. |
| **P1** | Severe × Module × Likely | Type assertions, downcasting, or generic assumptions are not met in important feature processing paths; structurally scoped within a module but the affected path serves an important feature, under normal inputs persistently triggers runtime exceptions or feature failures. | `Object obj = ...; Dog dog = (Dog)obj;`, but `obj` may not actually be a `Dog`. |
| **P2** | Limited × Local × Unlikely | Field type inconsistency with actual data in specific interfaces or boundary inputs; structurally limited to a specific code path not on a core business flow, causes local parsing failures or non-core feature anomalies. | `{"age": "20"}` in JSON is defined as `int age;` in code. |
| **P3** | Minor × Contained × Rare | Overly broad type expression or missing static constraints; no active business path is affected, no fault formed but weakens compile-time guarantees. | Function parameters and return values extensively use `Object` or `any`. |

---

## Collection / Array / String Errors

| Priority | Typical Profile | Description | Example |
| --- | --- | --- | --- |
| **P0** | Catastrophic × Module+ × Likely | Deterministic defects in handling collection / array / string boundaries on core processing paths; structurally the defective operation sits on a shared path or serves multiple callers, and the affected path is a core business flow, directly triggers crashes or core data processing distortion. | In core settlement logic, a fixed wrong index is used to read an array, and entering that branch immediately causes out-of-bounds. |
| **P1** | Severe × Module × Likely | Index, slice, concatenation, or traversal boundary constraints are not correctly consumed in important features; structurally scoped within a module but the affected path serves an important feature, under common abnormal inputs persistently causes out-of-bounds, errors, or wrong results. | `int index = getIndexFromRequest(); String value = options[index];`, no bounds check. |
| **P2** | Limited × Local × Unlikely | Boundary parameters or non-core string/collection operations cause local runtime exceptions or result truncation in specific inputs; structurally limited to a specific code path not on a core business flow, the impact is limited to specific scenarios. | `str.substring(10, 5)`, invalid range on specific inputs. |
| **P3** | Minor × Contained × Rare | Collection or string processing is not efficient enough or poor readability; no active business path is affected, does not affect correctness. | `String s = ""; for (...) { s += "x"; }`, inefficient concatenation. |

---

## Triage Examples

### Example 1: Null pointer in payment callback causes crash → P0

**Defect**: `service/payment.go:78`, In the payment callback handler, the code directly calls `order.UpdateStatus()` on an order object that may be nil when the order lookup fails.

```go
func HandlePaymentCallback(ctx context.Context, req *CallbackReq) error {
    order, _ := orderRepo.FindByID(ctx, req.OrderID) // err ignored, order may be nil
    order.UpdateStatus("PAID") // nil dereference → panic
    return nil
}
```

| Dimension | Verdict | Evidence |
| :--- | :--- | :--- |
| Impact Severity | **Catastrophic** | Nil dereference causes an unrecovered panic, crashing the request handler; in Go HTTP servers with no recover middleware this terminates the goroutine (process crash / unrecovered panic → Catastrophic) |
| Blast Radius | **Module-level** | The payment callback is a core business flow; `orderRepo.FindByID` returns nil when the order does not exist (e.g., duplicate callback, expired order). The panic affects the entire payment confirmation path |
| Trigger Probability | **Likely** | Payment gateways commonly send duplicate or delayed callbacks; the nil case is reached under normal operational conditions (matches signal ⑤ reachable via normal input) |

**Priority**: Critical impact (Catastrophic × Module-level) × Likely → **P0**, block merge.

---

### Example 2: Boundary-condition integer division by zero → P3

**Defect**: `utils/stats.go:45`, The completion-rate calculation does not guard against a zero denominator.

```go
func CompletionRate(done, total int) float64 {
    return float64(done) / float64(total) // panics when total == 0
}
```

| Dimension | Verdict | Evidence |
| :--- | :--- | :--- |
| Impact Severity | **Limited** | Integer division by zero causes a single-request panic but does not affect other requests or persistent data (single-request failure → Limited) |
| Blast Radius | **Local** | Called only by the single caller `ReportHandler`; no shared state or external side effects involved; not on a core business path |
| Trigger Probability | **Unlikely** | Only occurs for a newly created project with zero completed tasks (matches signal ⑧ boundary condition) |

**Priority**: Low impact (Limited × Local) × Unlikely → **P3**, does not block merge.
