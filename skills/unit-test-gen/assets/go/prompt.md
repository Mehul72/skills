# Go Language-Specific Prompt

## Go-Specific Filtering Rules

The following are Go language-specific function-level filtering rules (for general file-level exclusions, see `references/target-filter/AGENT.md`):

**Skip:**

- `init` functions, `main` functions
- Simple getter/setter with fewer than 3 lines

## Test File Naming Conventions

| Item         | Convention                                                       |
| ------------ | ---------------------------------------------------------------- |
| Test file    | `*_test.go`                                                      |
| Location     | Same directory and same package as the source file               |
| Package name | Prefer consistency with existing tests; if none, use source package name |
| Black-box    | If existing tests use `_test` suffix package name, follow it (e.g., `package foo_test`) |

---

## targets / results Organization Rules

The minimum execution unit in Go is the **package**. One JSON file per package, flat in the targets/ and results/ directories.

### File Naming

Replace `/` in the package path with `#`, e.g.:
- Package `service/user` → `service#user.json`
- Package `pkg/utils` → `pkg#utils.json`
- Root package `main` → `main.json`

### targets JSON Structure

```
${TMP_ROOT}/targets/
  ├── service#user.json
  ├── service#order.json
  └── pkg#utils.json
```

Each file is organized in three levels: `package` → `files[]` → `functions[]`:

| Field | Type | Required | Description |
|------|------|:----:|------|
| `package` | string | ✅ | Package path (original path, separated by `/`) |
| `files` | array | ✅ | List of source files in this package |
| `files[].file` | string | ✅ | Source file relative path (relative to `PROJECT_ROOT`) |
| `files[].functions` | array | ✅ | List of target functions in this file |
| `files[].functions[].function` | string | ✅ | Function name |
| `files[].functions[].line` | number | ✅ | Function starting line number |
| `files[].functions[].receiver` | string | ❌ | Receiver type name for methods |

#### targets Example

`${TMP_ROOT}/targets/service#user.json`:

```json
{
  "package": "service/user",
  "files": [
    {
      "file": "service/user/auth.go",
      "functions": [
        {"function": "Login", "line": 15, "receiver": "AuthService"},
        {"function": "Logout", "line": 78, "receiver": "AuthService"}
      ]
    },
    {
      "file": "service/user/profile.go",
      "functions": [
        {"function": "GetProfile", "line": 22, "receiver": "UserService"}
      ]
    }
  ]
}
```

### results JSON Structure

Mirrors targets with the same file names. Adds status, defects, and other result fields at the function level (field definitions in `references/output-contract/FORMATS.md`).

#### results Example (After Writer writes)

```json
{
  "package": "service/user",
  "files": [
    {
      "file": "service/user/auth.go",
      "functions": [
        {
          "function": "Login",
          "status": "generated",
          "test_file": "service/user/auth_test.go",
          "test_function": "TestLogin",
          "defects": [
            {
              "severity": "p0",
              "description": "err != nil 后仍使用了 user 字段",
              "location": "line 30-33",
              "scenario": "获取到有效记录时命中成功分支"
            }
          ]
        },
        {
          "function": "Logout",
          "status": "generated",
          "test_file": "service/user/auth_test.go",
          "test_function": "TestLogout"
        }
      ]
    }
  ]
}
```

---

## Execution Scheduling

Go uses the package as the basic unit for compilation and testing. The scheduling strategy aligns with this:

1. **Sequential by package**: `ls ${TMP_ROOT}/targets/` to get the full package list, process each package file in order
2. **Process files within a package**: Read the `files` array in the package JSON. Writer generates tests file by file and writes results to `${TMP_ROOT}/results/<pkg_name>.json`
3. **Package-level unified verification**: After all file Writers in the current package complete, dispatch Fixer to perform compilation check, run tests, failure triage, and fix for the package as a whole, updating the status in results file
4. After the current package's verify-and-fix completes, proceed to the next package

```
ls targets/ → [service#user.json, service#order.json, pkg#utils.json]

for each package file (sequential):
    ├── Read files list in targets/<pkg_name>.json
    ├── Dispatch Writer file by file
    │     ├── file_1: Writer workflow → write to results/<pkg_name>.json
    │     ├── file_2: Writer workflow → write to results/<pkg_name>.json
    │     └── file_3: Writer workflow → write to results/<pkg_name>.json
    └── Dispatch Fixer (package-level compile → run → triage → fix → update results)
```

### Verify-and-Fix Rounds

Fixer's verify-and-fix loop for each test file is limited to a maximum of **3 rounds**.

