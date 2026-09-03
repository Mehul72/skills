---
name: frontend-data-fetching
description: >-
  Wire a UI to a backend API correctly: request waterfalls, race conditions, the four UI
  states, caching server state, optimistic updates with rollback, pagination, and
  cancellation. Use when building or reviewing any component that calls an API, when data
  appears stale or flickers, when a list is slow to load, or on any mention of useEffect
  fetching, SWR, TanStack Query, loading states, or optimistic UI.
---

# Frontend Data Fetching

This is the seam where a backend engineer's instincts are mostly right and the failure modes are unfamiliar. The core adjustment: **the network is not the slow part, the round trips are.** One 300ms call is fine. Four sequential 300ms calls is a second and a quarter of a blank screen.

Not for: the API contract itself (`api-change-review`), or why the endpoint is slow (`sql-performance`).

## Step 1: Kill the waterfall

A waterfall is a request that can't start until another finishes. It's the dominant cause of slow-feeling UIs, and it hides in ordinary-looking code.

```
BAD  (sequential, 900ms)          GOOD (parallel, 300ms)
  fetch user      ──300ms──▶         fetch user     ──▶│
  fetch orders        ──300ms──▶     fetch orders   ──▶│ 300ms
  fetch prefs             ──300ms──▶ fetch prefs    ──▶│
```

- **Fire independent requests together:** `Promise.all`, or start them all before awaiting any. Sequential `await`s in a row are the classic accidental waterfall.
- **Watch for component-level waterfalls**: a parent fetches, renders a child, the child fetches. The child's request couldn't start until the parent's finished. Hoist the fetch, or fetch both in parallel at the top.
- **Don't gate on non-blocking data.** Render the page with what you have and let secondary panels load independently.
- **If the UI needs three things, consider one endpoint that returns them.** This is the frontend asking for a backend change, and it's usually the right call. You know how to build that.
- **Prefetch on intent:** on hover or focus, before the click.

## Step 2: Handle all four states

Every remote read has four outcomes. Most bugs are a missing third or fourth:

