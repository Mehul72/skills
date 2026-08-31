# Java Language-Specific Prompt

## Function Extraction Methods

| Tool/Method | Description                                                  |
| ----------- | ------------------------------------------------------------ |
| `grep`      | Quickly locate method signatures `public`/`protected`/`private` |
| IDE LSP     | Precisely parse class and method structures                   |
| `javap`     | View compiled class method signatures                         |

## Filtering Rules (Java-Specific)

**Skip:**

- `public static void main` entry methods
- Auto-generated code: `*Generated*`, Proto-generated files
- Lombok-generated getter/setter/toString/equals/hashCode (classes annotated with `@Data`, `@Getter`, etc.)
- Simple getter/setter with fewer than 3 lines
- `default` methods in interfaces (unless containing complex logic)

## Test File Naming Conventions

| Item       | Convention                                                        |
| ---------- | ----------------------------------------------------------------- |
| Test file  | `*Test.java`                                                      |
| Location   | Under `src/test/java/` in the corresponding package path          |
| Package    | Same as the class under test                                      |
| Test class | `{ClassName}Test` (e.g., `UserService` → `UserServiceTest`)      |

---

## targets / results Organization Rules

The minimum execution unit in Java is the **source class**. One JSON file per class, flat in the targets/ and results/ directories.

### File Naming

Use the fully qualified class name with `.` replaced by `#`. For multi-module projects, prefix with the module name:

- Single-module: `com.example.service.user.UserService` → `com#example#service#user#UserService.json`
- Multi-module: module `user-service`, class `com.example.service.user.UserService` → `user-service#com#example#service#user#UserService.json`

### targets JSON Structure

```
${TMP_ROOT}/targets/
  ├── user-service#com#example#service#user#UserService.json
  ├── user-service#com#example#service#user#AuthService.json
  └── order-service#com#example#service#order#OrderService.json
```

Each file contains a single class and its target methods:

| Field | Type | Required | Description |
|------|------|:----:|------|
| `class` | string | ✅ | Fully qualified class name |
| `module` | string | ❌ | Build module identifier (multi-module projects only; omit for single-module) |
| `file` | string | ✅ | Source file relative path (relative to `PROJECT_ROOT`) |
| `functions` | array | ✅ | List of target methods in this class |
| `functions[].function` | string | ✅ | Method name |
| `functions[].line` | number | ✅ | Method starting line number |
| `functions[].signature` | string | ❌ | Method signature for distinguishing overloaded methods (e.g., `updateProfile(Long, ProfileDTO)`) |

#### targets Example

`${TMP_ROOT}/targets/user-service#com#example#service#user#UserService.json`:

```json
{
  "class": "com.example.service.user.UserService",
  "module": "user-service",
  "file": "user-service/src/main/java/com/example/service/user/UserService.java",
  "functions": [
    {"function": "getProfile", "line": 30, "signature": "getProfile(Long)"},
    {"function": "updateProfile", "line": 55, "signature": "updateProfile(Long, ProfileDTO)"},
    {"function": "deleteUser", "line": 80}
  ]
}
```

### results JSON Structure

Mirrors targets with the same file names. Adds status, defects, and other result fields at the function level (field definitions in `references/output-contract/FORMATS.md`).

#### results Example (After Writer writes)

```json
{
  "class": "com.example.service.user.UserService",
  "module": "user-service",
  "file": "user-service/src/main/java/com/example/service/user/UserService.java",
  "functions": [
    {
      "function": "getProfile",
      "line": 30,
      "signature": "getProfile(Long)",
      "status": "passed",
      "test_file": "user-service/src/test/java/com/example/service/user/UserServiceTest.java",
      "test_function": "testGetProfile_正常获取用户资料"
    },
    {
      "function": "updateProfile",
      "line": 55,
      "signature": "updateProfile(Long, ProfileDTO)",
      "status": "generated",
      "test_file": "user-service/src/test/java/com/example/service/user/UserServiceTest.java",
      "test_function": "testUpdateProfile_正常更新",
      "defects": [
        {
          "severity": "p1",
          "description": "updateProfile 未校验 profileDTO 为 null 的情况，直接访问字段导致 NPE",
          "location": "line 58-60",
          "scenario": "传入 null ProfileDTO 时应抛出 IllegalArgumentException"
        }
      ]
    },
    {
      "function": "deleteUser",
      "line": 80,
      "status": "passed",
      "test_file": "user-service/src/test/java/com/example/service/user/UserServiceTest.java",
      "test_function": "testDeleteUser_正常删除"
    }
  ]
}
```

