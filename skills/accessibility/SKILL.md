---
name: accessibility
description: >-
  Build or review a UI so it works with a keyboard, a screen reader, and low vision: semantic
  HTML, focus management, labelled forms, accessible errors, contrast, and live regions,
  against WCAG 2.2 AA. Use when building forms, modals, menus, tables, or custom interactive
  widgets, when reviewing UI for a11y, or on any mention of accessibility, a11y, ARIA,
  keyboard navigation, screen readers, or WCAG.
---

# Accessibility

Most accessibility failures are not exotic. They're a `<div>` used as a button, an input with no label, and an error message only conveyed by turning the border red. Those three account for an enormous share of real-world problems, and all three are cheap to avoid while writing the code and expensive to retrofit.

Not for: React component patterns (`react-review`) or page speed (`web-performance`), though a skeleton that shifts the layout is both an a11y and a CLS problem.

Target **WCAG 2.2 level AA**, the current W3C Recommendation (2023, updated 2024), and the level named by most legal and procurement requirements. It's backwards compatible: meeting 2.2 means meeting 2.1 and 2.0.

## Step 1: Use the right element

**The first rule of ARIA is not to use ARIA.** A native element gives you keyboard behavior, focus, roles, and states for free, correctly, across every browser and assistive technology.

| Need | Use | Not |
|---|---|---|
| Action | `<button>` | `<div onClick>` |
| Navigation | `<a href>` | `<div onClick={navigate}>` |
| Form control | `<input>`, `<select>`, `<textarea>` | Custom divs |
| Toggle | `<input type="checkbox">` | A styled div with state |
| Modal | `<dialog>` | A positioned div |
| Disclosure | `<details>`/`<summary>` | Manual show/hide |
| Table of data | `<table>` with `<th scope>` | Divs with grid CSS |

`<div onClick>` is not focusable, not keyboard-operable, and announces as nothing. Fixing it with `tabindex`, `role`, `onKeyDown`, and `aria-pressed` is four attributes and a handler to reproduce what `<button>` does correctly by default.

**Buttons do things; links go places.** If it changes the URL, it's an `<a href>`. That's what enables middle-click, open-in-new-tab, and "where am I going" on hover.

Structure matters too: one `<h1>` per page, headings that don't skip levels, and landmarks (`<main>`, `<nav>`, `<header>`) so screen-reader users can jump. `<html lang="en">` is one attribute and changes the pronunciation of the entire page.

## Step 2: Keyboard

Everything operable by mouse must be operable by keyboard. Test it by putting the mouse away and pressing Tab.

- **Visible focus indicator, always.** `outline: none` with no replacement is the single most damaging line of CSS in accessibility. If the default ring is ugly, style it, `:focus-visible` gives you keyboard-only focus rings without showing them on mouse click.
- **Focus order follows visual order.** Reordering visually with CSS `order` or `flex-direction: row-reverse` while leaving DOM order alone desynchronizes them.
- **No keyboard traps.** You must always be able to Tab out of a widget.
- **Skip link** to main content as the first focusable element, visible at least on focus.
- **`tabindex`**: `0` to add something to the tab order, `-1` to make it programmatically focusable only. **Never a positive value**. It hijacks the order of the whole page.
- **Standard keys for custom widgets**: Enter/Space activate, Escape closes, arrows move within a composite widget (menu, tabs, listbox).

## Step 3: Focus management

Anything that changes what's on screen must put focus somewhere sensible. This is where SPAs typically fail.

- **Modal**: move focus into the dialog on open, trap it inside while open, restore it to the trigger on close. `<dialog showModal()>` does all of this. Screen-reader users left outside a modal have no idea it opened.
- **Route change in an SPA**: focus the new page's heading or a container, and announce it. Otherwise focus stays on the clicked link and the screen reader says nothing, the app appears to do nothing.
- **Deleting the focused element**: move focus deliberately (next item, or the list container). Focus falling to `<body>` drops the user to the top of the page.
- **Never steal focus** while someone is typing.

## Step 4: Forms

Where most real-world damage happens, and where backend engineers building admin panels most often slip.

