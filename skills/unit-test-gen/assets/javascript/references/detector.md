# Engineering Environment Detection

Detect only the information needed for the current target file. Do not scan every possible project setting by default.

---

## Test Framework Detection (Required)

Walk upward from the target file directory and determine whether the project uses Jest / Vitest / Rstest.

Recommended checks:

1. Config files:
   - Jest: `jest.config.{ts,js,mjs,cjs,json}`
   - Vitest: `vitest.config.{ts,js,mts,mjs}`
   - Rstest: `rstest.config.{ts,js,mjs,mts,cjs,cts}`
2. `package.json` devDependencies:
   - `vitest` -> Vitest
   - `@rstest/core` -> Rstest
   - `jest` / `@types/jest` -> Jest
3. Fallback: Jest

In monorepos, framework config files take precedence over root `package.json`, because the root may include multiple frameworks.

## Existing Test File Lookup (Recommended)

Check whether the target file already has a corresponding test file. If yes, supplement incrementally instead of creating a full replacement.

Recommended checks:

- Search the same directory and `__tests__/` for same-basename `.test.{ts,tsx}` or `.spec.{ts,tsx}`.
- Example: `src/utils.ts` -> `src/utils.test.ts`, `src/__tests__/utils.test.ts`.

## Adjacent Test Style (Recommended)

Read nearby tests to match imports, mock style, helpers, and `describe` / `it` structure.

Recommended checks:

- Glob `*.test.*` / `*.spec.*` in the target directory.
- Read imports and mock declarations from 1-2 adjacent test files.

## Test File Placement (On Demand)

When placement is unclear:

- Read `testMatch`, `testPathIgnorePatterns`, `testRegex` (Jest) or `include` / `exclude` (Vitest/Rstest).
- Follow existing project test paths discovered by globbing `**/*.test.*`.
- If the source directory is excluded, place the test under a matching `__tests__/` path.

## Babel Transform Constraints (On Demand)

Check when Jest mock factories produce `SyntaxError`.

Recommended checks:

- Read Jest config `transform`.
- `ts-jest` or `@swc/jest` usually supports TS syntax.
- `babel-jest` or no TS transform means Jest mock factories must avoid TS syntax.

Impact under Babel:

- Replace `import type { X }` with `import { X }` when needed.
- Do not use type annotations or `as` assertions inside `jest.mock` factories.
- For implicit-any conflicts, prefer local `// @ts-expect-error` over adding types inside factories.

## ES Module Constraints (On Demand)

Check when `require is not defined` or module loading errors appear.

Recommended check:

- Inspect `package.json` for `"type": "module"`.

Impact:

- `require()` may be unavailable.
- Follow project ESM patterns such as `jest.unstable_mockModule()` or top-level/dynamic imports.

## tsconfig Path Aliases (On Demand)

Check when source imports use non-relative paths, for example `@/utils`.

Recommended checks:

- Walk upward for `tsconfig.json` / `tsconfig.base.json`.
- Extract `compilerOptions.baseUrl` and `compilerOptions.paths`.
- Verify the test framework has matching alias/module mapper settings.

## Export Symbol Analysis (On Demand)

When deciding testable units:

- Read source exports.
- Pay attention to split default export patterns: component declared first, then `export default Comp`.

## Repository Guidelines (On Demand)

If the project may have custom testing conventions:

- Look for `AGENTS.md` / `CLAUDE.md` in the repo root or package root.
- Extract test, mock, lint, and style instructions only.