---

## Execution Scheduling

Java uses the class as the basic unit for task dispatch. The scheduling strategy:

1. **Sequential by class**: `ls ${TMP_ROOT}/targets/` to get the full class list, process each class file in order
2. **Writer generates per class**: Writer reads the `functions` array, generates one test class (or appends to an existing test class), and writes results to `${TMP_ROOT}/results/<class_name>.json`
3. **Fixer verifies per class**: After Writer completes, dispatch Fixer to compile the module, run the specific test class, triage failures, and fix, updating the status in results file

```
ls targets/ → [user-service#...#UserService.json, user-service#...#AuthService.json, ...]

for each class file (sequential):
    ├── Read targets/<class_name>.json
    ├── Dispatch Writer → generate/update test class → write to results/<class_name>.json
    └── Dispatch Fixer (compile module → run test class → triage → fix → update results)
```

### Verify-and-Fix Rounds

Fixer's verify-and-fix loop for each test class is limited to a maximum of **3 rounds**.

---

## Pre-Check (Must be completed before writing tests)

> **⚠️ Hard prerequisite**: Before generating any test code, this step's project learning **must** be completed. Different projects vary greatly in DI frameworks, Mock strategies, and testing styles. Skipping this step almost certainly leads to repeated fixes later.

### 1. Environment Detection

1. **Detect build tool**: Check whether the project uses Maven (`pom.xml`) or Gradle (`build.gradle` / `build.gradle.kts`)
2. **Check for multi-module project**: Look for multiple `pom.xml` or `build.gradle` files to confirm whether it's a multi-module project
   - In multi-module projects, compile and test commands need the module identifier (`-pl <module>` for Maven, `:<module>` for Gradle)
3. **Detect Java version** (recommended): Check `pom.xml` / `build.gradle` for source/target version, affects available syntax features (var, records, sealed classes, text blocks, etc.)

### 2. Learn Project Testing Patterns

Learn the style of existing tests in the target class's package (and adjacent packages):

1. **Scan existing test files** (required): Read 1-2 existing `*Test.java` files in the corresponding test directory to learn:
   - **Test framework**: JUnit 5 (`@Test` from `org.junit.jupiter`) vs JUnit 4 (`@Test` from `org.junit`)
   - **Mock strategy**: Mockito (`@Mock` + `@InjectMocks`), PowerMock, or manual stub classes?
   - **Assertion style**: JUnit 5 Assertions, AssertJ (`assertThat`), or Hamcrest matchers?
   - **DI pattern**: `@ExtendWith(MockitoExtension.class)`, `@SpringBootTest`, or constructor injection with manual mocks?
   - **Naming conventions**: Actual naming patterns for test methods
   - **Test case organization**: `@ParameterizedTest`, `@Nested` classes, or flat `@Test` methods?
2. **Discover Test Helpers / Factories** (recommended): Search for reusable test assets
   ```bash
   grep -rn "class.*TestBase\|class.*TestHelper\|class.*TestFactory\|@TestConfiguration" --include="*.java" <target_test_dir>
   ```
   - If `TestBase`, `TestHelper`, `TestFactory`, `TestFixture` classes exist, prefer reusing them
3. **Read project conventions** (recommended): Check `AGENTS.md`, `CLAUDE.md` under `PROJECT_ROOT`
   - Extract unit-test-related requirements (naming conventions, Mock frameworks, directory structure, etc.)

