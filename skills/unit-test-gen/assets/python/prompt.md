# Python Language-Specific Prompt

## Function Extraction Methods

| Tool/Method | Description                              |
| ----------- | ---------------------------------------- |
| `grep`      | Quickly locate `def` / `class` declarations |
| `ast` module | Precisely parse function and class structures |
| `inspect`   | Retrieve function signatures and source at runtime |
| `pydoc`     | View module/function documentation       |

## Filtering Rules (Python-Specific)

**Skip:**

- `if __name__ == "__main__"` entry blocks
- Auto-generated code files (Proto-generated files, `*_pb2.py`, `*_pb2_grpc.py`, etc.)
- Files containing `# Code generated` or `@generated` comments
- Simple property getter/setter with fewer than 3 lines
- Functions with coverage exceeding 90%
- Pure type definition files (containing only `TypedDict`, `dataclass` declarations with no business logic)

## Test File Naming Conventions

| Item       | Convention                                                   |
| ---------- | ------------------------------------------------------------ |
| Test file  | `test_*.py` or `*_test.py`                                   |
| Location   | Same directory as source file (follow existing conventions)  |
| Test class | `Test{ClassName}` (e.g., `UserService` → `TestUserService`)  |
| Test function | `test_<func>_<scenario>`                                  |

---

## targets / results Organization Rules

The minimum execution unit in Python is the **source file (module)**. One JSON file per source file, flat in the targets/ and results/ directories.

### File Naming

Use the source file's relative path with `/` replaced by `#` and `.py` suffix removed:

- `src/mypackage/service/user_service.py` → `src#mypackage#service#user_service.json`
- `mypackage/utils/helpers.py` → `mypackage#utils#helpers.json`

### targets JSON Structure

```
${TMP_ROOT}/targets/
  ├── src#mypackage#service#user_service.json
  ├── src#mypackage#service#auth_service.json
  └── src#mypackage#utils#helpers.json
```

Each file contains a single source module and its target functions/methods:

| Field | Type | Required | Description |
|------|------|:----:|------|
| `module` | string | ✅ | Source file relative path (relative to `PROJECT_ROOT`) |
| `functions` | array | ✅ | List of target functions/methods in this file |
| `functions[].function` | string | ✅ | Function or method name |
| `functions[].line` | number | ✅ | Function starting line number |
| `functions[].class` | string | ❌ | Class name (for methods; omit for top-level functions) |

#### targets Example

`${TMP_ROOT}/targets/src#mypackage#service#user_service.json`:

```json
{
  "module": "src/mypackage/service/user_service.py",
  "functions": [
    {"function": "get_user_by_id", "line": 15},
    {"function": "create_user", "line": 45},
    {"function": "get_profile", "line": 80, "class": "UserService"},
    {"function": "update_profile", "line": 110, "class": "UserService"},
    {"function": "delete_user", "line": 145, "class": "UserService"}
  ]
}
```

### results JSON Structure

Mirrors targets with the same file names. Adds status, defects, and other result fields at the function level (field definitions in `references/output-contract/FORMATS.md`).

#### results Example (After Writer writes)

```json
{
  "module": "src/mypackage/service/user_service.py",
  "functions": [
    {
      "function": "get_user_by_id",
      "line": 15,
      "status": "passed",
      "test_file": "tests/test_user_service.py",
      "test_function": "test_get_user_by_id_正常获取用户"
    },
    {
      "function": "get_profile",
      "line": 80,
      "class": "UserService",
      "status": "generated",
      "test_file": "tests/test_user_service.py",
      "test_function": "TestUserService::test_get_profile_正常获取",
      "defects": [
        {
          "severity": "p1",
          "description": "get_profile 未处理 user_id 为 None 的情况，直接访问属性导致 AttributeError",
          "location": "line 85-87",
          "scenario": "传入 None user_id 时应抛出 ValueError"
        }
      ]
    },
    {
      "function": "delete_user",
      "line": 145,
      "class": "UserService",
      "status": "passed",
      "test_file": "tests/test_user_service.py",
      "test_function": "TestUserService::test_delete_user_正常删除"
    }
  ]
}
```