- **Every input has a real `<label for>`.** Placeholder is not a label. It disappears on typing, fails contrast, and isn't reliably announced.
- **`aria-label`** only for genuinely visual-free controls, like an icon-only button.
- **Group related controls** in `<fieldset>` with `<legend>`, radios and checkbox sets especially.
- **Required indicated by more than color**, and marked with the `required` attribute.
- **Errors must be programmatically associated**, not just visually adjacent:
  ```html
  <label for="email">Email</label>
  <input id="email" type="email" aria-invalid="true" aria-describedby="email-err"
         autocomplete="email" required>
  <p id="email-err">Enter an email address, like name@example.com</p>
  ```
- **Errors say what to do.** "Invalid input" is useless; "Enter an email address, like name@example.com" is actionable.
- **On submit failure**, move focus to a summary or the first bad field. A user who tabs to submit and hears nothing doesn't know it failed.
- **`autocomplete` on known fields:** a WCAG 2.2 criterion, and a genuine convenience.
- **Never rely on color alone** for error state: add an icon or text.

## Step 5: Visual and dynamic

**Contrast (AA):** 4.5:1 for body text, 3:1 for large text (18pt / 14pt bold) and for UI component boundaries and icons. Check placeholder text, disabled states, and text over images, the usual failures. Never convey information by color alone.

**Zoom and reflow:** usable at 200% zoom, and at 320px width without horizontal scrolling. Use relative units; don't disable pinch-zoom on mobile.

**Motion:** respect `prefers-reduced-motion`. Nothing flashes more than three times per second. That's a seizure risk, not a preference. Auto-playing carousels need a pause control.

**Targets:** at least 24x24 CSS px (WCAG 2.2 AA); 44x44 is the comfortable mobile norm.

**Announcing changes:** dynamic content that appears without a page load, toasts, validation results, search results, loading completion, needs `aria-live`. Use `polite` for almost everything; `assertive` interrupts and should be reserved for genuine urgency. The live region must exist in the DOM *before* the content is inserted into it.

**Images:** meaningful ones get `alt` describing their purpose; decorative ones get `alt=""` so screen readers skip them. Never omit the attribute. That makes the filename get read out.

## Step 6: Test it

Automated tooling catches perhaps a third of issues. Run it, then do the manual checks. They're fast:

- **Automated:** axe DevTools, Lighthouse, or `eslint-plugin-jsx-a11y` in CI. Cheap, and catches contrast, missing labels, and bad ARIA.
- **Keyboard:** unplug the mouse. Tab the whole flow. Can you reach and operate everything? Is focus always visible? Can you escape every widget?
- **Screen reader:** VoiceOver (Cmd+F5 on macOS) or NVDA (Windows, free). Fifteen minutes on your own form is more informative than any checklist. Listen for unlabelled controls and silence after actions.
- **Zoom** to 200% and check nothing is clipped or overlapping.

## Common rationalizations

| "..." | Reality |
|---|---|
| "It's an internal admin tool" | Colleagues have disabilities, use keyboards, and get injuries. Internal tools are also where accessibility habits form |
| "We'll do an accessibility pass before launch" | Retrofitting means rewriting components. Semantic HTML costs nothing while you're writing it |
| "Add ARIA to make it accessible" | Bad ARIA is worse than none. A native element usually beats every ARIA attribute you'd add |
| "The placeholder says what it is" | It vanishes when typing, fails contrast, and isn't a label |
| "We removed focus outlines for design" | You made the app unusable by keyboard. Style the ring instead |
| "Screen reader users won't use this feature" | You don't know that, and the same fixes help keyboard, voice control, and zoom users |
| "axe passes, so we're accessible" | Automated tools catch roughly a third. The keyboard pass takes two minutes |

## Red flags

- `<div>` or `<span>` with an `onClick` and no `role`/`tabindex`/key handler
- `outline: none` without a `:focus-visible` replacement
- An input whose only label is a placeholder
- Error state conveyed by border color alone, with no `aria-describedby`
- A modal that doesn't move, trap, or restore focus
- `tabindex` with a positive value
- An SPA route change that never moves focus
- An icon-only button with no accessible name
- Toasts or async results with no live region
- `<img>` with no `alt` attribute at all
- Disabled pinch-zoom (`user-scalable=no`)
