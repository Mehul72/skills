# Control Flow Errors, P0-P3 Triage Rules

## Table of Contents

- [Conditional Logic Errors](#conditional-logic-errors)
- [Boolean Expression Writing Errors](#boolean-expression-writing-errors)
- [Loop / Recursive Logic Errors](#loop--recursive-logic-errors)
- [Sequential Logic Errors](#sequential-logic-errors)
- [State Initialization Errors](#state-initialization-errors)
- [Triage Examples](#triage-examples)

> This file is a referenced rule file for the `issue-severity-triage` Skill.
> It covers P0-P3 triage criteria (combining consequence severity, blast radius, and trigger probability) for **control flow problems** (5 sub-categories).
>
> **How to use this file:**
> 1) First complete the independent three-dimension assessment (SKILL.md §5) and table lookup (§6) to determine the preliminary priority.
> 2) Use this reference to cross-validate: find the closest sub-category and Typical Profile row below.
> 3) If the independent assessment differs from the reference anchor, explain the reason in the 【分类与参考验证】section.

---

## Conditional Logic Errors

| Priority | Typical Profile | Description | Example |
| --- | --- | --- | --- |
| **P0** | Catastrophic × Broad/Module × Certain/Likely | Condition coverage, mutual exclusion, or jump control has fatal defects in core branch decision-making; structurally the faulty branch guards a cross-module or global path, and the affected path is a core business flow, causes core state transitions or permission judgments to enter wrong branches, leading to unconditional full-path errors or security boundary penetration. | When updating different fields based on order status, `case "PAID":` has no `break`, continuing to execute the `case "SHIPPED":` logic. |
| **P1** | Severe × Module × Likely | Condition order, coverage, mutual exclusion, or branch fallback is wrong in important feature branch control; structurally scoped within a module but the affected path serves an important feature, under normal inputs persistently triggers wrong branches or permanently fails important branches. | `if (x > 5) { ... } else if (x > 10) { ... }`, the second branch is unreachable. |
| **P2** | Limited × Local × Unlikely | Boundary condition misjudgments in local rules or secondary branches; structurally limited to a specific code path not on a core business flow, causes single request failures or result deviations in boundary value scenarios, but overall impact is controllable. | Judging whether user credits are sufficient, `if (score > required)` instead of `if (score >= required)`. |
| **P3** | Minor × Contained × Rare | Unclear condition organization or verbose expressions; no active business path is affected, does not change runtime results but affects understanding efficiency. | Using a series of `if-else if` to judge the same enum value, when `switch` could improve clarity. |

---

## Boolean Expression Writing Errors

| Priority | Typical Profile | Description | Example |
| --- | --- | --- | --- |
| **P0** | Catastrophic × Broad/Module × Certain/Likely | Wrong true/false conditions, combination relationships, or priority in core judgments (permissions, payments, state transitions); structurally the faulty condition guards a cross-module or global path, and the affected path is a core business flow, directly allows wrong decisions through or blocks correct decisions, causing security boundary penetration or unconditional full-path errors. | In administrator permission judgment, written as `if (user.role = "admin")` (assignment instead of comparison). |
| **P1** | Severe × Module × Likely | Condition combinations, priority, brackets, or and/or relationships are wrong in important feature judgments; structurally scoped within a module but the affected path serves an important feature, under normal paths persistently produces logic misjudgments causing feature errors or privilege escalation. | Order visibility judgment written as `isOwner || isAdmin && isPaid`, when it should be `(isOwner || isAdmin) && isPaid`. |
| **P2** | Limited × Local × Unlikely | Incorrect boolean expression in boundary combinations or non-core judgments; structurally limited to a specific code path not on a core business flow, causes rules to be locally relaxed or tightened, but limited to specific scenarios. | Upload validation should require `size <= limit && typeAllowed`, but is written as `size <= limit || typeAllowed`. |
| **P3** | Minor × Contained × Rare | Redundant boolean expression writing or poor readability; no active business path is affected, does not change results but increases understanding cost. | `if (isValid == true)`, or multiple `else if` branches containing duplicate conditions. |

---

## Loop / Recursive Logic Errors

| Priority | Typical Profile | Description | Example |
| --- | --- | --- | --- |
| **P0** | Catastrophic × Broad/Module × Likely | Loop boundaries, termination conditions, or recursive convergence conditions have fatal defects; structurally the runaway loop/recursion sits on a shared path or global execution path, and the resulting resource exhaustion affects all business flows, directly causes infinite loops, infinite recursion, or process-level resource exhaustion. | A recursive retry function in a settlement task forgets to set a termination condition, causing infinite recursion on failure. |
| **P1** | Severe × Module × Likely | Boundaries, termination conditions, or traversal targets are wrong; structurally scoped within a module but the affected path serves an important feature, under normal paths persistently causes out-of-bounds, data omission, duplicate processing, or incomplete results. | Looping through an order list, but the loop condition is `i <= orders.length()`, causing out-of-bounds. |
| **P2** | Limited × Local × Unlikely | Specific data sets or boundary counting causes local element processing omissions or single task failures; structurally limited to a specific code path not on a core business flow, the impact is limited and performance degradation is bounded. | `for (item : list) { if (shouldDelete(item)) list.remove(item); }`, ConcurrentModificationException on specific data. |
| **P3** | Minor × Contained × Rare | Loop or recursive writing is not clear enough or poor abstraction; no active business path is affected, does not affect correctness but increases understanding cost. | Using traditional index traversal in scenarios where `foreach` can be used. |

---

## Sequential Logic Errors

| Priority | Typical Profile | Description | Example |
| --- | --- | --- | --- |
| **P0** | Catastrophic × Broad/Module × Certain | Order of initialization, submission, rollback, consumption, or state switching is fundamentally wrong in core process orchestration; structurally the misordered steps sit on a cross-module or global path, and the affected path is a core business flow, directly causes core process failures or persistent data irreversible corruption. | Calling `client.send()` without first calling `client.connect()`. |
| **P1** | Severe × Module × Likely | Step dependency relationships are incorrectly implemented in important business orchestration; structurally scoped within a module but the affected path serves an important feature, under normal paths persistently causes feature failures, state confusion, or data inconsistency. | In a database transaction, first inserting the order record, then deducting inventory; if deduction fails, the order already exists. |
| **P2** | Limited × Local × Unlikely | Imprecise ordering in boundary conditions or cleanup logic; structurally limited to a specific code path not on a core business flow, causes local cleanup failures or single task state anomalies, but the impact is limited. | Opening a file stream `reader` in the `try` block, and directly calling `reader.close()` in `finally`; if opening fails, `reader` is nil. |
| **P3** | Minor × Contained × Rare | Code organization order inconsistent with logical understanding order; no active business path is affected, does not affect functionality but increases reading difficulty. | Variable declarations in a function are far from their first point of use. |

---

## State Initialization Errors

| Priority | Typical Profile | Description | Example |
| --- | --- | --- | --- |
| **P0** | Catastrophic × Broad/Module × Certain | Default state, initial dependencies, or startup configuration of core objects / state machines is fundamentally wrong; structurally sits on a global initialization path or a shared state entry point, and the affected path is a core business flow, once the system enters the relevant process it goes to abnormal branches, causing core processes to be unavailable. | The initial value of the order state machine is set to `UNDEFINED`. |
| **P1** | Severe × Module × Likely | Key fields, dependencies, flags, or default configurations of important objects are not correctly assembled; structurally scoped within a module but the affected path serves an important feature, under normal paths the defect persistently triggers error branches or important features being unavailable. | The `db` member variable of a Service object is not assigned during construction. |
| **P2** | Limited × Local × Unlikely | Incomplete initialization of default values, collections, counters, or local states; structurally limited to a specific code path not on a core business flow, in specific instances or boundary scenarios causes local behavior deviations or non-core feature anomalies. | When a shopping cart object is created, the total price `totalPrice` is not initialized to 0. |
| **P3** | Minor × Contained × Rare | Initialization constraint expression is insufficient or default value intent is unclear; no active business path is affected, does not change runtime results but weakens readability and maintainability. | The `timeout` field in a config class does not change after construction, but is not declared as immutable. |

---

## Triage Examples

### Example 1: Missing break in switch causes core state error → P1

**Defect**: `service/order.go:89`, In the order-status switch, `case "PAID"` lacks a `break`, falling through to the `case "SHIPPED"` logic.

```java
switch (order.getStatus()) {
    case "PAID":
        markAsPaid(order);
        // missing break, falls through to SHIPPED
    case "SHIPPED":
        markAsShipped(order);
        break;
}
```

| Dimension | Verdict | Evidence |
| :--- | :--- | :--- |
| Impact Severity | **Severe** | The order is incorrectly marked as "shipped"; persistent data contains a recoverable error (recoverable persistent data error → Severe) |
| Blast Radius | **Module-level** | Involves a persistent DB write (order status update) whose erroneous data implicitly spreads to downstream reads; the order fulfillment path is a business-critical flow |
| Trigger Probability | **Likely** | Every successfully paid order enters the `case "PAID"` branch (matches signal ⑤ reachable via normal input) |

**Priority**: High impact (Severe × Module-level) × Likely → **P1**, default block merge.

---

### Example 2: Sending data on unconnected client → P0

**Defect**: `service/notification.go:34`, The notification service calls `client.Send()` before `client.Connect()`, causing all notification deliveries to fail.

```go
func SendNotification(ctx context.Context, msg *Message) error {
    client := NewMQClient(cfg)
    err := client.Send(ctx, msg) // client.Connect() was never called
    return err
}
```

| Dimension | Verdict | Evidence |
| :--- | :--- | :--- |
| Impact Severity | **Catastrophic** | The notification sending function fails on every invocation; the entire notification capability is non-functional (feature completely unavailable → Catastrophic) |
| Blast Radius | **Module-level** | All callers within the notification module converge on this function; the broken initialization prevents any notification from being delivered, the notification path is a business-critical flow |
| Trigger Probability | **Certain** | Every call to `SendNotification` enters this code path unconditionally (matches signal ① unconditional main path) |

**Priority**: Critical impact (Catastrophic × Module-level) × Certain → **P0**, block merge.