### 3. Context Analysis

For each target method, gather sufficient context information:

1. **Layer 1 (required)**: Read the target method source code, understand method signature, parameter/return value type definitions, class-level dependencies (`@Autowired` / constructor-injected fields)
2. **Layer 2 (recommended)**: Read the interface definitions of injected dependencies (to determine mock strategy and return types)
3. **Layer 3 (as needed)**: When Layer 2 information is insufficient, read indirect dependencies, DTO/Entity class definitions, or configuration classes

---

## Java Unit Test Standards

### Test Method Signature

- Use JUnit 5's `@Test` annotation to mark test methods
- Methods must have `void` return type, no parameters, non-`static`
- Method names follow `test<Method>_<scenario>` or `should<Expected>_when<Condition>` naming
- Recommended method access modifier is `package-private` (i.e., no modifier), no need for `public`

### Test Class Structure

- Test classes don't need to extend any base class (JUnit 5)
- Use `@BeforeEach` / `@AfterEach` instead of JUnit 4's `@Before` / `@After`
- Use `@BeforeAll` / `@AfterAll` to manage class-level resources (methods must be `static`)
- `@ExtendWith(MockitoExtension.class)` enables Mockito annotation support

### Test Isolation Principles

- Each `@Test` method must be independent, not depending on execution order of other tests
- Passing state between test methods via instance variables is forbidden (unless re-initialized in `@BeforeEach`)
- Mock objects are automatically reset before each test method execution (Mockito's default behavior)
- Using `@TestMethodOrder` to force test order for satisfying dependencies is forbidden

### Assertion Standards

- Prefer JUnit 5's `Assertions`: `assertEquals(expected, actual)`, note parameter order: **expected first, actual second**
- Or use AssertJ's fluent assertions: `assertThat(actual).isEqualTo(expected)` (follow existing tests)
- For floating-point comparison, use `assertEquals(expected, actual, delta)` or `assertThat(actual).isCloseTo(expected, within(delta))`
- For collection assertions, use `assertThat(list).hasSize(3).contains("a", "b")`
- For exception assertions, use `assertThrows(ExceptionType.class, () -> { ... })`
- Prefer precise value comparison (`assertEquals`/`isEqualTo`), but when verifying a complex object is non-null before asserting its fields, `assertNotNull` is a reasonable prerequisite assertion
- For complex object comparison, prefer `assertThat(actual).usingRecursiveComparison().isEqualTo(expected)`

### Exception Testing Requirements

- Methods that may throw exceptions must cover exception paths
- Use `assertThrows` to assert exception type and verify exception message:
  ```java
  Exception ex = assertThrows(IllegalArgumentException.class, () -> service.process(null));
  assertThat(ex.getMessage()).contains("不能为空");
  ```
- Using JUnit 4's `@Test(expected = ...)` syntax is forbidden

### null/Empty Value Handling

- Reference type parameters need to cover `null` input scenarios
- `String` parameters need to cover both empty string `""` and `null` scenarios
- `List`/`Map`/`Set` parameters need to cover both `null` and empty collection `Collections.emptyList()` scenarios
- `Optional` return values need to cover `Optional.empty()` scenarios
- Numeric parameters need to cover `0`, negative numbers, boundary values (e.g., `Integer.MAX_VALUE`) scenarios

### Access Control

- Test class and class under test are in the same package path, allowing access to `package-private` methods
- `private` methods are not tested directly; cover them indirectly through their public methods
- Using reflection to bypass access control for testing `private` methods is forbidden (except in extreme cases)

---

## Verification Methods

> Determine the build tool (Maven or Gradle) during Pre-Check and use the corresponding commands below.

### Maven

#### local-run

```bash
mvn test -pl <module> -Dtest=<TestClass>
```

#### Compilation Check

```bash
mvn compile -pl <module> -am
```

#### Run Tests

```bash
mvn test -pl <module> -Dtest=<TestClass>
```

#### Coverage Check

```bash
mvn test -pl <module> -Dtest=<TestClass> -Djacoco.skip=false
mvn jacoco:report -pl <module>
```

> For single-module projects, omit `-pl <module>`.

### Gradle

#### local-run

```bash
./gradlew :<module>:test --tests "<fully.qualified.TestClass>"
```

#### Compilation Check

```bash
./gradlew :<module>:compileTestJava
```

#### Run Tests

```bash
./gradlew :<module>:test --tests "<fully.qualified.TestClass>"
```

#### Coverage Check

```bash
./gradlew :<module>:test --tests "<fully.qualified.TestClass>" jacocoTestReport
```

> For single-module projects, omit `:<module>:` prefix (use `:test`, `:compileTestJava`, etc.).

---

## Special Fix Rules

**Failure Triage:**

> For complete defect determination rules, see the "Failure Triage Process" section in `references/test-fixer/AGENT.md`. Only Java-specific supplements are listed here.

**Java-Specific Defect Signals (must be judged in context; cannot be directly determined as defects):**
- `java.lang.NullPointerException` (not a Mock injection issue) → May be missing null guard, **but only counts as a defect when null arises from the method's internal logic**; triggered by tests intentionally passing null parameters doesn't count
- `java.lang.ArrayIndexOutOfBoundsException` → May be missing array boundary check, **but only counts as a defect when input comes from a normal business scenario**
- `java.lang.StringIndexOutOfBoundsException` → May be a string index out-of-bounds, **same as above**
- `java.lang.ArithmeticException: / by zero` → May be missing division-by-zero guard, **most likely a real defect**
- `java.lang.ClassCastException` → May be missing type check, **need to confirm whether mismatched types could occur in normal flow**
- `java.util.ConcurrentModificationException` → May be a concurrency safety issue, **most likely a real defect**
- `java.lang.StackOverflowError` → May be a recursion termination condition defect, **most likely a real defect**
- Assertion failure where expected value matches the correct semantics of the method → Logic defect, **most likely a real defect**

- If compilation reports `cannot find symbol`, check import statements and whether dependencies are declared in `pom.xml` / `build.gradle`
- If `NullPointerException` occurs instead of expected behavior, check whether mock objects are properly injected (`@InjectMocks` + `@Mock`)
- If Mockito reports `Unnecessary stubbings detected`, use `@MockitoSettings(strictness = Strictness.LENIENT)` or remove unused stubs
- If `org.mockito.exceptions.misusing.MissingMethodInvocationException` occurs, check whether final classes/methods are being mocked (requires `mockito-inline`)
- If Spring context loading fails, check whether necessary `@MockBean` declarations are missing

---

## Formatting

Follow project formatter configuration.

If the project has no unified formatter, Google Java Format is recommended:

```bash
google-java-format -i <file>
```

---

## Code Style

Style is determined by priority: user instructions > AGENTS.md > existing tests in the same directory > defaults below.

| Item            | Convention                                                            |
| --------------- | --------------------------------------------------------------------- |
| Scenario/comment language | Match the surrounding code and existing tests |
| Naming          | `test<Method>_<scenario>` (JUnit 5 `@Test`)                          |
| File            | `<ClassName>Test.java`, located at `src/test/java/` corresponding package path |
| Assertion       | `org.junit.jupiter.api.Assertions` or `AssertJ` (follow existing tests) |
| Mock            | `Mockito` (or follow existing tests)                                  |
| Test case organization | `@ParameterizedTest` + `@MethodSource` / `@CsvSource`          |
| import order    | static imports → stdlib → third-party → project internal packages, separated by blank lines |

---

## Mockito Usage

### Basic Structure

Use `@ExtendWith` + `@Mock` + `@InjectMocks` combination:

```java
@ExtendWith(MockitoExtension.class)
class UserServiceTest {

    @Mock
    private UserDAO userDAO;

    @Mock
    private CacheClient cacheClient;

    @InjectMocks
    private UserService userService;

    @Test
    void testGetUser_正常获取用户() {
        // 1. setup mock
        // 2. call target method
        // 3. assert results
        // 4. verify calls (optional)
    }
}
```

### Mock Method Return Values

```java
@Test
void testGetUser_正常获取用户() {
    User expectedUser = new User(1001L, "张三", "zhangsan@example.com");
    when(userDAO.findById(1001L)).thenReturn(Optional.of(expectedUser));

    User result = userService.getUser(1001L);

    assertEquals("张三", result.getName());
    assertEquals("zhangsan@example.com", result.getEmail());
    verify(userDAO).findById(1001L);
}

@Test
void testGetUser_用户不存在抛出异常() {
    when(userDAO.findById(999L)).thenReturn(Optional.empty());

    Exception ex = assertThrows(UserNotFoundException.class,
        () -> userService.getUser(999L));

    assertThat(ex.getMessage()).contains("用户不存在");
}
```

### Mock Method Throwing Exceptions

```java
@Test
void testGetUser_数据库查询失败() {
    when(userDAO.findById(anyLong()))
        .thenThrow(new RuntimeException("connection refused"));

    assertThrows(ServiceException.class,
        () -> userService.getUser(1001L));
}
```

### Conditional Mock (Return different results based on parameters)

```java
@Test
void testBatchGetUsers_不同ID返回不同结果() {
    when(userDAO.findById(1L)).thenReturn(Optional.of(new User(1L, "用户A")));
    when(userDAO.findById(2L)).thenReturn(Optional.of(new User(2L, "用户B")));
    when(userDAO.findById(999L)).thenReturn(Optional.empty());

    List<User> users = userService.batchGetUsers(List.of(1L, 2L, 999L));

    assertThat(users).hasSize(2);
    assertThat(users).extracting(User::getName).containsExactly("用户A", "用户B");
}
```

### Mock void Methods

```java
@Test
void testDeleteUser_正常删除() {
    doNothing().when(userDAO).deleteById(1001L);

    userService.deleteUser(1001L);

    verify(userDAO).deleteById(1001L);
}

@Test
void testDeleteUser_删除失败抛出异常() {
    doThrow(new RuntimeException("删除失败"))
        .when(userDAO).deleteById(anyLong());

    assertThrows(ServiceException.class,
        () -> userService.deleteUser(1001L));
}
```

### Mock Static Methods

```java
@Test
void testGenerateOrderNo_正常生成订单号() {
    try (MockedStatic<LocalDateTime> mockedTime = mockStatic(LocalDateTime.class)) {
        LocalDateTime fixedTime = LocalDateTime.of(2024, 1, 15, 10, 30, 0);
        mockedTime.when(LocalDateTime::now).thenReturn(fixedTime);

        String orderNo = orderService.generateOrderNo();

        assertThat(orderNo).startsWith("20240115");
    }
}
```

> `mockStatic` MUST be used within `try-with-resources` to ensure restoration. Leaking static mocks across tests causes cascading failures.

### Mock Anti-Patterns (Forbidden)

- ❌ Mock simple utility methods (e.g., `String.format`, `Collections.sort`) → ✅ Call directly, no mock needed
- ❌ Mock private methods of the class under test via reflection → ✅ Cover them indirectly through public methods
- ❌ Mock all dependencies turning tests into "verify call order" → ✅ Only mock uncontrollable external dependencies (DB/RPC/HTTP)
- ❌ Use `@SpringBootTest` for unit tests → ✅ Use `@ExtendWith(MockitoExtension.class)` for lightweight unit tests
- ❌ Mock return value type doesn't match the real signature → ✅ Mock return values must match the method signature exactly
- ❌ Mock `equals`/`hashCode`/`toString` → ✅ These methods should use real implementations

---

## Examples

### Example 1: Parameterized Tests (Recommended Pattern)

Target method:

```java
public int add(int a, int b) {
    return a + b;
}
```

Test code:

```java
@ParameterizedTest(name = "{0}: add({1}, {2}) = {3}")
@MethodSource("addTestCases")
void testAdd_参数化验证(String name, int a, int b, int expected) {
    assertEquals(expected, calculator.add(a, b));
}

static Stream<Arguments> addTestCases() {
    return Stream.of(
        Arguments.of("两个正数相加", 1, 2, 3),
        Arguments.of("正数加负数", 5, -3, 2),
        Arguments.of("两个负数相加", -1, -2, -3),
        Arguments.of("加零", 10, 0, 10),
        Arguments.of("两个零相加", 0, 0, 0),
        Arguments.of("大数相加", Integer.MAX_VALUE - 1, 1, Integer.MAX_VALUE)
    );
}
```

### Example 2: @Nested Class Organization (Multiple Scenarios for One Method)

Target method:

```java
public User getUser(Long id) {
    if (id == null || id <= 0) {
        throw new IllegalArgumentException("用户ID不合法");
    }
    return userDAO.findById(id)
        .orElseThrow(() -> new UserNotFoundException("用户不存在: " + id));
}
```

Test code:

```java
@ExtendWith(MockitoExtension.class)
class UserServiceTest {

    @Mock
    private UserDAO userDAO;

    @InjectMocks
    private UserService userService;

    @Nested
    class GetUser {

        @Test
        void 正常获取用户() {
            User expected = new User(1001L, "张三");
            when(userDAO.findById(1001L)).thenReturn(Optional.of(expected));

            User result = userService.getUser(1001L);

            assertEquals("张三", result.getName());
            verify(userDAO).findById(1001L);
        }

        @Test
        void 用户不存在时抛出异常() {
            when(userDAO.findById(999L)).thenReturn(Optional.empty());

            assertThrows(UserNotFoundException.class,
                () -> userService.getUser(999L));
        }

        @Test
        void ID为null时抛出参数异常() {
            assertThrows(IllegalArgumentException.class,
                () -> userService.getUser(null));
        }

        @Test
        void ID为负数时抛出参数异常() {
            assertThrows(IllegalArgumentException.class,
                () -> userService.getUser(-1L));
        }
    }
}
```

---

## Common Pitfalls and Fixes

| Pitfall                                             | Cause                                                   | Fix                                                                   |
| --------------------------------------------------- | ------------------------------------------------------- | --------------------------------------------------------------------- |
| `Unnecessary stubbings detected`                    | Stub was set up but not actually called in test          | Remove unused stubs, or use `@MockitoSettings(strictness = LENIENT)`  |
| `Cannot mock final class/method`                    | Mockito doesn't support final classes/methods by default | Add `mockito-inline` dependency (Mockito 5+ supports by default)      |
| `@InjectMocks` injection fails                      | Constructor parameters of class under test don't match `@Mock` field types | Manually construct the object under test, passing mock objects in constructor |
| `NullPointerException` on mock object               | Mock method not stubbed with return value, defaults to null | Set return values for all mock methods being called                    |
| `assertEquals` fails for floating-point comparison  | Floating-point precision issues                          | Use the three-parameter version `assertEquals(expected, actual, delta)` |
| `assertEquals` fails for custom object comparison   | Object doesn't override `equals`/`hashCode`              | Use AssertJ's `usingRecursiveComparison()` or assert field by field   |
| Static methods cannot be mocked                     | Mockito requires `mockStatic` within try-with-resources  | Use `try (MockedStatic<T> mocked = mockStatic(T.class)) { ... }`     |
| Spring integration test context loads slowly        | `@SpringBootTest` starts full context                    | For unit tests, use `@ExtendWith(MockitoExtension.class)` instead     |

---

## Context Discovery Commands

```bash
grep -rn "public.*class\|public.*interface" <package_path>
cat pom.xml build.gradle 2>/dev/null
find . -name "*Test.java" | head -20
grep -rn "@Mock\|@InjectMocks\|@MockBean" --include="*Test.java" .
grep -rn "import.*assert\|import.*Mock" --include="*Test.java" . | head -10
```
