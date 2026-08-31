# Completeness Errors, P0-P3 Triage Rules

> This file is a referenced rule file for the `issue-severity-triage` Skill.
> It covers P0-P3 triage criteria (combining consequence severity, blast radius, and trigger probability) for **completeness problems** (2 sub-categories).
>
> **How to use this file:**
> 1) First complete the independent three-dimension assessment (SKILL.md §5) and table lookup (§6) to determine the preliminary priority.
> 2) Use this reference to cross-validate: find the closest sub-category and Typical Profile row below.
> 3) If the independent assessment differs from the reference anchor, explain the reason in the 【分类与参考验证】section.

---

## Feature Not Implemented (Missing Implementation, Incorrectly Commented Out, etc.)

| Priority | Typical Profile | Description | Example |
| --- | --- | --- | --- |
| **P0** | Catastrophic × Module+ × Certain | The core capability promised by the current change is fundamentally not implemented, or the core business main flow cannot be walked through; structurally sits on the unconditional main path with module-wide or broader reach, and the affected path is a core business flow, after merging it directly blocks the achievement of core goals. | Clicking the payment button produces no response at all, preventing users from completing purchases. |
| **P1** | Severe × Module × Likely | Missing or failed functionality in important capabilities or high-frequency usage paths; structurally scoped within a module but the affected path serves an important user-facing feature, although the main flow can be bypassed, the affected function module is persistently broken under normal operations. | The "filter" capability on the product list page fails entirely; users can still browse and purchase, but cannot efficiently locate target products. |
| **P2** | Limited × Local × Unlikely | Unimplemented functionality on auxiliary capabilities, boundary scenarios, or non-core sub-processes; structurally confined to a single code path not on a core business flow, fallback or isolation mechanisms prevent impact from spreading, and only manifests under specific user actions. | The "nickname history" in a user profile page cannot be displayed; only triggered when users actively navigate to that sub-page. |
| **P3** | Minor × Contained × Rare | Prompt copy, degradation feedback, fallback experience, or supplementary capabilities are not filled in; no active business path is affected and no runtime correctness impact, only reduces product consistency and user experience polish. | A deprecated API does not return an "interface disabled" prompt as expected, but directly returns empty data. |

---

## Duplicate / Conflicting Definition

| Priority | Typical Profile | Description | Example |
| --- | --- | --- | --- |
| **P0** | Catastrophic × Broad/Module × Certain/Likely | Multiple conflicting implementations or definitions exist on the core path, and core rules, models, or state semantics are no longer unique; structurally the conflict spans module boundaries or sits on a shared global path, and the affected path is a core business flow, after merging directly causes critical behavior conflicts or system unavailability. | The same payment status is simultaneously used by two mutually incompatible enum implementations in the transaction path, causing core state transition errors. |
| **P1** | Severe × Module × Likely | Multiple duplicate definitions in important domain models or key business rules have deviated from consistent semantics; structurally scoped within a module but the affected definitions serve important features, under normal paths persistently produces parsing errors, logic inconsistency, or important feature anomalies. | The order service and payment service each define a set of "order status" enums that are not fully compatible. |
| **P2** | Limited × Local × Unlikely | Large amounts of duplicated logic or unabstracted code blocks within a single service; structurally limited to intra-module paths not on core business flows, does not directly cause failures currently, but rule adjustments are prone to missing changes, affecting local feature consistency. | Almost identical "data desensitization" or "date formatting" code exists in multiple classes. |
| **P3** | Minor × Contained × Rare | Minor duplicate implementations or poor abstraction granularity; no active business path is affected, mainly affects cleanliness and maintenance efficiency. | The same error message string is repeatedly defined in different methods of the same file. |

---

## Triage Examples

### Example 1: Payment button has no response → P0

**Defect**: `handler/payment.go:28`, The core processing logic of the payment endpoint is empty; clicking the payment button produces no response.

```go
func CreatePayment(ctx context.Context, req *PaymentReq) (*PaymentResp, error) {
    // TODO: implement payment logic
    return &PaymentResp{}, nil
}
```

| Dimension | Verdict | Evidence |
| :--- | :--- | :--- |
| Impact Severity | **Catastrophic** | The core payment capability promised by this change is completely unimplemented; users cannot complete purchases (feature completely unavailable → Catastrophic) |
| Blast Radius | **Module-level** | Payment is a core business flow involving persistent writes (order status updates); the unimplemented logic sits on a business-critical path whose failure blocks the entire purchase workflow |
| Trigger Probability | **Certain** | Any user clicking the payment button enters this empty logic (matches signal ① unconditional main path) |

**Priority**: Critical impact (Catastrophic × Module-level) × Certain → **P0**, block merge.

---

### Example 2: Incompatible order-status enums across services → P1

**Defect**: `model/order_status.go` and `payment/model/status.go`, The order service and payment service each define their own `OrderStatus` enum with incompatible mappings.

```go
// model/order_status.go
const (
    StatusPaid    = 2
    StatusShipped = 3
)

// payment/model/status.go
const (
    StatusPaid    = 1  // conflicts with order service
    StatusShipped = 2  // conflicts with order service
)
```

| Dimension | Verdict | Evidence |
| :--- | :--- | :--- |
| Impact Severity | **Severe** | Status code mismatch between services causes persistent misinterpretation of order states; payment confirmation writes status=1 but order service reads it as an unknown state (recoverable persistent data error → Severe) |
| Blast Radius | **Module-level** | The conflicting definitions span two modules (order and payment); any cross-module status exchange produces wrong state transitions, the order fulfillment path is a business-critical flow |
| Trigger Probability | **Likely** | Every payment completion triggers a status sync between the two services (matches signal ⑤ reachable via normal input) |

**Priority**: High impact (Severe × Module-level) × Likely → **P1**, default block merge.
