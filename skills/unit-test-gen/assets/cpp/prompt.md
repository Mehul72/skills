# C++ Language-Specific Prompt

## Function Extraction Methods

| Tool/Method | Description                              |
| ----------- | ---------------------------------------- |
| `grep`      | Quickly locate function declarations     |
| `ctags`     | Generate symbol index, extract function list |
| `clangd`    | LSP precisely parses class and function structures |
| `nm`        | View symbol table in compiled artifacts  |

## Filtering Rules (C++-Specific)

**Skip:**

- `main` function
- Auto-generated code files (Proto-generated files, `*.pb.h`/`*.pb.cc`, etc.)
- Files containing `// Code generated` or `@generated` comments
- Pure template specializations (header-only simple getter/setter with no side effects)
- Simple getter/setter with fewer than 3 lines

## Test File Naming Conventions

| Item      | Convention                                                    |
| --------- | ------------------------------------------------------------- |
| Test file | `*_test.cpp` or `*_unittest.cpp`                              |
| Location  | Same directory as source file or under `test/` (follow existing conventions) |
| Header    | Test file directly `#include`s the header file corresponding to the source under test |

---

## targets / results Organization Rules

The minimum execution unit in C++ is the **test target (test binary)**. One JSON file per test target, flat in the targets/ and results/ directories.

A test target is the smallest independently compilable and runnable test unit, corresponding to a CMake `add_executable` / `add_test` entry, or a Bazel `cc_test` rule.

### File Naming

Use the test target name. If it contains path separators, replace `/` with `#`:

- `user_service_test` → `user_service_test.json`
- `service/user_service_test` (Bazel-style) → `service#user_service_test.json`

### targets JSON Structure

```
${TMP_ROOT}/targets/
  ├── user_service_test.json
  ├── auth_service_test.json
  └── string_util_test.json
```

Each file contains one test target and the source functions to be tested:

| Field | Type | Required | Description |
|------|------|:----:|------|
| `target` | string | ✅ | Test target name (CMake target name or Bazel target label) |
| `build_target` | string | ❌ | Compile target name (if different from `target`; omit when same) |
| `test_file` | string | ✅ | Test file relative path (relative to `PROJECT_ROOT`) |
| `files` | array | ✅ | List of source files under test |
| `files[].file` | string | ✅ | Source file relative path (.cpp/.cc) |
| `files[].header` | string | ❌ | Corresponding header file path (.h/.hpp) |
| `files[].functions` | array | ✅ | Target functions in this source file |
| `functions[].function` | string | ✅ | Function/method name |
| `functions[].line` | number | ✅ | Function starting line number (in the .cpp file) |
| `functions[].class` | string | ❌ | Class name (for member functions; omit for free functions) |
| `functions[].signature` | string | ❌ | Function signature for distinguishing overloads (e.g., `Find(const std::string&)` vs `Find(int64_t)`) |

#### targets Example

`${TMP_ROOT}/targets/user_service_test.json`:

```json
{
  "target": "user_service_test",
  "test_file": "test/service/user_service_test.cpp",
  "files": [
    {
      "file": "src/service/user_service.cpp",
      "header": "src/service/user_service.h",
      "functions": [
        {"function": "GetUser", "line": 25, "class": "UserService", "signature": "GetUser(int64_t)"},
        {"function": "UpdateUser", "line": 58, "class": "UserService", "signature": "UpdateUser(const User&)"},
        {"function": "DeleteUser", "line": 90, "class": "UserService"}
      ]
    }
  ]
}
```

Multi-source-file target example (`${TMP_ROOT}/targets/string_util_test.json`):

```json
{
  "target": "string_util_test",
  "test_file": "test/utils/string_util_test.cpp",
  "files": [
    {
      "file": "src/utils/string_util.cpp",
      "header": "src/utils/string_util.h",
      "functions": [
        {"function": "Split", "line": 12, "signature": "Split(const std::string&, char)"},
        {"function": "Trim", "line": 45},
        {"function": "ToLower", "line": 62}
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
  "target": "user_service_test",
  "test_file": "test/service/user_service_test.cpp",
  "files": [
    {
      "file": "src/service/user_service.cpp",
      "header": "src/service/user_service.h",
      "functions": [
        {
          "function": "GetUser",
          "line": 25,
          "class": "UserService",
          "signature": "GetUser(int64_t)",
          "status": "passed",
          "test_file": "test/service/user_service_test.cpp",
          "test_function": "TEST_F(UserServiceTest, GetUser_正常获取用户信息)"
        },
        {
          "function": "UpdateUser",
          "line": 58,
          "class": "UserService",
          "signature": "UpdateUser(const User&)",
          "status": "passed",
          "test_file": "test/service/user_service_test.cpp",
          "test_function": "TEST_F(UserServiceTest, UpdateUser_正常更新用户)"
        },
        {
          "function": "DeleteUser",
          "line": 90,
          "class": "UserService",
          "status": "generated",
          "test_file": "test/service/user_service_test.cpp",
          "test_function": "TEST_F(UserServiceTest, DeleteUser_正常删除)",
          "defects": [
            {
              "severity": "p1",
              "description": "DeleteUser 未检查 user_id <= 0 的情况，直接传给 DAO 导致未定义行为",
              "location": "line 92-95",
              "scenario": "传入 0 或负数 id 时应返回错误码而非继续执行"
            }
          ]
        }
      ]
    }
  ]
}
```

