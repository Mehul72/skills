# Error Diagnosis and Fix Strategies

Common JavaScript/TypeScript unit test verification failures. Fix only test files or test-side mock/config adaptation; do not modify production code.

## Module Resolution Errors

### `Cannot find module`

Symptoms: test run reports `Cannot find module 'xxx'`.

Common causes:

- Wrong relative import path in the test.
- Source file uses path aliases, for example `@/utils`, but the test framework lacks matching alias config.
- Dependency is platform/environment-specific and does not exist in the test runtime.

Fixes:

- First correct the test import path.
- Check Jest `moduleNameMapper` or Vitest/Rstest `resolve.alias`.
- Mock dependencies that cannot resolve in test runtime and are not the behavior under test.

```ts
jest.mock('@/utils/helper', () => ({}), { virtual: true });
```

## Test Path Problems

### `No tests found`

Symptoms: test command does not discover the new test file.

Common causes:

- Test path does not match `testMatch` / `testRegex` / `include`.
- Test file is excluded by `testPathIgnorePatterns` / `exclude`.
- Test file suffix does not match project convention.

Fixes:

- Read framework config and confirm matching patterns.
- Move or rename the test file to match existing project style.
- Component tests with JSX should use `.tsx`, not `.ts`.

## Babel / Transform Errors

### `SyntaxError` in mock factory

Symptoms: `jest.mock` factory reports `Unexpected token`, `Missing semicolon`, etc.

Cause: Babel may parse hoisted `jest.mock` factories without TypeScript transform.

Fixes:

- Remove type annotations, `as` assertions, and generic calls from the mock factory.
- Use `(x) =>`, not `(x: string) =>`.
- Do not put JSX in mock factories; use `require('react').createElement` if unavoidable.

### `Cannot use import statement outside a module`

Symptoms: source file or dependency ESM imports cannot be parsed by the current test runtime.

Fixes:

- Reuse existing project transform config.
- Mock hard-to-transform modules that are not the behavior under test.
- In Jest ESM projects, follow existing `jest.unstable_mockModule` or dynamic import style.

## DOM / Environment Errors

### `document is not defined` / `window is not defined`

Cause: component or hook depends on DOM, but tests run in node environment.

Fixes:

- Jest: add `/** @jest-environment jsdom */` or use project jsdom config.
- Vitest: add `// @vitest-environment jsdom`.
- Rstest: add `// @rstest-environment jsdom`.

### `Cannot assign to read only property`

Cause: some jsdom `window` properties are read-only.

Fix:

```ts
Object.defineProperty(window, 'xxx', { value: mockValue, writable: true });
// or
jest.spyOn(window, 'xxx', 'get').mockReturnValue(mockValue);
```

## Mock Problems

### `Cannot access 'mockXxx' before initialization`

Cause: `jest.mock()` / `vi.mock()` / `rs.mock()` factory references a `let` / `const` that is not initialized yet.

Fix:

```ts
jest.mock('./mod', () => ({ fn: jest.fn() }));
const { fn: mockFn } = jest.requireMock('./mod');
```

Vitest uses `vi.hoisted`; Rstest should avoid external factory references or use supported non-hoisted mock APIs.

### i18n / router / store `is not a function`

Cause: mock shape does not match real exports, or default/named export is mixed up.

Fixes:

- Match the source import style and provide the correct default/named export.
- i18n can usually return the key.
- Prefer existing router/store test helpers.

## TypeScript Compile Problems

### Test-file type errors

Fixes:

- Reuse exported source types.
- Cast mock functions to the framework mock type or use existing helpers.
- Fix only test-related type errors.

### Source-file type errors

Do not modify production code. Mock hard-to-compile dependencies if necessary, or focus on tests that can be verified under current project config.

## Timeout and Async Leaks

### Test command timeout

Common causes:

- Network, WebSocket, timers, subscriptions, or external services are not mocked.
- Promise never resolves/rejects.
- React/Vue component enters an infinite update loop.

Fixes:

- Mock all external async dependencies.
- Use fake timers and restore real timers after the case.
- Wait for async state to settle before asserting.
- If the same case keeps timing out, delete or rewrite it and keep stable useful coverage.
