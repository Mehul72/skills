---
name: issue-severity-triage
description: Classify the severity of code defects found during unit test generation. Through "Impact Severity", "Blast Radius", and "Trigger Probability" three-dimension code analysis, output P0-P3 priority. Load this document on-demand only when defects are found.
---

# Defect Severity Classification Specification

## Table of Contents

- [Applicable Scenarios](#applicable-scenarios)
- [Assessment Flow](#assessment-flow)
- [Three-Dimension Definitions](#three-dimension-definitions)
- [Assessment Matrix](#assessment-matrix)
- [Output Format](#output-format)
- [Reference Documents](#reference-documents)
- [bug_type Mapping](#bug_type-mapping)

---

## Applicable Scenarios

This document is loaded at the following times:
- After Test Writer discovers code defects, to classify defect severity
- After Test Fixer confirms production code defects during failure triage, to classify defect severity

**Loading principle**: Load this document for classification only after confirming a defect truly exists. Do not load when no defects are found.

---

## Assessment Flow

1. **Assess Impact Severity**: What is the damage scale when the issue is triggered? (Catastrophic / Severe / Limited / Minor)
2. **Assess Blast Radius**: How far does the damage spread? (Broad / Module-level / Local / Contained)
3. **Look up Table 1**: Calculate "Impact Level" (Critical / High / Medium / Low)
4. **Assess Trigger Probability**: How easily is it triggered? (Certain / Likely / Unlikely / Rare)
5. **Look up Table 2**: Determine "Final Priority" (P0 / P1 / P2 / P3)
6. **Category and Reference Cross-Validation (MUST execute)**:
   1. Determine the primary category from the §5 reference document table based on the problem symptoms
   2. Use the file read tool to **actually read** the corresponding reference document (path: `${SKILL_ROOT}/references/issue-severity-triage-refs/<filename>`). Read only one reference document at a time.
   3. Match the closest secondary sub-category in the reference document, record its Typical Profile as an anchor
   4. Cross-validate the final priority from step 5 against the reference anchor; if there is a discrepancy, explain the reason

---

## Three-Dimension Definitions

### ① Impact Severity

| Level | Definition |
| :--- | :--- |
| **Catastrophic** | Irreversible damage, security boundary penetration, or complete loss of functionality availability |
| **Severe** | Damage persists beyond a single request, functionality partially available but continuously producing errors or degradation |
| **Limited** | Affects correctness of a single request only under specific conditions, with fallback mechanisms available |
| **Minor** | Does not affect any request's correctness, data integrity, or security |

**Typical Consequences and Impact Severity Mapping:**

| Consequence Type | Impact Severity |
|----------|----------|
| Process crash / Build failure / Startup failure / Deadlock | Catastrophic |
| Irreversible persistent data corruption / Complete functionality unavailability / Authentication/authorization bypass / Credential leakage / Injection execution / Process-level resource exhaustion | Catastrophic |
| Recoverable persistent data error / In-memory data corruption / Contract violation / Security mechanism weakening / Module-level resource exhaustion / Complexity order degradation / Undetectable failure | Severe |
| Single data error / Single request failure / Single result deviation / Low-sensitivity information leakage / Delayed resource release / Bounded performance overhead / Detectable but hard-to-locate failure | Limited |
| Minor resource waste / Log noise / Insufficient diagnostic information / Readability degradation / Dead code / Debug remnants / Potential technical debt | Minor |

### ② Blast Radius

Combine "structural spread scope" with "path business criticality"; take the higher.

| Level | Definition |
| :--- | :--- |
| **Broad** | Impact spreads across module boundaries, or blocks a core business flow |
| **Module-level** | Impact limited to a single module but spans multiple paths, or involves implicit spread operations (authentication/authorization/persistent writes) |
| **Local** | Impact limited to a single non-critical path, no shared state or external side effects |
| **Contained** | No active callers, or only affects static properties (dead code, naming, comments) |

### ③ Trigger Probability

| Level | Definition | Determination Signals |
| :--- | :--- | :--- |
| **Certain** | On a mandatory path, triggered unconditionally | Unconditional main path / Exposed at compile time / Unconditional initialization path / Always-true or always-false condition |
| **Likely** | Reachable with normal input | Normal conditional branch / Default state / Common input format |
| **Unlikely** | Triggered under specific boundary conditions or rare states | Boundary conditions / Multiple conditions simultaneously met / Concurrent timing / Exception handling path |
| **Rare** | Almost impossible to trigger in current context | All callers cannot produce triggering input / Deployment environment doesn't meet conditions / Requires actively constructing malicious input |

---

## Assessment Matrix

### Table 1: Impact Level (Impact Severity × Blast Radius)

| | Broad | Module-level | Local | Contained |
| :--- | :--- | :--- | :--- | :--- |
| **Catastrophic** | Critical | Critical | High |, |
| **Severe** | Critical | High | Medium |, |
| **Limited** | High | Medium | Low |, |
| **Minor** | Medium | Low | Low | Low |

> ", " indicates a logically contradictory combination; fall back and reassess.

### Table 2: Final Priority (Impact Level × Trigger Probability)

| | Certain | Likely | Unlikely | Rare |
| :--- | :--- | :--- | :--- | :--- |
| **Critical** | **P0** | **P0** | **P1** | **P2** |
| **High** | **P0** | **P1** | **P1** | **P3** |
| **Medium** | **P1** | **P1** | **P2** | **P3** |
| **Low** | **P2** | **P2** | **P3** | **P3** |

---

## Output Format

After classification is complete, fill the result into the defect's `severity` field (`p0` / `p1` / `p2` / `p3`), and include a brief summary of the three-dimension assessment rationale in `evidence`. Format:

```
<original evidence description>. [Triage: <Impact Severity> × <Blast Radius> × <Trigger Probability> → <Impact Level> → P<N>; Reference category: <primary category>/<secondary sub-category>]
```

---

## Reference Documents

The following reference documents are organized by problem primary category, providing P0-P3 anchors per secondary category for cross-validation.

| Primary Category | Reference File | Typical P0 Profile |
| :--- | :--- | :--- |
| **Control Flow Errors** | `issue-severity-triage-refs/control-flow-errors.md` | Catastrophic × Broad/Module × Certain |
| **Data & Type Errors** | `issue-severity-triage-refs/data-type-errors.md` | Catastrophic × Module+ × Likely |
| **Interface & Contract Errors** | `issue-severity-triage-refs/interface-contract-errors.md` | Catastrophic × Module+ × Likely |
| **Concurrency & Resource Errors** | `issue-severity-triage-refs/concurrency-resource-errors.md` | Catastrophic × Broad × Certain |
| **Security Vulnerabilities** | `issue-severity-triage-refs/security-vulnerabilities.md` | Catastrophic × Broad × Likely |
| **Data Persistence Errors** | `issue-severity-triage-refs/data-persistence-errors.md` | Catastrophic × Module-level × Certain |
| **Build & Environment Errors** | `issue-severity-triage-refs/build-environment-errors.md` | Catastrophic × Broad × Certain |
| **Completeness Errors** | `issue-severity-triage-refs/completeness-errors.md` | Catastrophic × Module-level × Certain |
| **Maintainability Issues** | `issue-severity-triage-refs/maintainability-issues.md` | Severe × Module × Likely |

**Usage**:
1. After completing the three-dimension assessment and table lookup to determine final priority, identify the primary category from the table above
2. **Read** the corresponding reference document (path: `${SKILL_ROOT}/references/issue-severity-triage-refs/<filename>`), match the closest secondary sub-category
3. Cross-validate the final priority against the reference anchor; if there is a discrepancy, explain in evidence

---

## bug_type Mapping

Correspondence between defect `bug_type` field and primary categories:

| bug_type | Corresponding Primary Category |
|----------|-------------|
| `Logic Errors` | Control Flow Errors |
| `Boundary Errors` | Data & Type Errors |
| `Error Handling` | Interface & Contract Errors |
| `Concurrency` | Concurrency & Resource Errors |
| `Resource` | Concurrency & Resource Errors |
| `Security` | Security Vulnerabilities |
| `Business Gaps` | Completeness Errors |
| `Other Type` | Choose the closest primary category based on specific symptoms |