### Handling New Test Files (CMakeLists.txt Registration)

When the test target does not yet exist (new test file needs to be created):

1. Create the test file (e.g., `test/service/user_service_test.cpp`)
2. Register the test target in the appropriate `CMakeLists.txt` (typically `test/CMakeLists.txt`):
   - This is **allowed**, test build configuration is not production code
   - Follow existing patterns in the same `CMakeLists.txt` for `add_executable` and `target_link_libraries`
3. For Bazel projects, add a `cc_test` rule in the corresponding `BUILD` file

---

## Execution Scheduling

C++ uses the test target as the basic unit for task dispatch. The scheduling strategy:

1. **Sequential by target**: `ls ${TMP_ROOT}/targets/` to get the full target list, process each test target in order
2. **Writer generates per target**: Writer reads the `files[].functions` arrays, generates test cases into the test file, and writes results to `${TMP_ROOT}/results/<target_name>.json`
3. **Fixer verifies per target**: After Writer completes, dispatch Fixer to compile the target, run the test binary, triage failures, and fix, updating the status in results file

```
ls targets/ → [user_service_test.json, auth_service_test.json, string_util_test.json, ...]

for each target file (sequential):
    ├── Read targets/<target_name>.json
    ├── Dispatch Writer → generate/update test file → write to results/<target_name>.json
    └── Dispatch Fixer (compile target → run test binary → triage → fix → update results)
```

### Verify-and-Fix Rounds

Fixer's verify-and-fix loop for each test target is limited to a maximum of **3 rounds**.

> **Note**: C++ compilation is significantly more expensive than other languages. Writer should strive for correctness in the first generation to minimize Fixer iterations.

---

## Pre-Check (Must be completed before writing tests)

> **⚠️ Hard prerequisite**: Before generating any test code, this step's project learning **must** be completed. C++ projects have extremely diverse build configurations, library choices, and coding conventions. Skipping this step almost certainly leads to compilation failures.

### 1. Environment Detection

1. **Detect build system**: Check for `CMakeLists.txt` (CMake) or `BUILD` / `BUILD.bazel` (Bazel) or `Makefile`
2. **Locate build directory** (CMake): Check for `build/`, `cmake-build-debug/`, `out/`, needed for compile commands
3. **Detect test framework**: Confirm Google Test (default) vs Catch2 vs Boost.Test. Check linked libraries in test `CMakeLists.txt` or existing test includes
4. **Detect C++ standard**: Check `CMAKE_CXX_STANDARD` or `-std=c++XX` flags, affects available features (concepts, ranges, std::expected, etc.)
5. **Identify existing test targets**: Parse `CMakeLists.txt` or `BUILD` to find existing test targets and their naming patterns

### 2. Learn Project Testing Patterns

Learn the style of existing tests in the target's test directory:

1. **Scan existing test files** (required): Read 1-2 existing `*_test.cpp` or `*_unittest.cpp` files to learn:
   - **Test framework**: Google Test `TEST`/`TEST_F` vs Catch2 `TEST_CASE`/`SECTION`?
   - **Mock strategy**: Google Mock (`MOCK_METHOD`), custom fakes, or dependency injection without mocks?
   - **Fixture patterns**: `TEST_F` with fixture classes, or independent `TEST` tests?
   - **Naming conventions**: Actual naming patterns for test suites and test cases
   - **Include patterns**: How headers are included, relative paths vs absolute
2. **Inspect CMakeLists.txt patterns** (required):
   - How are test targets registered? (`add_executable` + `add_test`, or `gtest_discover_tests`?)
   - What libraries are linked? (`target_link_libraries(... gtest gmock gtest_main ...)`)
   - Is there a common test utility library or helper target?
