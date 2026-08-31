---
name: react-review
description: Write or review React components against the patterns that actually cause bugs: unnecessary effects, derived state, stale closures, key misuse, re-render cascades, and premature memoization. Use when writing or reviewing React/Next.js components, when a component re-renders too often or shows stale data, when an effect loops, or on any mention of useEffect, useMemo, memo, state management, or Server Components.
---

# React Review

Most React bugs come from one mistake: **treating render as a place where things happen, rather than as a description of what the UI should be for the current state.** Effects, memoization, and duplicated state are all symptoms of fighting that model.

Not for: how the data gets fetched (`frontend-data-fetching`), or bundle size and Core Web Vitals (`web-performance`).

## Step 1: Most effects shouldn't exist

`useEffect` is for **synchronizing with something outside React**, the DOM, a subscription, a timer, an analytics SDK, a browser API. It is not a lifecycle hook, and it is not where logic goes.

Delete the effect if it's doing any of these:

**Deriving state from props or state:** just compute it during render.
```jsx
// BAD: extra state, extra render, can go stale
const [fullName, setFullName] = useState('');
useEffect(() => { setFullName(`${first} ${last}`); }, [first, last]);

// GOOD
const fullName = `${first} ${last}`;
```
If it's genuinely expensive, wrap it in `useMemo`, still no state, still no effect.

**Resetting state when a prop changes:** give the component a `key` instead. `<Profile key={userId} />` remounts with fresh state, which is what you meant.

**Responding to a user event:** put it in the event handler. Effects run after render, so an effect reacting to a state change is one render behind the event that caused it, and the causality gets lost.

**Chaining state updates:** an effect that sets state, triggering another effect that sets more state, is a render cascade that's hard to follow and easy to loop. Compute the whole result in one place.

**A `setState` in an effect with no dependency array**, or with a dependency the effect itself updates, is an infinite loop. If you're adding `eslint-disable` to the dependency array to stop a loop, the effect is wrong, the lint rule is right.

Legitimate effects: subscriptions, event listeners, timers, imperative DOM work (focus, scroll, measurement), third-party widget lifecycles, and logging. **Every one needs a cleanup function.**

## Step 2: One source of truth for each piece of state

- **Don't copy props into state.** `useState(props.value)` captures the initial value and then silently ignores every update. If you need to reset on change, use `key`.
- **Don't store what you can compute.** Filtered lists, totals, validity flags, and "is anything selected" are derived, computing them during render can't go stale.
- **Colocate state as low as possible.** State lifted higher than needed re-renders everything below it. Push it down until it's at the closest common parent that needs it.
- **Don't duplicate server data into local state:** see `frontend-data-fetching`.

## Step 3: Keys

`key` tells React which item is which across renders. Getting it wrong produces bugs that look like state "jumping between rows".

- **Never use the array index** when the list can reorder, filter, or have items inserted or removed. With index keys, deleting the first row makes every subsequent row inherit the previous row's state, checked checkboxes, focus, and input values all shift by one.
- Use a stable ID from the data. Index is only acceptable for a static, append-only list.
- **Don't use `Math.random()` or a fresh UUID per render:** every item unmounts and remounts every render, destroying state and performance.
- Keys must be unique among siblings, not globally.

## Step 4: Re-renders, measure before optimizing

A re-render is not automatically a problem. React re-renders are usually cheap; the cost is in what they trigger.

**Common causes of avoidable re-renders:**
- A new object, array, or inline function created in render and passed as a prop. Referential identity changes every render, defeating `memo` and re-triggering effects.
- Context whose value is a fresh object literal, every consumer re-renders on any change. Memoize the value, and split contexts that change at different rates.
- State held too high in the tree.

**On memoization:** `memo`, `useMemo`, and `useCallback` have real costs, allocation, comparison, and complexity. Apply them where the React DevTools Profiler shows a problem, not preemptively. Blanket memoization slows apps down and makes dependency arrays a maintenance burden. If the project uses the React Compiler, most manual memoization is redundant. Check before adding more.

**Fix the structure first.** Moving state down or composing with `children` usually eliminates the re-render entirely, which beats memoizing around it.

## Step 5: Closures, refs, and async

- **Stale closures**: a callback captures the values from the render it was created in. A `setInterval` set up once, reading `count`, sees the original `count` forever. Fix with the updater form (`setCount(c => c + 1)`) or a ref.
- **`useRef` for values that shouldn't trigger renders:** timer handles, previous values, mutable flags. Never for something the UI displays.
- **Guard async completions.** A response arriving after unmount, or after the input changed, must not set state. Cleanup and abort, see `frontend-data-fetching`.
- **StrictMode double-invokes** effects and renders in development on purpose, to surface missing cleanup. If something breaks only in StrictMode, the code has a real bug. Don't disable it.

## Step 6: Component shape

- **Composition over prop drilling.** Passing `children` or an element prop usually beats threading a value through four layers, and beats reaching for context.
- **One responsibility per component.** A component doing fetching, transformation, and presentation is hard to test and re-render-expensive. Split the data boundary from the presentation.
- **Controlled vs. uncontrolled. Pick one.** A `value` without `onChange` is a read-only input, and a `value` that flips between `undefined` and a string logs a warning and loses cursor position.
- **Error boundaries** around subtrees that can fail independently. Note they don't catch errors in event handlers or async code, handle those explicitly.
- **On Server Components (React 19 / Next.js App Router):** keep `"use client"` as low in the tree as possible. It's a boundary, and everything below it ships to the browser. Server components can't use state, effects, or browser APIs; a client component can't be `async`. Never pass secrets through props across the boundary. They get serialized into the payload the browser receives.

## Common rationalizations

| "..." | Reality |
|---|---|
| "The effect is simpler than restructuring" | Until it loops, or renders one frame behind. Most effects are a missing derived value |
| "I'll memoize it to be safe" | Memoization costs allocation and comparison, and adds dependency arrays to maintain. Profile first |
| "Index keys are fine, the list doesn't reorder" | Until someone adds a filter or a delete button, and the bug looks like state corruption |
| "I disabled the lint rule because it looped" | The rule found a real bug. The loop is the symptom |
| "Copying the prop into state is easier" | It ignores every subsequent update. That's a stale-UI bug waiting for a code review nobody does |
| "StrictMode double-render is annoying" | It's showing you a missing cleanup that will be a production leak |
| "Context is simpler than passing props" | Context re-renders every consumer. For a value that changes often, composition is both faster and clearer |

## Red flags

- `useEffect` that only calls `setState` from props or state
- A dependency array with `eslint-disable` next to it
- `useState` initialized from a prop that later changes
- `key={index}` on a list that can reorder or filter
- An inline object, array, or arrow function passed to a `memo`-wrapped child
- A context value constructed as a fresh literal in render
- `useMemo`/`useCallback` applied everywhere with no profiling
- An effect with a subscription, listener, or timer and no cleanup
- `"use client"` at the root of the App Router tree
- State that could be computed from other state
