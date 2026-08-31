# Rstest Quick Reference (Deltas and Pitfalls Only)

## Key Differences from Jest/Vitest

| Item | Jest | Vitest | Rstest |
|---|---|---|---|
| Imports | Usually global | `from 'vitest'` | `from '@rstest/core'` |
| Mock object | `jest` | `vi` | `rs` or `rstest` |
| Partial mock | `jest.requireActual` | `importOriginal` | `import ... with { rstest: 'importActual' }` |
| Timeout | `jest.setTimeout(ms)` | `vi.setConfig(...)` | `rstest.setConfig({ testTimeout: ms })` |
| Env comment | `/** @jest-environment jsdom */` | `// @vitest-environment jsdom` | `// @rstest-environment jsdom` |
| Done callback | Supported | Supported | Not supported; use async/await |

## Module Mock Behavior

### Auto Mock Requires Explicit Option

Unlike Jest/Vitest, `rs.mock('./module')` does not auto-mock exports; it only looks for `__mocks__`. Pass an option:

```ts
// Auto mock: replace function exports with rs.fn()
rs.mock('./math', { mock: true });

// Spy the whole module: keep implementation but track calls
rs.mock('./calculator', { spy: true });
```

### Partial Mock: Import Attributes

```ts
import * as actualDateUtils from './date-utils' with { rstest: 'importActual' };
import { formatDate } from './date-utils';

rs.mock('./date-utils', () => ({
  ...actualDateUtils,
  formatDate: rs.fn().mockReturnValue('2026-03-19'),
}));
```

### `rs.doMock`

Non-hoisted:

```ts
rs.doMock('./feature', () => ({ readFeatureFlag: () => 'mocked' }));
const { readFeatureFlag } = await import('./feature');
```

### CommonJS Modules

Use `rs.mockRequire()` / `rs.doMockRequire()`, not `rs.mock`.

## Deep Mock Object

```ts
const service = rs.mockObject({
  user: { fetch: async (id: string) => ({ id, name: 'real' }) },
  version: 'v1',
});
service.user.fetch.mockResolvedValue({ id: '1', name: 'mocked' });
```

## Mock Cleanup

```ts
afterEach(() => {
  rs.restoreAllMocks();
  rs.clearAllMocks();
});
```

Or configure `restoreMocks: true, clearMocks: true`.

## Common Errors

| Error | Fix |
|---|---|
| `No tests found` | Check `include` pattern and file suffix |
| `rs is not defined` | Import `rs` from `@rstest/core` or enable `globals: true` |
| `document is not defined` | Use `testEnvironment: 'jsdom'` or `// @rstest-environment jsdom` |
| `rs.mock` has no effect | Passing only a path only checks `__mocks__`; add `{ mock: true }` for auto mock |

## Environment Notes

- DOM tests: `testEnvironment: 'jsdom'` or `'happy-dom'`.
- File-level environment: `// @rstest-environment jsdom`.
- If `globals: true`, add `"types": ["@rstest/core/globals"]` to tsconfig.
- Reuse build config via `@rstest/adapter-rsbuild`, `@rstest/adapter-rslib`, or `@rstest/adapter-rspack`.