3. **Read project conventions** (recommended): Check `AGENTS.md`, `CLAUDE.md` under `PROJECT_ROOT`
   - Extract unit-test-related requirements

### 3. Context Analysis

For each target function, gather sufficient context information:

1. **Layer 1 (required)**: Read the target function's **header declaration** (interface, parameter types, return type) and **implementation** (logic)
2. **Layer 2 (recommended)**: Read dependent interface headers (to define Mock classes for virtual function interfaces)
3. **Layer 3 (as needed)**: When Layer 2 information is insufficient, read transitive dependencies, struct/enum definitions, or template specializations

---

## C++ Unit Test Standards

### Test Naming Rules

- Test suite name (SuiteName) uses class name or module name in PascalCase
- Test case name (TestName) describes the test scenario in PascalCase or underscore-separated
- `TEST(SuiteName, TestName)` for independent tests without fixture
- `TEST_F(FixtureName, TestName)` for tests requiring shared setup/teardown
- `TEST_P(SuiteName, TestName)` for parameterized tests

### Test Isolation Principles

- Each `TEST` / `TEST_F` test case must be independent, not depending on execution order of other test cases
- `TEST_F` fixture is reconstructed before each test case (`SetUp`) and destroyed after (`TearDown`)
- Passing state between test cases via global or static variables is forbidden
- Mock object lifecycle must be managed within a single test case

### Fixture Usage Standards

- When multiple tests need the same initialization logic, use `TEST_F` + Fixture class
- Fixture class inherits from `::testing::Test`
- Initialize resources in `SetUp()`, release resources in `TearDown()`
- Avoid complex initialization in Fixture constructor; prefer using `SetUp()`

### Assertion Standards

- `EXPECT_*` series: Continues executing subsequent assertions after failure (recommended as default)
- `ASSERT_*` series: Immediately terminates current test after failure (use when subsequent assertions depend on this result)
- Integer comparison uses `EXPECT_EQ` / `EXPECT_NE` / `EXPECT_LT` / `EXPECT_GT` / `EXPECT_LE` / `EXPECT_GE`
- Floating-point comparison uses `EXPECT_FLOAT_EQ` / `EXPECT_DOUBLE_EQ` or `EXPECT_NEAR(val1, val2, abs_error)`
- String comparison uses `EXPECT_STREQ` / `EXPECT_STRNE` (C-style strings) or `EXPECT_EQ` (`std::string`)
- Boolean values use `EXPECT_TRUE` / `EXPECT_FALSE`
- Prefer precise assertions (e.g., `EXPECT_NE(ptr, nullptr)`), but when verifying a complex object is non-null before asserting its fields, `EXPECT_TRUE(ptr != nullptr)` is an acceptable prerequisite assertion

### Error Handling Test Requirements

- Functions that throw exceptions use `EXPECT_THROW(expr, exception_type)` for assertion
- Normal paths that don't throw use `EXPECT_NO_THROW(expr)`
- Functions returning error codes must cover the non-zero error code path
- For `std::optional` / `std::expected` return values, cover both has-value and no-value scenarios

### nullptr/Empty Value Handling

- Pointer parameters need to cover `nullptr` input scenarios
- `std::string` parameters need to cover empty string `""` scenarios
- Container parameters need to cover empty container scenarios
- `std::optional` parameters need to cover `std::nullopt` scenarios
- Numeric parameters need to cover `0`, negative numbers, boundary values (e.g., `INT_MAX`, `INT_MIN`) scenarios

### Memory Safety

- Dynamically allocated resources in tests must be released before test case ends, or managed with smart pointers
- Use `EXPECT_DEATH` / `EXPECT_DEBUG_DEATH` to test fatal errors (only when needed)
- Recommend running tests with AddressSanitizer (`-fsanitize=address`)

---

## Verification Methods

> Determine the build system (CMake or Bazel) during Pre-Check and use the corresponding commands below.

### CMake

#### local-run

```bash
cmake --build <build_dir> --target <target>
ctest --test-dir <build_dir> -R <target> --output-on-failure
```

#### Compilation Check

```bash
cmake --build <build_dir> --target <target>
```

#### Run Tests

```bash
ctest --test-dir <build_dir> -R <target> --output-on-failure
```

Or run the test binary directly for verbose output:

```bash
<build_dir>/test/<target> --gtest_output=xml
```

#### Coverage Check

```bash
cmake --build <build_dir> --target <target> -- CXXFLAGS="--coverage"
ctest --test-dir <build_dir> -R <target>
lcov --capture --directory <build_dir> --output-file coverage.info
lcov --list coverage.info
```

### Bazel

#### local-run

```bash
bazel test //<package>:<target> --test_output=errors
```

