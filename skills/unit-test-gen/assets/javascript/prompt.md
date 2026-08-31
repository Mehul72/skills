# JavaScript & TypeScript Language-Specific Prompt

This file supplies the JS/TS details required by `SKILL.md`: execution unit, targets/results shape, extraction, filters, test organization, mock/framework rules, verification commands, and scheduling.

## Target Selection

### Minimum Execution Unit

The minimum execution unit is the **source file**. One source file maps to one `targets/<unit>.json` and one mirrored `results/<unit>.json`.

File naming: replace `/` in the source relative path with `#`, keep the original extension, append `.json`.

Examples:

- `src/utils/date.ts` -> `src#utils#date.ts.json`
- `packages/app/src/Button.tsx` -> `packages#app#src#Button.tsx.json`

### Function Extraction

Extract regular functions, exported arrow/function expressions, class methods, React/Vue components, and custom hooks. Record at least `function` and `line`; add optional `kind`, `class`, `export_type`, `signature` when useful.

Use `rg` for quick discovery and TypeScript Compiler API / Babel parser / IDE LSP when accurate symbols, signatures, or JSX/TSX parsing are needed.

### JS/TS Filters

Apply common `references/target-filter/AGENT.md` rules plus:

- Skip: `dist/`, `build/`, `coverage/`, `.next/`, `.nuxt/`, `.output/`, `.svelte-kit/`, `node_modules/`
- Skip: `*.d.ts`, `*.config.*`, `vite.config.*`, `jest.config.*`, `vitest.config.*`, `rspack.config.*`, `webpack.config.*`
- Skip: `*.stories.*`, `*.story.*`, `*.demo.*`, `__fixtures__/`, `fixtures/`
- Skip barrel files that only re-export symbols
- Skip type-only declarations, simple getter/setters, constant wrappers, pure style/config objects, and private inline callbacks without standalone logic

## targets / results JSON

`targets` uses:

```json
{
  "file": "src/services/user.ts",
  "functions": [
    {
      "function": "getUserProfile",
      "line": 18,
      "kind": "function",
      "export_type": "named",
      "signature": "export async function getUserProfile(userId: string)"
    }
  ]
}
```

Required fields: `file`, `functions[]`, `functions[].function`, `functions[].line`.

`results` mirrors the same structure and adds function-level result fields from `references/output-contract/FORMATS.md`, such as `status`, `test_file`, `test_function`, `defects`, `error_log`.

## Scheduling

Process source-file units serially:

1. Orchestrator writes one targets JSON per source file.
2. Writer processes all `functions[]` in that file together, sharing framework detection, imports, mocks, and test setup.
3. Fixer verifies and repairs the corresponding test file, then updates the same results JSON.
4. Move to the next source file only after the current file is done.

Fixer may run at most **10** verify/fix rounds per test file.

## Test Organization

| Item | Convention |
|---|---|
| Test file | Follow existing style; otherwise use `*.test.ts(x)` / `*.test.js(x)` or project `*.spec.*` convention |
| Location | Prefer existing test location; otherwise source directory or a path matching `testMatch` / `include` |
| Test structure | `describe('<symbol>', ...)` + `it/test('<scenario>', ...)` |
| Components | React: Testing Library style; Vue: `@vue/test-utils` style |

Only create/modify test files. Incrementally supplement usable existing tests; rewrite only when existing tests are broken or obsolete.

## Preflight Knowledge

Before writing tests, read `assets/javascript/references/detector.md`, then load only the relevant reference docs:

- Framework: `Jest.md` / `Vitest.md` / `Rstest.md`
- Mock needed: `mock-guidelines.md`
- React component/hook: `React.md` and usually `testing-library.md`
- Vue component/composable: `Vue.md`
- Monorepo/package manager/config uncertainty: `engineering.md`
- Verification errors: `troubleshooting.md`

Context analysis is manual for JS/TS. Read the source file, direct imports, existing tests, and adjacent tests as needed.

## Mock / Framework Rules

Detected framework decides API:

- Jest: `jest.fn/mock/spyOn`, partial mock with `jest.requireActual`
- Vitest: `vi.fn/mock/spyOn`, partial mock with `importOriginal` / `vi.importActual`
- Rstest: `rs.fn/mock/spyOn`, follow Rstest-specific import-actual syntax
- Assertions: use the detected framework's `expect` and project-installed matchers; do not introduce new assertion libraries.

Mock hoisting rule: `jest.mock` / `vi.mock` / `rs.mock` factories run before `let`/`const` initialization. Never reference top-level test variables from a mock factory.

Safe patterns:

- Jest: define mocks inside factory, then read them with `jest.requireMock()`
- Vitest: use `vi.hoisted`
- All frameworks: lazy getter state, or non-hoisted `doMock` when supported
- Avoid TS annotations, `as` assertions, and JSX inside Jest mock factories when Babel parses them

## Verification Commands

Prefer project scripts and adjacent-test commands over global binaries.

Command selection:

1. Reuse commands from nearby tests, README, `AGENTS.md`, `CLAUDE.md`, or `package.json#scripts`.
2. In monorepo, run from the nearest package root with `package.json`.
3. Package-manager defaults:
   - npm: `npm test -- <test-file>`
   - pnpm: `pnpm test -- <test-file>` or `pnpm --filter <pkg> test -- <test-file>`
   - yarn: `yarn test <test-file>` or `yarn workspace <pkg> test <test-file>`
   - bun: `bun test <test-file>`
4. If scripts are too broad, run the detected framework through the package manager: Jest `<test-file>`, Vitest `run <test-file>`, or Rstest `<test-file>`.

Checks:

- Run tests first. Only then check TS/lint.
- Prefer IDE diagnostics for changed test files; otherwise use project `typecheck` / `tsc`.
- Use existing lint/format scripts; auto-fix when safe.
- Collect coverage only when requested or already part of the workflow.

## Generation and Exit Rules

- Cover happy path, boundary values, and exception/error paths.
- Reuse project style and helpers.
- Do not weaken assertions to pass.
- If one approach fails repeatedly, rethink mock/test structure or rewrite the test file.
- If a case cannot be made stable, remove that case and keep passing useful coverage.
- Exit only when tests pass, TS has no test-file errors, and lint has no relevant errors.

## Reference Index

| Document | Purpose |
|---|---|
| `detector.md` | framework, existing tests, placement, Babel/ESM, paths |
| `Jest.md` / `Vitest.md` / `Rstest.md` | framework-specific deltas |
| `mock-guidelines.md` | hoisting, partial mock, ESM/Babel, timers/globals |
| `React.md` / `Vue.md` / `testing-library.md` | component-specific patterns |
| `engineering.md` | package manager, monorepo, config |
| `troubleshooting.md` | common verification failures |
