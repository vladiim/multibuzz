---
name: feedback-visible-form-inputs
description: Form inputs must have a visible resting border and real padding. Never ship transparent-border or padding-less inputs.
metadata:
  type: feedback
---

Every `<input>`, `<select>`, and `<textarea>` in the app must have a **visible border at rest** (not transparent, not relying on the focus ring to make it appear) and **real padding** (`px-3 py-2` minimum; `py-3` for prominent CTAs and form fields the user spends time in). Round the corners (`rounded-md`) and add a light shadow (`shadow-sm`) on form fields.

**Why:** User reacted strongly to admin form inputs that rendered borderless and padding-less — they read as half-finished AI output. The baseline is: a user should always be able to *see* an input as a discrete affordance without hovering or focusing it. The pattern I had been shipping (no `border-*` class at rest, relying on `focus:border-indigo-500` only) is wrong and not acceptable.

**How to apply:** Default classes for any new input/textarea/select in this codebase:

```
border border-gray-300 rounded-md shadow-sm px-3 py-2 text-sm
focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500
```

For prominent form fields use `py-3`. For multi-line textareas, also add `min-h-24` or similar so the affordance is obvious before the user types.

Do not strip these baseline classes "to keep the form clean" — clean ≠ invisible. If the design genuinely calls for chromeless inputs (e.g. an inline-edit field), call it out explicitly and confirm; don't infer it from minimalism.

Related: [[feedback_ui_patterns]] — that one's about preferring text+datalist over fancy dropdowns; this one's about how the chosen input is actually drawn.