| State | Requirement |
|---|---|
| **Loading** | Skeleton matching final layout, not a spinner that collapses the page (that's a layout shift) |
| **Error** | What failed, and a retry affordance. Never a blank screen or a silent `console.error` |
| **Empty** | A real message. **The most-forgotten state**, an empty list rendered as nothing looks identical to a bug |
| **Success** | The data |

Distinguish **empty** from **loading** from **failed**. All three commonly render as "nothing here", and the user can't tell which, nor can you, in a bug report.

Also handle **stale-while-revalidating**: showing cached data while refetching is good, but signal it, or a user watching a number they expect to change will think the app is broken.

## Step 3: Race conditions

The bug: user types "ab", then "abc". The "ab" response arrives *after* "abc" and overwrites it. Results now don't match the input. **Responses do not arrive in request order**. This is guaranteed to bite any search-as-you-type or tab-switching UI.

Fixes, best first:
- **Use a data-fetching library.** TanStack Query, SWR, and RTK Query solve this by keying requests. This is the main reason to use one.
- **`AbortController`:** cancel the previous request when a new one starts, and on unmount.
- **Ignore stale responses:** capture a sequence number or the request key in the closure, and drop the response if it no longer matches current state.

Cancel in-flight requests on unmount regardless, or you'll set state on a dead component and leak.

## Step 4: Treat server state as a cache, not as state

The mistake that makes React apps hard: putting server data in `useState` or Redux and hand-maintaining it. **Server data is a cache of something you don't own**. It goes stale, needs revalidation, is shared across components, and can fail. That's a different problem from client state (form input, modal open, selected tab).

Use a server-state library, TanStack Query, SWR, RTK Query, or your framework's loader. You get, for free and correct: caching, deduplication of concurrent identical requests, background revalidation, retries, and race-condition safety. Hand-rolling these is where the bugs live.

**Key the cache by every input the request depends on:** endpoint, params, filters, page, *and* the user or tenant. A cache key missing the tenant will show one customer another customer's data, which is a security incident, not a bug.

**On React specifically:** fetching in `useEffect` is not the modern default. It produces waterfalls (fetch starts after render), needs manual race handling and cleanup, and runs twice in StrictMode. Prefer a query library, a route loader, a Server Component, or `use()` with Suspense. Where you do keep an effect, it needs cleanup and a stale-response guard.

## Step 5: Mutations

- **Optimistic updates need a rollback path.** Apply the change immediately, keep the previous value, restore it on failure, and *tell the user it failed*. An optimistic update that silently reverts is worse than a spinner, the user believes their change saved.
- **Invalidate what the mutation affected**, or the list still shows the old row after a successful edit. Getting invalidation wrong is the most common "why is it stale" bug.
- **Disable the submit control while in flight** and make the request idempotent where you can. Double-submit is the frontend half of the idempotency story in `resilience-review`, and a client-side guard alone is not sufficient, because retries also happen at the network layer.
- **Reconcile with the server's response.** The server may have normalized, defaulted, or rejected part of the write. Take its version as truth rather than assuming your optimistic value stuck.

## Step 6: Lists and pagination

- **Cursor/keyset over offset**, for the same reason as the backend: offset pages drift and duplicate when rows are inserted between requests, and get slower the deeper you go.
- **Virtualize long lists** (`react-window`, TanStack Virtual). Thousands of DOM nodes is a main-thread problem, and shows up as bad INP.
- **Infinite scroll needs a keyboard and screen-reader path** to whatever is below it, plus a visible "load more" fallback. It also breaks the browser back button unless you restore scroll position.
- **Don't refetch the whole list after mutating one item** when you can update that entry in the cache.

## Step 7: Failure and auth

- **Set a client-side timeout.** `fetch` has no default timeout, a hung request leaves a spinner forever. Use `AbortSignal.timeout()`.
- **Retry only idempotent reads**, with backoff. Never blind-retry a POST from the client.
- **Handle token refresh once.** Concurrent 401s must not each trigger a refresh, dedupe onto a single in-flight refresh and replay the queued requests. Independent refreshes race and log the user out.
- **Error boundaries** around any subtree that renders remote data, so one failed panel doesn't blank the page.
- **Never render a raw server error.** Map to something the user can act on; log the detail with the correlation ID.
- **Test on a slow, flaky connection.** DevTools throttling to Slow 4G reveals almost all of the above in a few minutes.

## Common rationalizations

| "..." | Reality |
|---|---|
| "useEffect + fetch is simpler" | Until you add cleanup, race guards, caching, retries, and dedup, at which point you've written a worse query library |
| "The API is fast, waterfalls don't matter" | Four sequential 300ms calls is 1.2s of blank screen on a fast API |
| "Race conditions are rare" | They're deterministic in search-as-you-type and tab switching. Users hit them constantly |
| "We'll add the empty state later" | It ships as a blank screen that looks exactly like a bug, and gets reported as one |
| "Redux is where our data goes" | Client state and server cache are different problems. Mixing them is why the store is unmaintainable |
| "Optimistic updates are risky" | Only without rollback. With rollback they're the biggest perceived-speed win available |
| "It works on my connection" | Throttle to Slow 4G. Most of these bugs surface in the first minute |

## Red flags

- `useEffect(() => { fetch(...) }, [])` with no cleanup and no race guard
- A cache key that omits the user, tenant, or a filter the request depends on
- A `fetch` with no timeout and no `AbortController`
- A list rendering `null` when empty
- An optimistic update with no rollback, or a rollback with no user-visible message
- Sequential `await`s for data that has no dependency between the calls
- A raw error object or stack trace rendered into the UI
- Retry logic around a POST on the client
- A refresh-token call that can be triggered concurrently by several 401s
