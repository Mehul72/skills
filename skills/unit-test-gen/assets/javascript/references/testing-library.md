# Testing Library Quick Reference

Use for React and similar user-behavior-focused component tests. Prefer observable behavior over internal state.

## Basic Structure

```ts
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

it('submits form', async () => {
  const user = userEvent.setup();
  render(<Form onSubmit={onSubmit} />);

  await user.type(screen.getByLabelText('Name'), 'Alice');
  await user.click(screen.getByRole('button', { name: 'Submit' }));

  expect(onSubmit).toHaveBeenCalledWith(expect.objectContaining({ name: 'Alice' }));
});
```

## Query Priority

1. `getByRole` with `name`
2. `getByLabelText`
3. `getByPlaceholderText`
4. `getByText`
5. `getByDisplayValue`
6. `getByAltText` / `getByTitle`
7. `getByTestId` as last resort

Selection rules:

- Must exist: `getBy*`
- May not exist: `queryBy*`
- Appears asynchronously: `findBy*`
- Scoped search: `within(container).getBy*`

## Interactions and Async

- Prefer `userEvent`; use `fireEvent` only for low-level events.
- Most `userEvent` calls are async; use `await`.
- Wait for state changes with `await waitFor(() => expect(...))`.
- Wait for removal with `waitForElementToBeRemoved`.
- Do not assert before async effects settle.

## Hook Tests

```ts
import { renderHook, act } from '@testing-library/react';

const { result, rerender } = renderHook(({ id }) => useUser(id), {
  initialProps: { id: '1' },
});

await waitFor(() => expect(result.current.loading).toBe(false));
rerender({ id: '2' });
```

Wrap manually triggered synchronous state updates in `act(() => ...)`.

## Provider Wrapper

```ts
const wrapper = ({ children }) => (
  <Provider store={store}>
    <Router>{children}</Router>
  </Provider>
);

render(<Page />, { wrapper });
renderHook(() => useFeature(), { wrapper });
```

## Network and External Dependencies

- If the component only needs API results, mock the API module first.
- MSW can preserve request semantics, but do not add MSW when the project does not already use it.
- Mock timers, WebSocket, Observer, router, clipboard, localStorage, and other environment dependencies.

## Common Errors

| Error | Fix |
|---|---|
| `Unable to find role` | Check accessible name, or use a more appropriate query |
| `not wrapped in act(...)` | Wait for user interaction and async state updates before asserting |
| `document is not defined` | Use jsdom/happy-dom test environment |
| JSX parse failure | Use `.tsx` test file |
| Test leakage | Clean mocks, timers, and DOM in `afterEach` |
