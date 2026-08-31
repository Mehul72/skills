# Security Vulnerabilities, P0-P3 Triage Rules

> This file is a referenced rule file for the `issue-severity-triage` Skill.
> It covers P0-P3 triage criteria (combining consequence severity, blast radius, and trigger probability) for **security vulnerabilities** (3 sub-categories).
>
> **How to use this file:**
> 1) First complete the independent three-dimension assessment (SKILL.md §5) and table lookup (§6) to determine the preliminary priority.
> 2) Use this reference to cross-validate: find the closest sub-category and Typical Profile row below.
> 3) If the independent assessment differs from the reference anchor, explain the reason in the 【分类与参考验证】section.

---

## Data / Interface Exposure Errors

| Priority | Typical Profile | Description | Example |
| --- | --- | --- | --- |
| **P0** | Catastrophic × Broad × Likely | Access control baseline for core data or high-risk capabilities is broken; structurally exposed to external or cross-module callers, and the compromised path sits on a core business flow, sensitive data or critical operations are completely out of control. | The user details query interface forgets to add permission validation, allowing traversal of user IDs to obtain all users' sensitive information. |
| **P1** | Severe × Module × Likely | Permission granularity is too coarse or authentication conditions have obvious defects at important interfaces; the exposure is structurally contained within a module but involves auth-sensitive operations whose compromise implicitly spreads, under normal access paths persistently produces privilege escalation or leakage of important capabilities. | The "system configuration" interface that should only be visible to administrators is also open to regular users. |
| **P2** | Limited × Local × Unlikely | Interfaces return excessive fields, internal identifiers, or information beyond the minimum necessary scope; structurally limited to specific endpoints not on core business paths, does not directly constitute high-risk leakage, but amplifies information gathering risk. Fallback mechanisms exist. | Production environment API error responses contain detailed database errors and code line numbers. |
| **P3** | Minor × Contained × Rare | Exposure surface design is not restrained enough or information minimization is not thorough enough; no active business path is affected, actual exploitation value is currently low and only affects security governance consistency. | An internal debug interface returns the framework version number and non-sensitive build information, which is unnecessary for business functionality. |

---

## Unsafe Code Execution

| Priority | Typical Profile | Description | Example |
| --- | --- | --- | --- |
| **P0** | Catastrophic × Broad × Likely | Directly exploitable execution surface is formed; external input can stably penetrate SQL, command, template, script, or interpreter execution paths, structurally reachable from external callers across module boundaries, and the compromised path grants access to core data and system capabilities. | The username field of the login interface is directly concatenated into the SQL query string. |
| **P1** | Severe × Module × Likely | External input can stably affect page execution, script execution, template rendering, or dynamic interpretation on important features; structurally scoped within a module but the affected path serves user-facing or auth-related functions, causes session hijacking, privilege escalation, or important feature distortion. | User comment content is rendered directly in the page template without filtering. |
| **P2** | Limited × Local × Unlikely | A potentially unsafe execution surface exists, but requires additional prerequisites, special configuration, or combined exploitation to trigger; structurally limited to a specific code path not on a core business flow, the current risk is real but exploitation difficulty is high and the impact is limited. | Using a library's XML parsing functionality that has an XXE vulnerability under specific configuration, but the code does not use that configuration. |
| **P3** | Minor × Contained × Rare | Execution surface convergence is incomplete or whitelist / isolation boundary design is not stable enough; no active business path is affected and no directly exploitable vulnerability can form in the short term, a security baseline issue needing long-term governance. | An internal script tool still retains broad command whitelist matching logic, but the input source has been constrained to fixed constants. |

---

## Credential / Secret Exposure

| Priority | Typical Profile | Description | Example |
| --- | --- | --- | --- |
| **P0** | Catastrophic × Module+ × Certain | Sensitive credentials, keys, or production-level secrets are hardcoded directly into code or artifacts; the leaked credentials grant access to core systems, once pushed to version control, implicitly spreads to all data consumers of the compromised system. | `String pwd = "prod_db_password";`. |
| **P1** | Severe × Module × Likely | Non-production but security-sensitive credentials (internal API tokens, OAuth client secrets for staging, service-to-service shared keys) are hardcoded in source code or committed configuration; the leaked credential does not directly grant production-level access but can be leveraged for lateral movement, privilege escalation, or staging-environment compromise, structurally scoped within a module but the exposed credential path serves authentication-sensitive operations whose compromise implicitly spreads trust boundary violations. | `var sec = "stg_client_sec_abc123"` hardcoded in a service initializer; not a production secret but grants access to the staging OAuth provider. |
| **P2** | Limited × Local × Unlikely | Non-production test credentials, internal-only tokens, or demo secrets appear in code; structurally limited to specific code paths and not directly deployable to production, reduces security posture but exploitation requires additional context. | A test file contains a hardcoded API key for the staging environment. |
| **P3** | Minor × Contained × Rare | Credential management patterns are not clean enough; no actual secret is exposed, mainly affects security governance consistency. | Configuration loading code does not validate that secrets come from a secure source (env var / vault), but currently all callers do pass secrets correctly. |

---

## Triage Examples

### Example 1: User details endpoint has no authentication → P0

**Defect**: `handler/user.go:34`, The user details query endpoint performs no permission check; any caller can enumerate `userID` values to obtain all users' sensitive information.

```go
func GetUserDetail(ctx context.Context, req *GetUserReq) (*GetUserResp, error) {
    user, err := userRepo.FindByID(ctx, req.UserID) // no authentication check
    return &GetUserResp{Phone: user.Phone, IDCard: user.IDCard}, err
}
```

| Dimension | Verdict | Evidence |
| :--- | :--- | :--- |
| Impact Severity | **Catastrophic** | Authentication / authorization bypass, untrusted input can completely circumvent authorization and read user private data (auth bypass → Catastrophic) |
| Blast Radius | **Broad** | The endpoint is a public HTTP API accessible by any external caller; the leaked data covers the entire user table, structurally it is exposed to all external consumers, and from a business perspective it directly compromises core user data |
| Trigger Probability | **Likely** | Simply constructing sequential userIDs reliably triggers the leak; no special preconditions required (matches signal ⑤ reachable via normal input) |

**Priority**: Critical impact (Catastrophic × Broad) × Likely → **P0**, block merge.

---

### Example 2: Error response exposes stack trace → P1

**Defect**: `middleware/error_handler.go:22`, Production API error responses include full stack traces and database connection strings.

```go
func ErrorHandler(ctx context.Context, err error) {
    ctx.JSON(500, map[string]interface{}{
        "error":   err.Error(),
        "stack":   fmt.Sprintf("%+v", err),
    })
}
```

| Dimension | Verdict | Evidence |
| :--- | :--- | :--- |
| Impact Severity | **Limited** | Exposes internal paths and stack traces (non-credential information); widens the attack surface but does not directly constitute data leakage (low-sensitivity information exposure → Limited) |
| Blast Radius | **Broad** | Sits in the global error-handling middleware, a path traversed by all endpoint error responses; any 500 error leaks internal details to external callers across the entire service |
| Trigger Probability | **Unlikely** | Only exposed when a request triggers a 500 error (matches signal ⑪ triggered on exception-handling path) |

**Priority**: High impact (Limited × Broad) × Unlikely → **P1**, default block merge.