---

## Pre-Check (Must be completed before writing tests)

> **⚠️ Hard prerequisite**: Before generating any test code, this step's project learning **must** be completed. Different projects vary greatly in Mock frameworks and testing styles. Skipping this step almost certainly leads to repeated fixes later.

### 1. Environment Detection

1. **Check for multi-module project** (recommended): `find . -name "go.mod" -maxdepth 3` to confirm whether it's a multi-module project
   - In multi-module projects, `go test` needs to be run in the directory where the target module resides

### 2. Learn Project Testing Patterns

Learn the style of existing tests in the target function's directory (and adjacent directories):

1. **Scan existing test files** (required): Read 1-2 existing `*_test.go` files in the target function's directory to learn the following dimensions:
   - **Mock strategy**: Does the project use mockey, gomock, gomonkey, or interface injection?
   - **Assertion style**: testify/assert, testify/require, or standard library's `if got != want`?
   - **Naming conventions**: Actual naming patterns for test functions/scenario names
   - **Test case organization**: Table-driven, independent `t.Run`, or `Convey` nesting?
   - **Go version-related style**: Do existing tests use `tt := tt` (for loop variable capture in Go < 1.22)? Follow the existing style
   - When unable to find existing tests or determine the framework, prefer using the mockey framework and Convey framework
2. **Discover Test Helpers / Factories** (recommended): Search for reusable test assets in the project
   ```bash
   grep -rn "func.*Test\|func setup\|func new.*Test\|testHelper\|testdata\|testutil" --include="*_test.go" <target_dir>
   ```
   - If `testutil`, `testhelper`, `fixture` packages exist, prefer reusing them
3. **Read project conventions** (recommended): Check `AGENTS.md`, `CLAUDE.md` under `PROJECT_ROOT`
   - Extract unit-test-related requirements (naming conventions, Mock frameworks, directory structure, etc.)

### 3. Context Analysis

For each target function, gather sufficient context information:

1. **Layer 1 (required)**: Read the target function source code, understand function signature, parameter/return value type definitions
2. **Layer 2 (recommended)**: Read the interface definitions of dependency modules. Use `go doc <pkg>.<Symbol>` or Grep for the interface/struct declaration to pull the contract without reading whole files
3. **Layer 3 (as needed)**: When Layer 2 information is insufficient to determine mock strategy, Read indirect dependencies or type definition files

---

## Go Unit Test Standards

### Test Function Signature

- Test functions must start with `Test`, with signature `func TestXxx(t *testing.T)`
- `Xxx` must start with an uppercase letter, otherwise `go test` won't recognize it
- Benchmark tests use `func BenchmarkXxx(b *testing.B)`
- Example functions use `func ExampleXxx()`

### Package-Level Constraints

- The `package` declaration in test files must match the source files in the same directory (white-box testing), or use `packagename_test` (black-box testing)
- The same directory cannot have two different non-`_test` package names simultaneously
- `_test.go` files can access unexported functions/variables in the same package (white-box mode)

### Test Isolation Principles

- Each `t.Run` subtest must be independent, not depending on execution order or side effects of other subtests
- Passing state between subtests via package-level variables is forbidden
- When shared setup logic is needed, use `TestMain` or initialize independently within each subtest
- Mocks must be set up and cleaned within the subtest scope; leaking to other test cases is not allowed

### Error Handling Test Requirements

- For functions returning `error`, the error non-nil path must be covered
- Use `assert.NoError` / `assert.Error` to explicitly assert error state
- For specific error types, use `assert.ErrorIs` or `assert.ErrorAs` for precise matching
- Ignoring error return values is forbidden (i.e., `_ = SomeFunc()` without assertion afterward)

### nil/Zero Value Handling

- Pointer type parameters need to cover `nil` input scenarios
- slice/map parameters need to cover both `nil` and empty (`[]T{}`/`map[K]V{}`) scenarios
- string parameters need to cover empty string `""` scenarios
- Numeric parameters need to cover `0`, negative numbers, boundary values (e.g., `math.MaxInt64`) scenarios

### Concurrency Safety

- When using `t.Parallel()`, loop variables must be reassigned within the subtest closure (Go < 1.22)
- `t.Fatal` / `t.FailNow` is forbidden in concurrent tests (only allowed in the main goroutine)
- For tests involving shared resources, verify concurrency safety (e.g., using `sync.WaitGroup` + multiple goroutines calling concurrently)

### Assertion Standards

