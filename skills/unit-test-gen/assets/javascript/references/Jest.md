# Jest Quick Reference (Deltas and Pitfalls Only)

## Mock Hoisting

`jest.mock` is hoisted to the top of the file. The factory runs before `let` / `const` initialization.

```ts
// Bad: TDZ error
const mockFn = jest.fn();
jest.mock('./mod', () => ({ fn: mockFn }));

// Good: define in factory, then read via requireMock
jest.mock('./mod', () => ({ fn: jest.fn() }));
const { fn: mockFn } = jest.requireMock('./mod');

// Good: lazy getter
let state = {};
jest.mock('./mod', () => ({ get data() { return state; } }));
```

## Partial Mock

```ts
jest.mock('./utils', () => ({
  ...jest.requireActual('./utils'),
  formatDate: jest.fn().mockReturnValue('2024-01-01'),
}));
```

## Default Export Mock

```ts
jest.mock('./module', () => ({
  __esModule: true,
  default: jest.fn(() => 'mocked'),
  namedExport: jest.fn(),
}));
```

## Same-File Function Mock Limitation

If functions inside one module call each other, mocking the exported reference does not affect the internal binding. If `foobar()` calls local `foo()`, mocking exported `foo` will not affect `foobar`.

## Mock Cleanup

| Method | Effect |
|---|---|
| `jest.clearAllMocks()` | Clears call history, keeps implementation |
| `jest.resetAllMocks()` | Clears call history and resets implementation |
| `jest.restoreAllMocks()` | Restores original `spyOn` implementation |

## Common Errors

| Error | Fix |
|---|---|
| `No tests found` | Check `testMatch` / `testRegex` against the test path |
| `Cannot find module` | Check whether `moduleNameMapper` maps tsconfig paths |
| `SyntaxError: Unexpected token` | Check transform config and ESM dependencies |
| `document is not defined` | Use `testEnvironment: 'jsdom'` |
| `ReferenceError: jest is not defined` | In ESM mode, use `import { jest } from '@jest/globals'` |
| `jest.mock` factory references external variable | Define inside factory or use `requireMock`; `mock*` prefix only helps in limited babel-jest cases |
| `Exceeded timeout` | Check missing `await`, timers, network, or open handles |

## Environment Notes

- DOM tests: `testEnvironment: 'jsdom'`; Jest 28+ may require `jest-environment-jsdom`.
- File-level environment: `/** @jest-environment jsdom */`.
- Path aliases: map tsconfig `paths` to `moduleNameMapper`.
