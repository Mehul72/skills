# Engineering Environment Quick Reference

Read this only when package manager, monorepo layout, test config, or TypeScript config is unclear.

## Identification Order

1. Lockfiles: `pnpm-lock.yaml`, `yarn.lock`, `package-lock.json`, `bun.lockb`
2. Workspace files: `pnpm-workspace.yaml`, `rush.json`, `turbo.json`, `eden.monorepo.json`, `package.json#workspaces`
3. Test config: `jest.config.*`, `vitest.config.*`, `rstest.config.*`, `package.json#scripts`
4. TypeScript config: `tsconfig.json`, `compilerOptions.paths`, `types`

## Package Manager Commands

| Environment | Install | Test script | Single test file |
|---|---|---|---|
| npm | `npm install` | `npm test -- ...` | `npm test -- <test-file>` |
| pnpm | `pnpm install` | `pnpm test -- ...` | `pnpm test -- <test-file>` |
| yarn classic | `yarn install` | `yarn test ...` | `yarn test <test-file>` |
| yarn berry | `yarn install --immutable` | `yarn test ...` | `yarn test <test-file>` |
| bun | `bun install` | `bun test` | `bun test <test-file>` |

Prefer existing project scripts. Do not assume direct `jest` / `vitest` / `rstest` binaries are available.

## Monorepo Package Selection

| Type | Marker | Common command |
|---|---|---|
| pnpm workspace | `pnpm-workspace.yaml` | `pnpm --filter <pkg> test -- <file>` |
| Yarn workspace | `package.json#workspaces` | `yarn workspace <pkg> test <file>` |
| Rush | `rush.json` | Run `rushx test -- <file>` inside the package |
| Turborepo | `turbo.json` | Prefer package script; fallback `turbo run test --filter=<pkg>` |
| Eden/EMO | `eden.monorepo.json` | `emo test --filter <pkg>` or package-local `emox test` |

Find the package by walking upward from the target source file to the nearest `package.json`.

## Test Config Notes

### Jest

- File matching: `testMatch`, `testRegex`, `testPathIgnorePatterns`
- TS transform: `ts-jest`, `babel-jest`, `@swc/jest`
- DOM environment: `testEnvironment: 'jsdom'` or `/** @jest-environment jsdom */`
- Path aliases: `moduleNameMapper` should match `tsconfig.paths`

### Vitest

- File matching: `test.include`, `test.exclude`
- DOM environment: `environment: 'jsdom'` or `// @vitest-environment jsdom`
- Path aliases: `resolve.alias` must be absolute, or use `vite-tsconfig-paths`
- Global APIs: if `globals: true` is not configured, import from `vitest`

### Rstest

- File matching: `include`, `exclude`
- DOM environment: `testEnvironment: 'jsdom'` or `// @rstest-environment jsdom`
- Global APIs: if globals are disabled, import from `@rstest/core`
- Build config is often reused via `@rstest/adapter-rsbuild` / `@rstest/adapter-rspack`

## TypeScript Config

- Path aliases come from `compilerOptions.paths`; test framework aliases must match.
- JSX tests need `.tsx`; do not put JSX in `.ts` tests.
- In strict mode, reuse exported source types first.
- Source-file type errors are not fixed by changing production code; only fix test-file-related errors.

## Troubleshooting Priority

1. `No tests found`: check test file path against framework config.
2. `Cannot find module`: check alias / moduleNameMapper / resolve.alias.
3. `document is not defined`: use jsdom/happy-dom.
4. `SyntaxError`: check Babel/SWC/TS transform; mock hard-to-transform dependencies if needed.
5. timeout: mock network, timers, WebSocket, subscriptions, and external services.