#### Compilation Check

```bash
bazel build //<package>:<target>
```

#### Run Tests

```bash
bazel test //<package>:<target> --test_output=all
```

#### Coverage Check

```bash
bazel coverage //<package>:<target> --combined_report=lcov
```

---

## Special Fix Rules

- If compilation reports `undefined reference`, check whether CMakeLists.txt links the target under test
- If `multiple definition` occurs, check whether non-inline functions are defined in header files
- If Mock class reports `unimplemented pure virtual method`, ensure all pure virtual functions are covered by `MOCK_METHOD`
- If `EXPECT_DEATH` fails in non-debug mode, switch to `EXPECT_DEBUG_DEATH` or skip
- If `error: use of deleted function` occurs, check the copy/move semantics of the class under test

---

## Formatting

```bash
clang-format -i <file>
```

---

## Code Style

Style is determined by priority: user instructions > AGENTS.md > existing tests in the same directory > defaults below.

| Item            | Convention                                                           |
| --------------- | -------------------------------------------------------------------- |
| Scenario/comment language | Match the surrounding code and existing tests |
| Naming          | `TEST(SuiteName, TestName)` or `TEST_F`                              |
| File            | `<module>_test.cpp`, same directory as source file or under `test/`   |
| Assertion       | Google Test `EXPECT_EQ` / `ASSERT_EQ` (or follow existing tests)     |
| Mock            | Google Mock `MOCK_METHOD` (or follow existing tests)                  |
| Test case organization | Related test cases under the same `TEST_F` fixture             |
| include order   | Header under test → stdlib → third-party → project internal headers, separated by blank lines |

---

## Google Mock Usage

### Basic Structure

Define Mock class inheriting from interface, declare mock methods with `MOCK_METHOD`:

```cpp
class MockUserService : public UserService {
public:
    MOCK_METHOD(User*, GetUser, (int64_t id), (override));
    MOCK_METHOD(bool, UpdateUser, (const User& user), (override));
};
```

### Mock Virtual Function Interfaces

```cpp
class MockDatabase : public Database {
public:
    MOCK_METHOD(std::optional<Record>, Find, (const std::string& key), (override));
    MOCK_METHOD(bool, Insert, (const std::string& key, const Record& record), (override));
    MOCK_METHOD(bool, Delete, (const std::string& key), (override));
};

TEST_F(OrderServiceTest, 正常创建订单) {
    MockDatabase mockDB;
    OrderService service(&mockDB);

    EXPECT_CALL(mockDB, Insert(testing::_, testing::_))
        .WillOnce(testing::Return(true));

    auto result = service.CreateOrder("user_001", 9900);

    EXPECT_TRUE(result.has_value());
    EXPECT_EQ(result->amount, 9900);
}
```

### Setting Expectations and Return Values

```cpp
TEST_F(UserServiceTest, 正常获取用户信息) {
    MockUserDAO mockDAO;
    UserService service(&mockDAO);

    User expectedUser{1001, "张三", "zhangsan@example.com"};

    EXPECT_CALL(mockDAO, GetUser(1001))
        .Times(1)
        .WillOnce(testing::Return(&expectedUser));

    auto* user = service.FindUser(1001);

    ASSERT_NE(user, nullptr);
    EXPECT_EQ(user->name, "张三");
    EXPECT_EQ(user->email, "zhangsan@example.com");
}
```

### Mock Anti-Patterns (Forbidden)

- ❌ Mock simple utility functions (e.g., `std::sort`, `strlen`, math functions) → ✅ Call directly, no mock needed
- ❌ Mock non-virtual functions (impossible without link-seam tricks) → ✅ Use dependency injection with virtual interfaces
- ❌ Mock private member functions via hacks → ✅ Cover them indirectly through public interface
- ❌ Over-specify `EXPECT_CALL` with exact argument matchers when not needed → ✅ Use `testing::_` for irrelevant arguments
- ❌ Use `EXPECT_CALL` without verifying the actual output → ✅ Always assert the function's return value or side effects
- ❌ Create Mock classes for simple POD structs → ✅ Construct real objects directly for value types

---

## Examples

### Example 1: Parameterized Tests (Recommended Pattern)

Target function:

```cpp
int Add(int a, int b) {
    return a + b;
}
```

Test code:

```cpp
struct AddTestParam {
    std::string name;
    int a;
    int b;
    int expected;
};

class AddTest : public ::testing::TestWithParam<AddTestParam> {};

TEST_P(AddTest, 计算结果正确) {
    const auto& param = GetParam();
    EXPECT_EQ(Add(param.a, param.b), param.expected);
}

INSTANTIATE_TEST_SUITE_P(
    AddTestCases, AddTest,
    ::testing::Values(
        AddTestParam{"两个正数相加", 1, 2, 3},
        AddTestParam{"正数加负数", 5, -3, 2},
        AddTestParam{"两个负数相加", -1, -2, -3},
        AddTestParam{"加零", 10, 0, 10},
        AddTestParam{"两个零相加", 0, 0, 0},
        AddTestParam{"大数相加", INT_MAX - 1, 1, INT_MAX}
    ),
    [](const ::testing::TestParamInfo<AddTestParam>& info) {
        return info.param.name;
    }
);
```

### Example 2: TEST_F Fixture Organization (Multiple Scenarios for One Method)

Target function:

```cpp
// user_service.h
class UserService {
public:
    explicit UserService(UserDAO* dao);
    User* GetUser(int64_t id);
private:
    UserDAO* dao_;
};
```

```cpp
// user_service.cpp
User* UserService::GetUser(int64_t id) {
    if (id <= 0) {
        return nullptr;
    }
    return dao_->FindById(id);
}
```

Test code:

```cpp
#include "src/service/user_service.h"
#include "gmock/gmock.h"
#include "gtest/gtest.h"

class MockUserDAO : public UserDAO {
public:
    MOCK_METHOD(User*, FindById, (int64_t id), (override));
};

class UserServiceTest : public ::testing::Test {
protected:
    void SetUp() override {
        service_ = std::make_unique<UserService>(&mock_dao_);
    }

    MockUserDAO mock_dao_;
    std::unique_ptr<UserService> service_;
};

TEST_F(UserServiceTest, GetUser_正常获取用户信息) {
    User expected{1001, "张三"};
    EXPECT_CALL(mock_dao_, FindById(1001))
        .WillOnce(testing::Return(&expected));

    auto* result = service_->GetUser(1001);

    ASSERT_NE(result, nullptr);
    EXPECT_EQ(result->name, "张三");
}

TEST_F(UserServiceTest, GetUser_用户不存在返回nullptr) {
    EXPECT_CALL(mock_dao_, FindById(999))
        .WillOnce(testing::Return(nullptr));

    auto* result = service_->GetUser(999);

    EXPECT_EQ(result, nullptr);
}

TEST_F(UserServiceTest, GetUser_ID为零返回nullptr) {
    auto* result = service_->GetUser(0);
    EXPECT_EQ(result, nullptr);
}

TEST_F(UserServiceTest, GetUser_ID为负数返回nullptr) {
    auto* result = service_->GetUser(-1);
    EXPECT_EQ(result, nullptr);
}
```

---

## Common Pitfalls and Fixes

| Pitfall                                           | Cause                                                   | Fix                                                                |
| ------------------------------------------------- | ------------------------------------------------------- | ------------------------------------------------------------------ |
| `undefined reference to vtable`                   | Mock class doesn't implement all pure virtual functions  | Ensure all pure virtual methods are declared with `MOCK_METHOD`    |
| `EXPECT_CALL` not taking effect                   | Mock object not passed into target code via pointer/reference | Target code must hold Mock object via pointer/reference, cannot copy |
| `Uninteresting mock function call`                | Mock method called but no `EXPECT_CALL` set              | Add `EXPECT_CALL` or use `NiceMock<T>` to suppress warnings       |
| Floating-point `EXPECT_EQ` fails                  | Floating-point arithmetic precision issues               | Use `EXPECT_NEAR` or `EXPECT_DOUBLE_EQ`                            |
| `EXPECT_DEATH` unusable on some platforms         | Requires fork support, unavailable in some environments  | Use `GTEST_FLAG_SET(death_test_style, "threadsafe")` or skip       |
| Tests affecting each other                         | Global/static variables modified without restoration     | Reset in Fixture `TearDown`, or avoid using global state           |
| Link error `multiple definition`                   | Non-inline functions defined in header files             | Move function definitions to `.cpp` file, or add `inline` keyword  |
| Mock reports `unresolved expectation` on destruction | `EXPECT_CALL` expectations not fulfilled                | Check whether target code correctly calls mock methods, or adjust `Times` constraints |

---

## Context Discovery Commands

```bash
find . -name "*.h" -o -name "*.hpp" -o -name "*.cpp" | head -50
grep -rn "class.*:.*public" --include="*.h" --include="*.hpp" .
cat CMakeLists.txt
grep -rn "Mock\|Fake\|Stub" --include="*test*" .
grep -rn "TEST\|TEST_F\|TEST_P" --include="*test*" .
```