- Prefer `assert.Equal(t, expected, actual)`, note parameter order: **expected first, actual second**
- For floating-point comparison use `assert.InDelta(t, expected, actual, delta)`
- For containment checks use `assert.Contains`
- When all assertions need to execute, use `assert`; when you want to terminate on first failure, use `require`
- Prefer precise value comparison (`assert.Equal`), but when verifying a complex object is non-nil before asserting its fields, `assert.NotNil` is a reasonable prerequisite assertion

---

## Verification Methods

### Compilation Check

```bash
go build ./...
```

### Run Tests

```bash
go test -v -gcflags="all=-l -N" ./path/to/pkg/...
```

### Coverage Check

```bash
go test -v -gcflags="all=-l -N" -coverprofile=${TMP_ROOT}/coverage.out ./path/to/pkg/...
go tool cover -func=${TMP_ROOT}/coverage.out
```

---

## Go-Specific Defect Signals

> For complete defect determination rules, see `references/test-fixer/AGENT.md`. Only Go-specific supplementary signals are listed here (must be judged in context; cannot be directly determined as defects):

- `panic: runtime error: index out of range` → May be a slice out-of-bounds defect, **but only counts as a defect when the input comes from a normal business scenario**; triggered by tests intentionally passing an empty slice doesn't count
- `panic: runtime error: invalid memory address or nil pointer dereference` → May be a nil pointer defect, **but only counts as a defect when nil arises from the function's internal logic**; triggered by tests intentionally passing nil parameters doesn't count
- `panic: interface conversion` → May be a type assertion defect, **need to confirm whether mismatched types could occur in normal flow**
- `concurrent map read and map write` → Concurrency safety defect, **most likely a real defect**
- Assertion failure where expected value matches the correct semantics of the function → Logic defect, **most likely a real defect**

---

## Special Fix Rules

- If a dependency package's `init()` fails, check whether the project requires a blank-import side-effect package (look at how existing tests bootstrap) and add it
- If `go build` reports `undefined` errors, check whether required imports are missing
- If an `interface conversion` panic occurs in tests, check whether mock return value types match the interface definition
- If `concurrent map read and map write` occurs, add locks in the target code or test, or switch to `sync.Map`
- If `go.sum` is missing dependencies, run `go mod tidy`

---

## Formatting
- Code formatting priority: user instructions > AGENTS.md. If there are no formatting requirements, use goimports by default.
- See `assets/go/goimports/GUIDE.md` for detailed goimports usage.

---

## Code Style

Style is determined by priority: user instructions > AGENTS.md > existing tests in the same directory > defaults below.

| Item            | Convention                                                       |
| --------------- | ---------------------------------------------------------------- |
| Scenario/comment language | Match the surrounding code and existing tests |
| Naming          | `Test{Struct}{Method}` or `Test{Func}`; follow existing test names in the package |
| File            | `*_test.go` in the same directory as the source file, prefer appending to existing test files |
| Package name    | Consistent with existing tests; if none, use source package name |
| Assertion       | `github.com/stretchr/testify/assert` (or follow existing tests) |
| Mock            | `github.com/bytedance/mockey` (or follow existing tests)        |
| Test case organization | `t.Run` to expand sub-scenarios                           |
| Compile flags   | `-gcflags="all=-l -N"` (disable inlining, required by mockey)   |
| import grouping | stdlib → third-party → internal packages, separated by blank lines |

---

## mockey Usage

### Basic Structure

Nest `mockey.PatchConvey` inside `t.Run` to manage mock lifecycle:

```go
func TestFoo(t *testing.T) {
    t.Run("场景描述", func(t *testing.T) {
        mockey.PatchConvey("", t, func() {
            // 1. setup mock
            // 2. call target function
            // 3. assert results
        })
    })
}
```

### Mock Regular Functions

```go
func TestGetUserInfo(t *testing.T) {
    t.Run("正常获取用户信息", func(t *testing.T) {
        mockey.PatchConvey("", t, func() {
            mockey.Mock(QueryUserFromDB).Return(&User{
                ID:   1001,
                Name: "张三",
            }, nil).Build()

            user, err := GetUserInfo(1001)

            assert.NoError(t, err)
            assert.Equal(t, "张三", user.Name)
            assert.Equal(t, int64(1001), user.ID)
        })
    })

    t.Run("数据库查询失败返回错误", func(t *testing.T) {
        mockey.PatchConvey("", t, func() {
            mockey.Mock(QueryUserFromDB).Return(nil, fmt.Errorf("connection refused")).Build()

            user, err := GetUserInfo(1001)

            assert.Error(t, err)
            assert.Nil(t, user)
            assert.Contains(t, err.Error(), "connection refused")
        })
    })
}
```

