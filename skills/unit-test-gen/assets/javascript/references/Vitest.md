# Vitest Quick Reference (Deltas and Pitfalls Only)

## Key Differences from Jest

| Item | Jest | Vitest |
|---|---|---|
| Imports | Usually global | `import { describe, it, expect, vi } from 'vitest'` |
| Mock object | `jest` | `vi` |
| Partial mock | `jest.requireActual` | `importOriginal` or `vi.importActual` |
| Timeout | `jest.setTimeout(ms)` | `vi.setConfig({ testTimeout: ms })` |
| Env comment | `/** @jest-environment jsdom */` | `// @vitest-environment jsdom` |

## Mock Hoisting and `vi.hoisted`

`vi.mock` is hoisted. The factory must not reference external variables. Use `vi.hoisted`:

```ts
const mocks = vi.hoisted(() => ({
  fetchUser: vi.fn(),
}));

vi.mock('./api', () => ({
  fetchUser: mocks.fetchUser,
}));
```

## Partial Mock

```ts
vi.mock(import('./utils'), async (importOriginal) => {
  const original = await importOriginal();
  return { ...original, formatDate: vi.fn().mockReturnValue('2024-01-01') };
});
```

## Default Export Mock

```ts
vi.mock('./module', () => ({
  default: { myKey: vi.fn() },
  namedExport: vi.fn(),
}));
```

## `vi.doMock`

Non-hoisted. It may reference external variables, but only affects later dynamic imports:

```ts
vi.doMock('./increment', () => ({ increment: () => 100 }));
const { increment } = await import('./increment');
```

## Same-File Function Mock Limitation

Same as Jest: mocking an exported reference does not change internal module bindings.

## Mock Cleanup

| Method | Effect |
|---|---|
| `vi.clearAllMocks()` | Clears call history, keeps implementation |
| `vi.resetAllMocks()` | Clears call history and resets implementation |
| `vi.restoreAllMocks()` | Restores original `spyOn` implementation; does not unmock modules |

## Common Errors

| Error | Fix |
|---|---|
| `vi is not defined` | Import `vi` from `vitest` or enable `globals: true` |
| `vi.mock` factory references external variable | Use `vi.hoisted` or `vi.doMock` |
| `Cannot find module` | Use `vite-tsconfig-paths` or absolute `resolve.alias` |
| `document is not defined` | Add `// @vitest-environment jsdom` |
| `Failed to Terminate Worker` | `fetch` may conflict with `pool: 'threads'`; try `pool: 'forks'` |

## Environment Notes

- DOM tests: `environment: 'jsdom'` or `'happy-dom'`.
- File-level environment: `// @vitest-environment jsdom`.
- Path aliases: absolute `resolve.alias` or `vite-tsconfig-paths`.
- If `globals: true`, add `"types": ["vitest/globals"]` to tsconfig when needed.