---

## Execution Scheduling

Python uses the source file as the basic unit for task dispatch. The scheduling strategy:

1. **Sequential by file**: `ls ${TMP_ROOT}/targets/` to get the full file list, process each source file in order
2. **Writer generates per file**: Writer reads the `functions` array, generates one test file (or appends to an existing test file), and writes results to `${TMP_ROOT}/results/<module_name>.json`
3. **Fixer verifies per file**: After Writer completes, dispatch Fixer to run syntax check and tests for the specific test file, triage failures, and fix, updating the status in results file

```
ls targets/ → [src#mypackage#service#user_service.json, src#mypackage#service#auth_service.json, ...]

for each source file (sequential):
    ├── Read targets/<module_name>.json
    ├── Dispatch Writer → generate/update test file → write to results/<module_name>.json
    └── Dispatch Fixer (syntax check → run tests → triage → fix → update results)
```

### Verify-and-Fix Rounds

Fixer's verify-and-fix loop for each test file is limited to a maximum of **3 rounds**.

---

## Pre-Check (Must be completed before writing tests)

> **⚠️ Hard prerequisite**: Before generating any test code, this step's project learning **must** be completed. Different projects vary greatly in testing frameworks, fixture patterns, and mock strategies. Skipping this step almost certainly leads to repeated fixes later.

### 1. Environment Detection

1. **Detect project configuration**: Check for `pyproject.toml`, `setup.py`, `setup.cfg` to understand project structure
2. **Detect test framework**: Confirm pytest (default) vs unittest. Check for `pytest.ini`, `pyproject.toml [tool.pytest]`, or `conftest.py`
3. **Detect package manager**: pip, poetry (`pyproject.toml [tool.poetry]`), or pipenv (`Pipfile`)
4. **Check test directory layout**: Tests in `tests/` directory, alongside source files, or `src/` layout?
5. **Detect Python version** (recommended): Check `pyproject.toml` or `.python-version`, affects available syntax features (walrus operator, match-case, type hints, etc.)

### 2. Learn Project Testing Patterns

Learn the style of existing tests in the target file's test directory:

1. **Scan existing test files** (required): Read 1-2 existing `test_*.py` or `*_test.py` files to learn:
   - **Test framework**: pytest (function-based) vs unittest (class-based)?
   - **Mock strategy**: `unittest.mock.patch` decorator, `pytest-mock` (mocker fixture), or manual dependency injection?
   - **Assertion style**: bare `assert` (pytest) vs `self.assertEqual` (unittest)?
   - **Fixture patterns**: `@pytest.fixture`, `conftest.py` shared fixtures, or setup/teardown methods?
   - **Naming conventions**: Actual naming patterns for test functions/classes
   - **Test organization**: Flat functions, `@pytest.mark.parametrize`, or `Test*` classes grouping?
2. **Discover conftest.py and shared fixtures** (recommended):
   ```bash
   find . -name "conftest.py" | head -10
   grep -rn "@pytest.fixture\|def setup\|def teardown" --include="test_*.py" --include="conftest.py" . | head -10
   ```
   - If shared fixtures exist in `conftest.py`, prefer reusing them
3. **Read project conventions** (recommended): Check `AGENTS.md`, `CLAUDE.md` under `PROJECT_ROOT`
   - Extract unit-test-related requirements

### 3. Context Analysis

For each target function, gather sufficient context information:

