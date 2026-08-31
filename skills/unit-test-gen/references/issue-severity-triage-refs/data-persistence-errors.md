# Data Persistence Errors, P0-P3 Triage Rules

> This file is a referenced rule file for the `issue-severity-triage` Skill.
> It covers P0-P3 triage criteria (combining consequence severity, blast radius, and trigger probability) for **data persistence problems** (2 sub-categories).
>
> **How to use this file:**
> 1) First complete the independent three-dimension assessment (SKILL.md §5) and table lookup (§6) to determine the preliminary priority.
> 2) Use this reference to cross-validate: find the closest sub-category and Typical Profile row below.
> 3) If the independent assessment differs from the reference anchor, explain the reason in the 【分类与参考验证】section.

---

## Data Operation Errors

| Priority | Typical Profile | Description | Example |
| --- | --- | --- | --- |
| **P0** | Catastrophic × Module+ × Certain | Fundamental correctness of core data reads/writes is broken, query targets, update objects, filter conditions, write semantics, or transaction boundaries have fatal defects; the affected persistent writes sit on a core business flow and erroneous data implicitly spreads to all downstream consumers, causing large-scale unrecoverable integrity damage. | The order refund interface erroneously uses a global WHERE condition, causing all user orders to be deleted. |
| **P1** | Severe × Module × Likely | Data read/write logic, mapping relationships, or transaction constraints are incorrectly implemented on important business data processing paths; structurally scoped within a module but involves persistent writes whose errors implicitly spread to downstream reads, under normal paths persistently produces incorrect reads/writes or data inconsistency. | A PR in the coupon service incorrectly reads the coupon applicable range field, causing all modules using coupons to be unable to correctly determine eligibility. |
| **P2** | Limited × Local × Unlikely | Non-core paths or boundary scenarios cause local data deviations or short-term display anomalies; structurally limited to a single code path not on a core business flow, auto-correction or compensation mechanisms exist to contain the impact. | User portrait tag calculation logic error, causing recommendations to be slightly inaccurate in the short term, but the system recalculates tags daily and auto-corrects. |
| **P3** | Minor × Contained × Rare | Data processing methods, mapping organization, or implementation abstraction is not stable enough; no active business path produces deterministic erroneous data, only increases understanding costs and risks of subsequent changes. | The same statistical data is assembled with similar field mappings in multiple query functions, making it prone to maintenance inconsistency when fields are adjusted later. |

---

## Database Errors

| Priority | Typical Profile | Description | Example |
| --- | --- | --- | --- |
| **P0** | Catastrophic × Broad/Module × Certain | Database-level fundamental correctness or deployability is broken, unexecutable migration scripts, destroyed core table structures, or incorrectly deleted key constraints; structurally sits on a global initialization or build path, and the affected schema underpins core business flows, directly causes deployment failures, core data loss, or database layer unavailability. | SQL syntax errors in Flyway or Liquibase scripts, or containing `DROP TABLE users;`. |
| **P1** | Severe × Module × Likely | SQL logic, field mapping, association relationships, filter conditions, or index assumptions have obvious defects on important queries/writes/transactions; structurally scoped within a module but the affected path serves an important user-facing feature, under normal requests persistently returns wrong results, timeouts, or throws exceptions. | The product detail page query interface causes 500 errors due to incorrect table joins. |
| **P2** | Limited × Local × Unlikely | Non-core interfaces or boundary queries cause slow queries, single failures, or local result errors due to missing conditions, pagination errors, or poor execution plans; structurally limited to a specific endpoint not on a core business path, the impact is limited to specific scenarios. | The background log query interface does not limit the time range, and queries with very large spans will noticeably timeout. |
| **P3** | Minor × Contained × Rare | SQL writing is not standard enough, unclear abstraction boundaries, or high coupling with table structures; no active business path is affected, only increases evolution and maintenance costs. | Background queries long use `SELECT *`, and after new table fields are added, return payload and mapping maintenance costs keep rising. |

---

## Triage Examples

### Example 1: Refund endpoint deletes all orders due to global WHERE condition → P0

**Defect**: `service/refund.go:56`, The DELETE statement in the refund handler is missing a user filter in the WHERE clause, causing all users' orders to be deleted.

```go
func ProcessRefund(ctx context.Context, orderID string) error {
    result := db.Exec("DELETE FROM orders WHERE status = 'REFUNDING'") // missing AND order_id = ?
    return result.Error
}
```

| Dimension | Verdict | Evidence |
| :--- | :--- | :--- |
| Impact Severity | **Catastrophic** | The entire table is erroneously deleted; persistent data is irreversibly corrupted (irreversible persistent data corruption → Catastrophic) |
| Blast Radius | **Module-level** | Involves an unscoped persistent DB delete that wipes the entire orders table; the erroneous data loss implicitly affects all downstream order reads, and the order/refund path is a core business flow |
| Trigger Probability | **Certain** | The SQL executes on every refund request with no conditional guard (matches signal ① unconditional main path) |

**Priority**: Critical impact (Catastrophic × Module-level) × Certain → **P0**, block merge.

---

### Example 2: Background log query has no time-range limit → P3

**Defect**: `handler/admin_log.go:31`, The background log query endpoint does not restrict the time span; wide-range queries cause slow-query timeouts.

```go
func QueryLogs(ctx context.Context, req *LogQueryReq) ([]*LogEntry, error) {
    return logRepo.Find(ctx, req.Keyword) // no time-range limit
}
```

| Dimension | Verdict | Evidence |
| :--- | :--- | :--- |
| Impact Severity | **Limited** | A query timeout only affects a single request; it does not compromise data integrity, and timeout / circuit-breaker mechanisms provide a safety net (bounded performance overhead → Limited) |
| Blast Radius | **Local** | Only the log-query feature in the admin console is affected; no shared state or persistent writes involved; not on a core business path |
| Trigger Probability | **Unlikely** | Only times out when an operator selects an extremely large time span (matches signal ⑧ boundary condition) |

**Priority**: Low impact (Limited × Local) × Unlikely → **P3**, does not block merge.
