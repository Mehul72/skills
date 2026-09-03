---
name: web-performance
description: >-
  Diagnose and fix a slow web page against Core Web Vitals (LCP, INP, CLS) using field data
  first, then a profile. Covers the LCP subpart breakdown, long-task and main-thread work
  behind INP, layout-shift causes, and bundle discipline. Use when a page feels slow, when
  Lighthouse or Search Console flags Core Web Vitals, when reviewing a frontend change for
  performance, or on any mention of bundle size, LCP, INP, CLS, or render blocking.
---

# Web Performance

Two rules, and the first one is where most effort gets wasted:

1. **Measure before changing anything.** An unprofiled optimization is a guess that costs complexity whether or not it works.
2. **Field data decides; lab data explains.** Lighthouse on your laptop is a fast machine on a fast network running no extensions. Real users are on worse hardware than you think.

Not for: a slow API response behind the page (that's `sql-performance` or `resilience-review`, and if TTFB is the problem, it *is* a backend problem). Not for a functional bug (`systematic-debugging`).

## The metrics

Google evaluates at the **75th percentile of real user page loads**. Optimizing the median while p75 stays poor changes nothing.

| Metric | Measures | Good | Poor | Dominant cause |
|---|---|---|---|---|
| **LCP** | Loading, when the largest element paints | ≤ 2.5s | > 4s | Slow TTFB, or the hero resource discovered late |
| **INP** | Responsiveness, interaction to next paint | ≤ 200ms | > 500ms | Long tasks blocking the main thread |
| **CLS** | Visual stability, unexpected layout shift | ≤ 0.1 | > 0.25 | Unsized media, injected content, font swap |

INP replaced First Input Delay in 2024. If you find a doc or dashboard still tracking FID, it's stale. FID only measured input *delay* on the first interaction, so it was passing almost everywhere while pages still felt unresponsive.

**Diagnostic (not Core) metrics:** TTFB explains LCP, FCP isolates render-blocking, TBT is the lab proxy for INP.

## Step 1: Get field data first

- **CrUX:** real Chrome users, p75, 28-day rolling. Search Console's Core Web Vitals report, PageSpeed Insights, or the CrUX API. Free and real, but coarse and lagging.
- **RUM:** the `web-vitals` library reporting to your own backend. Worth it because it segments: by route, device, country, and release. "LCP is bad" is not actionable; "LCP is bad on the product page, on Android, in the last release" is.

Only once you know *which page, which metric, which segment* should you open a profiler. Skipping this is how teams spend a sprint shaving 40KB off a bundle when TTFB was the whole problem.

## Step 2: Attack the metric you actually have

### LCP, break it into its four subparts

This decomposition tells you which team owns the fix:

1. **TTFB**, server response. If this is > 800ms, nothing on the frontend will save you. **This is the backend's problem**: slow queries, no caching, no CDN, cold starts.
2. **Resource load delay**, time between TTFB and the browser *starting* to fetch the LCP resource. Almost always a discovery problem: the image is in CSS, injected by JS, or behind a lazy-loading attribute.
3. **Resource load time**, the download itself. Size and format.
4. **Element render delay**, resource is there but the page hasn't painted. Render-blocking CSS/JS, or client-side rendering the content.

Fixes, roughly in order of payoff:
- Fix TTFB, cache, CDN, edge, faster queries.
- **Never lazy-load the LCP element.** `loading="lazy"` on the hero image is the single most common self-inflicted LCP wound.
- `fetchpriority="high"` on the hero image; `<link rel="preload">` when it's discovered late.
- Serve modern formats (AVIF/WebP), correctly sized via `srcset`/`sizes`.
- Remove render-blocking resources: `defer`/`async` scripts, inline critical CSS.
- `preconnect` to the origin serving the hero resource.

### INP, find the long tasks

INP is main-thread contention. The browser can't paint a response while JavaScript is running.

- Record a Performance trace, interact, and look for **long tasks (> 50ms)**. The offender is usually one of: a large re-render, a synchronous handler doing real work, an expensive layout, or a third-party script.
- **Break up long work and yield** so input can be handled between chunks, `await scheduler.yield()` where available, `setTimeout(0)` as the fallback. Chunking is what converts one 400ms task into eight responsive ones.
- **Do the minimum in the handler**, then defer the rest. Update what the user sees; schedule the analytics, the recompute, the persistence.
- Debounce or throttle high-frequency handlers (`input`, `scroll`, `resize`).
- In React, mark non-urgent updates with `useTransition`/`startTransition` so typing stays responsive while an expensive list re-renders.
- **Audit third-party scripts.** Tag managers, chat widgets, and A/B testing tools frequently dominate INP, and they're invisible in your own code.

### CLS, reserve the space

Every shift is something appearing without its space held open:

- **Always set `width` and `height`** (or `aspect-ratio`) on images, videos, iframes, and ads. The browser then reserves the box before the resource lands.
- Reserve space for anything injected late, banners, cookie notices, embeds. Never insert content above existing content unless it's in response to a user interaction.
- **Fonts**: `font-display: optional` or `swap` plus `<link rel="preload">` on the font, and a fallback metrically matched with `size-adjust`. An unmatched fallback swap shifts every line of text on the page.
- Use `transform` for animation, never properties that trigger layout (`top`, `width`, `margin`).
- Skeletons must match the final content's dimensions, or they trade one shift for another.

## Step 3: Keep the bundle honest

- **Look at the actual bundle** before optimizing it, `webpack-bundle-analyzer`, `vite-bundle-visualizer`, `source-map-explorer`. The problem is almost always one fat dependency (a moment/lodash/icon set imported whole), not your code.
- **Code-split by route**, then lazy-load heavy below-the-fold components with dynamic `import()`.
- **Check import shape**: `import { debounce } from 'lodash'` may pull the entire library; `lodash-es` or `lodash/debounce` doesn't. Same trap with icon libraries and date libraries.
- **Set a budget and enforce it in CI.** A bundle with no gate grows monotonically, every PR adds a little and nobody is responsible for the total. Lighthouse CI or a size check on the PR.

## Step 4: Verify, and keep the ones that worked

- Re-measure the same way you measured before. Same page, same throttling, same conditions.
- **Revert optimizations that didn't move the number.** A `useMemo` that saved nothing is permanent complexity for zero benefit.
- Log the attempts that failed as well as the ones that worked. It stops the next person re-trying them.
- Field data lags: CrUX is a 28-day rolling window, so a real fix takes weeks to show up there. Confirm in your RUM first.
- Add the guard: bundle-size check, Lighthouse CI, or a RUM alert on p75 regression.

## Common rationalizations

| "..." | Reality |
|---|---|
| "It's fast on my machine" | Your machine is a fast laptop on office wifi with a warm cache. Throttle to 4x CPU slowdown and Slow 4G |
| "Lighthouse gives us 98" | Lighthouse is a lab simulation of one load. Field p75 is what users and Search Console see |
| "Let's memoize everything" | `useMemo`/`memo` have their own cost and hide the real problem. Profile, then memoize what showed up |
| "The bundle is only 300KB" | Gzipped or not? Parse and execute cost on a mid-range Android is several times the download cost |
| "We'll add lazy loading everywhere" | Lazy-loading the LCP element makes LCP worse. It's for below the fold only |
| "CLS doesn't matter, it's cosmetic" | It's users tapping the wrong button because the page moved under them |
| "The third-party script is required by marketing" | Then measure its cost and show them the number. That's a tradeoff decision, not a technical constraint |

## Red flags

- An optimization PR with no before/after measurement
- `loading="lazy"` on a hero image
- Images or embeds without `width`/`height` or `aspect-ratio`
- Any `<script>` in `<head>` without `defer` or `async`
- A default import of a large utility or icon library
- No bundle-size gate in CI
- Core Web Vitals tracked only from Lighthouse, with no field data at all
- A dashboard still tracking FID
