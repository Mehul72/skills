# Concurrency & Resource Errors, P0-P3 Triage Rules

> This file is a referenced rule file for the `issue-severity-triage` Skill.
> It covers P0-P3 triage criteria (combining consequence severity, blast radius, and trigger probability) for **concurrency and resource problems** (3 sub-categories).
>
> **How to use this file:**
> 1) First complete the independent three-dimension assessment (SKILL.md §5) and table lookup (§6) to determine the preliminary priority.
> 2) Use this reference to cross-validate: find the closest sub-category and Typical Profile row below.
> 3) If the independent assessment differs from the reference anchor, explain the reason in the 【分类与参考验证】section.

---

## Concurrency / Async Errors

| Priority | Typical Profile | Description | Example |
| --- | --- | --- | --- |
| **P0** | Catastrophic × Broad/Module × Likely | Shared state synchronization, message collaboration, or timing control has fatal defects on core concurrency paths; structurally the unsynchronized state sits on a global path or is written by cross-module callers, and the affected path is a core business flow, directly causes data races, state corruption, panics, or process-level resource exhaustion. | Multiple goroutines concurrently writing to the same map without using `sync.Mutex`. |
| **P1** | Severe × Module × Likely | Channels, locks, task orchestration, or callback collaboration are incorrectly implemented on important async / high-frequency concurrent paths; structurally scoped within a module but the affected path serves an important feature, under normal running persistently triggers panics, task failures, or blocking. | A producer still tries to send data after closing a channel. |
| **P2** | Limited × Local × Unlikely | Specific timing, high load, or boundary concurrent scenarios cause blocking or throughput degradation; structurally limited to a specific code path not on a core business flow, the impact is controllable and local result instability is bounded. | `mutex.Lock(); httpClient.Get(...); mutex.Unlock();`, holding lock during I/O. |
| **P3** | Minor × Contained × Rare | Concurrency or async model selection is not reasonable or overly complex; no active business path is affected, does not cause correctness problems but increases debugging difficulty. | Creating an extra goroutine for a lightweight function that could be executed synchronously, and immediately blocking to wait for its return. |

---

## Memory Errors

| Priority | Typical Profile | Description | Example |
| --- | --- | --- | --- |
| **P0** | Catastrophic × Broad/Module × Likely | Fundamental correctness of memory allocation, deallocation, or reference validity is broken; structurally the memory corruption sits on a global path or affects shared state, and the resulting crash takes down the entire process affecting all business flows, directly causes process crashes or makes core services unavailable. | `free(ptr); ...; free(ptr);`, double free. |
| **P1** | Severe × Module × Likely | Memory release, reference holding, or lifecycle management has obvious defects on important or high-frequency paths; structurally scoped within a module but the affected path serves an important feature, after continuous running persistently pushes up memory usage causing features to degrade or restart. | A function `new`s an object but does not `delete` it on any return path. |
| **P2** | Limited × Local × Unlikely | Logical memory leaks, insufficient cache eviction, or overly long object lifecycles; structurally limited to a specific code path not on a core business flow, causes alerts or performance degradation during long-running, but GC / timeout / pool limits can auto-recover. | A static Map cache only adds cache items without any expiration or eviction strategy. |
| **P3** | Minor × Contained × Rare | Uneconomical object allocation or minor GC pressure; no active business path is affected, does not cause substantial failures. | `String s = new String("hello")`, unnecessary allocation. |

---

## Excessive IO / Memory / Disk / Network / Database Usage

| Priority | Typical Profile | Description | Example |
| --- | --- | --- | --- |
| **P0** | Catastrophic × Broad × Likely | Basic safety boundary of resource usage is broken on the core service path; IO, memory, CPU, network, disk, or database resources are continuously and erroneously consumed without release, structurally sits on a global path traversed by all requests, and the resulting exhaustion takes down the entire process affecting all business flows. | In request processing logic, each request allocates a block of memory that cannot be reclaimed (e.g., added to a global static Map). |
| **P1** | Severe × Module × Likely | Resource usage pattern has obvious defects on important interfaces or high-frequency tasks; structurally scoped within a module but the affected path serves an important user-facing feature, after normal load amplification persistently slows down responses, crowds out resources, or degrades important features. | The order list interface queries user information for each order individually in a loop (N+1 query). |
| **P2** | Limited × Local × Unlikely | Background tasks, non-core interfaces, or boundary load scenarios have improper resource usage; structurally limited to a specific code path not on a core business flow, causes alerts or throughput degradation under peak requests, but timeout / circuit-breaker mechanisms contain the impact. | The export feature queries all data into memory first, then generates the file. |
| **P3** | Minor × Contained × Rare | Resource usage is not economical enough, insufficient reuse, or has optimization space; no active business path is affected, only brings minor extra overhead and does not affect correctness or stability. | Repeatedly creating short-lived objects in a low-frequency management interface when they could be reused to reduce minor allocation overhead. |

---

## Triage Examples

### Example 1: Concurrent map writes cause panic → P0

**Defect**: `service/task_runner.go:127`, Multiple goroutines simultaneously write to `taskStatusMap` (`map[string]string`) without synchronization.

```go
var taskStatusMap = make(map[string]string)

func UpdateTaskStatus(taskID, status string) {
    taskStatusMap[taskID] = status // unsynchronized write
}
```

| Dimension | Verdict | Evidence |
| :--- | :--- | :--- |
| Impact Severity | **Catastrophic** | The Go runtime issues a fatal error on concurrent map writes, crashing the process (process crash → Catastrophic) |
| Blast Radius | **Broad** | `taskStatusMap` is a package-level global variable written by all HTTP handlers concurrently, structurally it writes to global shared state and sits on a path traversed by every request; the resulting crash affects all in-flight requests across modules |
| Trigger Probability | **Certain** | Triggered by normal concurrent HTTP handler invocations; no special input required (matches signal ① unconditional main path) |

**Priority**: Critical impact (Catastrophic × Broad) × Certain → **P0**, block merge.

---

### Example 2: N+1 query slows down the list endpoint → P1

**Defect**: `service/order_list.go:42`, The order list endpoint queries user information one-by-one in a loop.

```go
func ListOrders(ctx context.Context) ([]*OrderVO, error) {
    orders, _ := orderRepo.FindAll(ctx)
    var result []*OrderVO
    for _, o := range orders {
        user, _ := userRepo.FindByID(ctx, o.UserID) // N+1 query
        result = append(result, toVO(o, user))
    }
    return result, nil
}
```

| Dimension | Verdict | Evidence |
| :--- | :--- | :--- |
| Impact Severity | **Severe** | Algorithmic complexity degrades from O(1) to O(N) DB calls, persistently slowing responses and exhausting the connection pool (complexity order degradation → Severe) |
| Blast Radius | **Module-level** | The order list is a high-frequency intra-module endpoint; once the connection pool is saturated it affects all DB operations within the module, multiple paths converge on this shared resource |
| Trigger Probability | **Likely** | Triggered by any normal visit to the order list; performance degrades as soon as there is more than one order (matches signal ⑤ reachable via normal input) |

**Priority**: High impact (Severe × Module-level) × Likely → **P1**, default block merge.