### Mock Struct Methods

```go
func TestUserServiceGetProfile(t *testing.T) {
    t.Run("正常获取用户资料", func(t *testing.T) {
        mockey.PatchConvey("", t, func() {
            mockey.Mock((*UserDAO).FindByID).Return(&UserProfile{
                Name:  "李四",
                Email: "lisi@example.com",
            }, nil).Build()

            svc := &UserService{}
            profile, err := svc.GetProfile(1001)

            assert.NoError(t, err)
            assert.Equal(t, "李四", profile.Name)
            assert.Equal(t, "lisi@example.com", profile.Email)
        })
    })
}
```

### Conditional Mock (Return different results based on input)

```go
func TestBatchGetUsers(t *testing.T) {
    t.Run("不同用户ID返回不同结果", func(t *testing.T) {
        mockey.PatchConvey("", t, func() {
            mockey.Mock(QueryUserFromDB).To(func(id int64) (*User, error) {
                switch id {
                case 1:
                    return &User{ID: 1, Name: "用户A"}, nil
                case 2:
                    return &User{ID: 2, Name: "用户B"}, nil
                default:
                    return nil, fmt.Errorf("用户不存在: %d", id)
                }
            }).Build()

            users, errs := BatchGetUsers([]int64{1, 2, 999})

            assert.Equal(t, 2, len(users))
            assert.Equal(t, 1, len(errs))
            assert.Contains(t, errs[0].Error(), "用户不存在")
        })
    })
}
```

### Mock Anti-Patterns (Forbidden)

- ❌ Mock simple utility functions (e.g., `strings.TrimSpace`) → ✅ Call directly, no mock needed
- ❌ Mock same-package helpers called by the target function → ✅ Only mock external dependencies (DB/RPC), let internal logic execute naturally
- ❌ Mock all dependencies turning tests into "verify call order" → ✅ Only mock uncontrollable external dependencies
- ❌ Mock return value type doesn't match the real signature → ✅ Mock return values must match the function signature

---

## Examples

### Example 1: Table-Driven Tests (Recommended Pattern)

Target function:

```go
func Add(a, b int) int {
    return a + b
}
```

Test code:

```go
func TestAdd(t *testing.T) {
    tests := []struct {
        name     string
        a, b     int
        expected int
    }{
        {"两个正数相加", 1, 2, 3},
        {"正数加负数", 5, -3, 2},
        {"两个负数相加", -1, -2, -3},
        {"加零", 10, 0, 10},
        {"两个零相加", 0, 0, 0},
        {"大数相加", math.MaxInt32, 1, math.MaxInt32 + 1},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got := Add(tt.a, tt.b)
            assert.Equal(t, tt.expected, got)
        })
    }
}
```

---

## Common Pitfalls and Fixes

| Pitfall                                         | Cause                                                  | Fix                                                                |
| ----------------------------------------------- | ------------------------------------------------------ | ------------------------------------------------------------------ |
| `mockey.Mock` not taking effect                 | Compile-time inlining optimization, mock patch cannot take effect | Must use `-gcflags="all=-l -N"` to disable inlining               |
| Mock outside `PatchConvey` leaks to other subtests | Mock not managed within `PatchConvey` scope            | All mocks must be inside the `PatchConvey` callback function       |
| `assert.Equal` fails for `time.Time` comparison | `time.Time` contains monotonic clock information       | Use `assert.WithinDuration` or `time.Truncate`                     |
| Table-Driven loop variable capture issue (Go < 1.22) | Closure captures the reference to loop variable, not the value | Add `tt := tt` reassignment before `t.Run`                         |
| `interface conversion: xxx is nil, not yyy`     | Mock returned `nil` but caller did type assertion       | Mock return value must match interface definition, or return correct zero-value instance |
| Tests affecting each other                       | Package-level variable modified without restoration    | Initialize independently within each subtest, or use `t.Cleanup` to restore |
| `go test -race` reports data race               | Concurrent access to shared variables in tests          | Use `sync.Mutex` / `atomic` to protect, or avoid using `t.Fatal` in concurrent code |
| `import cycle not allowed`                       | Test file imports a package causing circular dependency  | Use `_test` suffix package name for black-box testing to break circular dependency |
| `package xxx is not in std` OR `no tests to run` | Go multi-module project                                | For multi-module projects, use the module's directory as the working directory for go test (consider cd-ing into the directory) |

---

## Context Discovery Commands

```bash
go list ./...
go doc <package>.<Function>
go test -cover ./<package>/...
cat go.mod
```
