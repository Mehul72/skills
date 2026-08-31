# Mock Guidelines

## Mock Hoisting

`jest.mock()` / `vi.mock()` / `rs.mock()` calls are hoisted and execute before imports and before `let` / `const` initialization.

This means:

- Do not reference top-level `let` / `const` variables inside mock factories.
- Do not reference imported modules inside mock factories.

### Safe Patterns

**Pattern 1: define inside factory + get reference later**

```ts
jest.mock('./service', () => ({
  fetchData: jest.fn(),
}));

const { fetchData: mockFetchData } = jest.requireMock('./service');

beforeEach(() => {
  mockFetchData.mockReturnValue({ data: 'test' });
});
```

**Pattern 2: lazy getter**

```ts
let mockState: Record<string, any> = {};
jest.mock('./store', () => ({
  get state() { return mockState; },
}));

beforeEach(() => {
  mockState = { user: { name: 'test' } };
});
```

**Pattern 3: require inside factory**

```ts
jest.mock('./utils', () => {
  const actual = require('./utils');
  return {
    ...actual,
    formatDate: jest.fn(),
  };
});
```

### Dangerous Patterns

```ts
// Bad: TDZ error. Even mock-prefixed names are unsafe outside limited babel-jest behavior.
const mockFn = jest.fn();
jest.mock('./mod', () => ({ fn: mockFn }));

// Bad: imported binding is not available when the factory runs.
import { helper } from './helper';
jest.mock('./mod', () => ({ fn: helper }));

// Bad: import statement inside factory.
jest.mock('./mod', () => {
  import { x } from './other';
  return { x };
});
```

## Babel Constraints

When Babel transforms Jest tests, the `jest.mock` factory may be parsed separately without TypeScript transform.

Avoid inside factories:

1. `import type`
2. Type annotations: use `(x) => x`, not `(x: string) => x`
3. `as` assertions
4. Generic calls such as `create<MyType>()`
5. JSX; use `require('react').createElement` only if needed

If tsc implicit-any errors conflict with Babel syntax limitations, use a local `// @ts-expect-error` instead of adding TS syntax inside the factory.

## ESM Constraints

For Jest in ESM projects (`"type": "module"`):

- `require()` may be unavailable.
- Follow project patterns such as `jest.unstable_mockModule()` or dynamic import.
- `jest.mock()` factories still cannot use import statements.

## Partial Mock

Jest:

```ts
jest.mock('./module', () => ({
  ...jest.requireActual('./module'),
  targetFn: jest.fn(),
}));
```

Vitest:

```ts
vi.mock('./module', async (importOriginal) => {
  const actual = await importOriginal();
  return { ...actual, targetFn: vi.fn() };
});
```

Rstest:

```ts
import * as actualModule from './module' with { rstest: 'importActual' };

rs.mock('./module', () => ({
  ...actualModule,
  targetFn: rs.fn(),
}));
```

## Virtual Mock

For unresolved aliases or environment-only modules that are not the behavior under test:

```ts
jest.mock('@/utils/someModule', () => ({
  someExport: jest.fn(),
}), { virtual: true });
```

## Timer Mock

Jest:

```ts
jest.useFakeTimers();
jest.runAllTimers();
jest.advanceTimersByTime(1000);
jest.useRealTimers();
```

Vitest:

```ts
vi.useFakeTimers();
vi.runAllTimers();
vi.advanceTimersByTime(1000);
vi.useRealTimers();
```

## Global Object Mock

Read-only properties:

```ts
Object.defineProperty(window, 'performance', {
  value: mockPerf,
  writable: true,
});

jest.spyOn(window, 'matchMedia').mockImplementation(query => ({
  matches: false,
  media: query,
}));
```

## Cleanup

Restore globals and clear mocks in `afterEach`. Also restore real timers when fake timers were used.