1. **Layer 1 (required)**: Read the target function source code, understand function signature, type hints, default parameters, and class dependencies (if it's a method)
2. **Layer 2 (recommended)**: Read imported modules to understand external dependency signatures (for deciding mock strategy)
3. **Layer 3 (as needed)**: When Layer 2 information is insufficient, read indirect dependencies, dataclass/TypedDict definitions, or configuration modules

---

## Python Unit Test Standards

### Test Function/Method Signature

- Test functions must start with `test_` for pytest to auto-discover them
- Test classes must start with `Test` and cannot have an `__init__` method
- Test function parameters can declare fixture names for pytest auto-injection
- Prefer functional test style; only use test classes when multiple tests share setup logic

### Test Isolation Principles

- Each test function must be independent, not depending on execution order or side effects of other tests
- Passing state between test functions via module-level variables is forbidden
- When shared setup logic is needed, use fixtures (`@pytest.fixture`) rather than module-level variables
- Mock / patch must be set up and cleaned within the test function scope; leaking to other test cases is not allowed
- Use `with` statements or decorator-style `patch` to ensure automatic restoration

### Assertion Standards

- Prefer pytest native `assert` statements (pytest automatically provides detailed failure messages)
- For floating-point comparison, use `pytest.approx(expected, abs=delta)` or `assert abs(actual - expected) < delta`
- For set containment, use `assert item in collection` or `assert set_a <= set_b`
- For exception assertions, use `with pytest.raises(ExceptionType) as exc_info:` + verify message
- Prefer precise value comparison (`assert result == expected`), but when verifying a complex object is non-None before asserting its attributes, `assert result is not None` is a reasonable prerequisite assertion
- Using `assertTrue` / `assertEqual` and other `unittest`-style assertions is forbidden (unless the project has existing conventions)

### Exception Testing Requirements

- Functions that may raise exceptions must cover exception paths
- Use `pytest.raises` to assert exception type and verify exception message:
  ```python
  with pytest.raises(ValueError, match="不能为空"):
      service.process(None)
  ```
- When precise exception message matching is needed, use `exc_info.value` to access the exception object:
  ```python
  with pytest.raises(ValueError) as exc_info:
      service.process(None)
  assert "不能为空" in str(exc_info.value)
  ```

### None/Empty Value Handling

- Optional parameters need to cover `None` input scenarios
- `str` parameters need to cover both empty string `""` and `None` scenarios
- `list`/`dict`/`set` parameters need to cover both `None` and empty collection `[]`/`{}`/`set()` scenarios
- `Optional[T]` return values need to cover `None` scenarios
- Numeric parameters need to cover `0`, negative numbers, boundary values (e.g., `sys.maxsize`, `float('inf')`) scenarios

### Type Safety

- For functions using type hints, tests should cover type mismatch edge cases (if the function doesn't perform type checking)
- For functions returning `TypedDict` / `dataclass`, assert field by field rather than comparing the whole object (unless `__eq__` is implemented)

---

## Verification Methods

### Syntax Check

```bash
python -m py_compile <test_file>
```

### Run Tests

```bash
python -m pytest <test_file> -v
```

### Coverage Check

```bash
python -m pytest <test_file> -v --cov=<source_module> --cov-report=term-missing
```

---

## Special Fix Rules

**Failure Triage:**

> For complete defect determination rules, see the "Failure Triage Process" section in `references/test-fixer/AGENT.md`. Only Python-specific supplements are listed here.

**Python-Specific Defect Signals (must be judged in context; cannot be directly determined as defects):**
- `TypeError: 'NoneType' object is not subscriptable/iterable/callable` → May be missing None guard, **but only counts as a defect when None arises from the function's internal logic**; triggered by tests intentionally passing None parameters doesn't count
- `AttributeError: 'NoneType' object has no attribute 'xxx'` → May be a missing None check, **same as above, need to exclude cases where tests intentionally pass None**
- `IndexError: list index out of range` → May be missing boundary check, **but only counts as a defect when empty list comes from a normal business scenario**
- `KeyError` → May be missing dict key existence check, **need to confirm whether the key comes from normal business input**
- `ZeroDivisionError` → May be missing division-by-zero guard, **most likely a real defect**
- `RecursionError: maximum recursion depth exceeded` → May be a recursion termination condition defect, **most likely a real defect**
- Assertion failure where expected value matches the correct semantics of the function → Logic defect, **most likely a real defect**

- If `import` reports `ModuleNotFoundError`, check whether dependencies are missing or `sys.path` is configured incorrectly
- If `patch` target path is wrong causing mock not to take effect, ensure the patch target is the **consumer's** import path, not the definer's
- If fixture reports `fixture 'xxx' not found`, check whether the fixture is defined in the correct `conftest.py`
- If `AttributeError: __enter__` or `__exit__` occurs, check whether `patch` was incorrectly used in non-context-manager form
- If async function tests report `RuntimeWarning: coroutine was never awaited`, install `pytest-asyncio` and use the `@pytest.mark.asyncio` decorator

---

## Formatting

```bash
black <file>
```

Or `autopep8 -i <file>` (follow project configuration).

If the project uses `ruff`:

```bash
ruff format <file>
```

---

## Code Style

Style is determined by priority: user instructions > AGENTS.md > existing tests in the same directory > defaults below.

| Item            | Convention                                                     |
| --------------- | -------------------------------------------------------------- |
| Scenario/comment language | Match the surrounding code and existing tests |
| Naming          | `test_<func>_<scenario>` or `Test<Class>`                     |
| File            | `test_<module>.py`, same directory as source file (follow existing conventions) |
| Assertion       | `pytest` + built-in `assert` (or follow existing tests)        |
| Mock            | `unittest.mock.patch` / `pytest-mock` (or follow existing tests) |
| Test case organization | Parameterize with `@pytest.mark.parametrize`            |
| import order    | stdlib → third-party → project internal modules, separated by blank lines |

---

## Mock Usage

### Basic Structure (unittest.mock)

Use `patch` decorator or context manager to mock external dependencies:

```python
from unittest.mock import patch, MagicMock

def test_get_user_info_正常获取():
    # 1. setup mock
    # 2. call target function
    # 3. assert results
    pass
```

### patch Decorator Form

```python
@patch("module_under_test.query_user_from_db")
def test_get_user_info_正常获取(mock_query):
    mock_query.return_value = User(id=1001, name="张三")

    result = get_user_info(1001)

    assert result.name == "张三"
    assert result.id == 1001
    mock_query.assert_called_once_with(1001)
```

### patch Context Manager Form

```python
def test_get_user_info_数据库查询失败():
    with patch("module_under_test.query_user_from_db") as mock_query:
        mock_query.side_effect = ConnectionError("connection refused")

        with pytest.raises(ServiceError, match="查询失败"):
            get_user_info(1001)

        mock_query.assert_called_once_with(1001)
```

### pytest-mock Form (mocker fixture)

```python
def test_get_user_info_正常获取(mocker):
    mock_query = mocker.patch("module_under_test.query_user_from_db")
    mock_query.return_value = User(id=1001, name="张三")

    result = get_user_info(1001)

    assert result.name == "张三"
    mock_query.assert_called_once_with(1001)
```

### Mock Class Methods

```python
def test_user_service_get_profile_正常获取(mocker):
    mock_dao = mocker.patch.object(UserDAO, "find_by_id")
    mock_dao.return_value = UserProfile(name="李四", email="lisi@example.com")

    svc = UserService()
    profile = svc.get_profile(1001)

    assert profile.name == "李四"
    assert profile.email == "lisi@example.com"
    mock_dao.assert_called_once_with(1001)
```

### Mock Anti-Patterns (Forbidden)

- ❌ Mock simple utility functions (e.g., `str.split`, `len`, `sorted`) → ✅ Call directly, no mock needed
- ❌ Mock private methods (`_internal_method`) via `patch.object` → ✅ Cover them indirectly through public methods
- ❌ Patch too broadly (e.g., entire module) making tests meaningless → ✅ Only mock uncontrollable external dependencies (DB/HTTP/filesystem)
- ❌ Use `MagicMock` without `spec` allowing any attribute access without error → ✅ Always use `spec=True` or `autospec=True`
- ❌ Mock the function under test itself → ✅ Mock its **dependencies**, not the target
- ❌ Forget to assert mock was called (mock hides real failures silently) → ✅ Always verify `assert_called_once_with` or check return values

---

## Examples

### Example 1: Parameterized Tests (Recommended Pattern)

Target function:

```python
def add(a: int, b: int) -> int:
    return a + b
```

Test code:

```python
import sys
import pytest

@pytest.mark.parametrize(
    "a, b, expected",
    [
        pytest.param(1, 2, 3, id="两个正数相加"),
        pytest.param(5, -3, 2, id="正数加负数"),
        pytest.param(-1, -2, -3, id="两个负数相加"),
        pytest.param(10, 0, 10, id="加零"),
        pytest.param(0, 0, 0, id="两个零相加"),
        pytest.param(sys.maxsize, 1, sys.maxsize + 1, id="大数相加"),
    ],
)
def test_add(a, b, expected):
    assert add(a, b) == expected
```

### Example 2: Test Class Organization (Multiple Scenarios for One Method)

Target method:

```python
class UserService:
    def __init__(self, user_dao: UserDAO):
        self._user_dao = user_dao

    def get_user(self, user_id: int) -> User:
        if user_id is None or user_id <= 0:
            raise ValueError("用户ID不合法")
        user = self._user_dao.find_by_id(user_id)
        if user is None:
            raise UserNotFoundError(f"用户不存在: {user_id}")
        return user
```

Test code:

```python
from unittest.mock import MagicMock
import pytest


class TestUserService:

    @pytest.fixture
    def user_dao(self):
        return MagicMock(spec=UserDAO)

    @pytest.fixture
    def svc(self, user_dao):
        return UserService(user_dao)

    def test_get_user_正常获取用户(self, svc, user_dao):
        expected = User(id=1001, name="张三")
        user_dao.find_by_id.return_value = expected

        result = svc.get_user(1001)

        assert result.name == "张三"
        user_dao.find_by_id.assert_called_once_with(1001)

    def test_get_user_用户不存在时抛出异常(self, svc, user_dao):
        user_dao.find_by_id.return_value = None

        with pytest.raises(UserNotFoundError, match="用户不存在"):
            svc.get_user(999)

    def test_get_user_ID为None时抛出参数异常(self, svc):
        with pytest.raises(ValueError, match="用户ID不合法"):
            svc.get_user(None)

    def test_get_user_ID为负数时抛出参数异常(self, svc):
        with pytest.raises(ValueError, match="用户ID不合法"):
            svc.get_user(-1)
```

---

## Common Pitfalls and Fixes

| Pitfall                                               | Cause                                                     | Fix                                                                 |
| ----------------------------------------------------- | --------------------------------------------------------- | ------------------------------------------------------------------- |
| `patch` not taking effect, target function still calls real implementation | Patch path is not the consumer's import path               | Patch target must be the **reference in the consumer module**, e.g., `module_a.func` not `module_b.func` |
| `fixture 'xxx' not found`                             | Fixture not defined in correct `conftest.py` or not imported | Place fixture in `conftest.py` at the same or parent directory level of the test file |
| `assert` statements optimized away by Python          | Runtime used `-O` optimization flag                        | Don't use `-O` when running tests; pytest doesn't optimize by default |
| `MagicMock` returns new Mock for any attribute access without error | MagicMock's default behavior is chain-generating child Mocks | Use `spec=True` or `autospec=True` to restrict attribute access     |
| Counter-intuitive parameter order when stacking `patch` decorators | Multiple `@patch` execute bottom-to-top, parameters inject left-to-right | Note decorator order: the innermost `@patch` corresponds to the first parameter |
| Async tests not executing                             | Missing `pytest-asyncio` or `@pytest.mark.asyncio` not added | Install `pytest-asyncio` and add the decorator                      |
| Object parameters in `parametrize` cause unreadable test IDs | Default shows object's `repr`                              | Use `pytest.param(..., id="description")` to specify readable IDs   |
| Tests affecting each other                            | Module-level variables or singletons modified without restoration | Use `yield` + cleanup logic in fixtures, or use `monkeypatch`       |

---

## Context Discovery Commands

```bash
grep -rn "def \|class " <file>
pip list | grep -i test
cat setup.py setup.cfg pyproject.toml 2>/dev/null
find . -name "test_*.py" -o -name "*_test.py" | head -20
grep -rn "import.*mock\|from.*mock\|@patch\|@pytest" --include="test_*.py" . | head -10
grep -rn "conftest\|fixture" --include="conftest.py" .
```
