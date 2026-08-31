# React Unit Test Quick Reference

React tests should prioritize user-visible behavior and hook return values. Use this together with `testing-library.md`.

## Component Tests

- Props: render different props; assert text, button state, and callback arguments.
- Conditional rendering: cover loading, empty, error, and success.
- Lists: assert item count, key items, and empty lists.
- Forms: use `userEvent.type/click/selectOptions`; assert submitted payload.
- Callback props: pass `jest.fn()` / `vi.fn()` / `rs.fn()` and assert calls and arguments.

## Hooks

| Type | Test Focus |
|---|---|
| `useState` / reducer | Initial value and returned value after events |
| `useEffect` | Mount behavior, dependency changes, cleanup |
| `useMemo` / `useCallback` | Assert behavior, not internal caching |
| `useRef` | Assert external effect; avoid implementation details |
| Context hook | Provide wrapper with Provider |
| Async hook | Mock API and `waitFor` final state |

## Special Components

- `memo`: test like a normal component; do not test render skipping.
- `forwardRef`: assert exposed ref methods or DOM node behavior.
- `lazy` / `Suspense`: assert fallback and loaded content.
- Error Boundary: trigger with a throwing child component; mock `console.error` if needed.
- Portal: assert final DOM output; create portal root in test when needed.

## Common Mocks

```ts
jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useNavigate: () => mockNavigate,
  useParams: () => ({ id: '1' }),
}));
```

Mock routing, state management, i18n, analytics, and network calls at module boundaries. Do not mock React core APIs.

## Imports

- Components: `@testing-library/react`
- Hooks: `renderHook` from `@testing-library/react`
- User interactions: `@testing-library/user-event`
