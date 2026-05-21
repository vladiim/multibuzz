# mbuzz Design System

The source of truth for layout, typography, controls, and voice across the mbuzz product surface. New screens conform; existing screens migrate when touched.

**Status:** v1, derived from the 2026-05 onboarding cohesion audit. Onboarding is the first surface to land on this system; admin and dashboard follow as they're touched.

**Mockups:** `lib/mockups/onboarding-chrome.html` is the canonical reference for the onboarding chrome and the resume-nav pill.

---

## 1. Principles

- **One way to do each thing.** If two patterns exist for the same role, one of them is wrong. Pick, document here, and migrate.
- **Make the affordance visible.** Never rely on focus/hover to make an input or button look like one. Borders and padding at rest are non-negotiable.
- **Chrome over body.** Cross-cutting concerns (progress, exit, branch label) live in the chrome. Don't repeat them in the body.
- **Verbs match outcomes.** `Continue` for safe forward steps. Concrete verbs (`Pay $1,500`, `Send invite`, `Book kickoff`) only when the action is irreversible or commits money.

---

## 2. Layout primitives

### 2.1 Container widths

| Width | Use for |
|---|---|
| `max-w-3xl` | Default. Forms, content-dense screens, plan pickers, code blocks. |
| `max-w-4xl` | Hero screens. Setup choice, install-service overview, attribution celebration. |
| `max-w-7xl` | App shell (dashboard, admin). |

Never use `max-w-2xl` or `max-w-5xl`. They produce gratuitous width drift between adjacent screens.

### 2.2 Page padding

```
class="min-h-screen bg-gray-50 py-12 sm:px-6 lg:px-8"
```

Use on every full-page route. Do not add `flex flex-col justify-center` — vertical centering varies with content height and reads as inconsistent across screens.

### 2.3 Card / panel

```
class="bg-white border border-gray-200 rounded-lg shadow-sm p-6"
```

Standard card. `rounded-xl`, `rounded-2xl`, the borderless `shadow` (no `-sm`), and `p-5`/`p-8` are deprecated. One exception: the install-service hero promo card may use a gradient — but it's the *only* sanctioned gradient and it stays at `rounded-2xl`.

### 2.4 Vertical rhythm

- `mb-6` between major card sections
- `space-y-4` for stacked form rows inside a card
- `mt-2` for subhead beneath a heading
- `mt-8` between the page heading and the first card

---

## 3. Typography

| Role | Class | Example |
|---|---|---|
| Page title | `text-3xl font-bold text-gray-900` | "Set up your SDK" |
| Hero title | `text-4xl font-bold text-gray-900 tracking-tight` | "You're all set!" |
| Subhead | `text-lg text-gray-600 mt-2` | "Follow these steps to start tracking events." |
| Section heading (in card) | `text-base font-semibold text-gray-900` | "Your API Key" |
| Body | `text-sm text-gray-700` | Paragraph copy. |
| Muted / helper | `text-sm text-gray-500` | "Times are in your time zone." |
| Field label | `block text-sm font-medium text-gray-700 mb-1` | "Email" |
| Mono / code | `font-mono text-sm text-gray-900` | API keys, code snippets. |

`font-extrabold` is deprecated. `font-semibold` is reserved for section headings and prominent CTAs.

### 3.1 Alignment

- Body content: **left-aligned.** Always.
- Hero / celebration screens (`max-w-4xl` from §2.1): **centered.**
- A page title is *never* centered inside a content-dense screen.

---

## 4. Colour

mbuzz is an indigo accent on a gray-50 / white surface. The full palette in active use:

| Token | Use |
|---|---|
| `bg-gray-50` | Page background |
| `bg-white` | Card surface |
| `text-gray-900` | Headings, primary text |
| `text-gray-700` | Body text |
| `text-gray-600` | Subhead, muted body |
| `text-gray-500` | Helper text |
| `border-gray-300` | Input borders, secondary button borders |
| `border-gray-200` | Card borders |
| `bg-indigo-600` / `hover:bg-indigo-700` | Primary action background |
| `text-indigo-600` / `hover:text-indigo-800` | Inline links |
| `bg-indigo-50` / `text-indigo-700` | Numbered step circles, info pills |
| `bg-red-50` / `border-red-200` / `text-red-700` | Errors |
| `text-green-600` | Success checkmark glyphs |

Reserve indigo gradients for the install-service hero promo. Yellow (`bg-yellow-50`) is not part of the system — use the muted-empty pattern in §8 instead.

---

## 5. Buttons

### 5.1 Primary

```
class="px-5 py-2.5 bg-indigo-600 text-white rounded-md shadow-sm font-medium
       hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500
       focus:ring-offset-2"
```

### 5.2 Primary prominent

Reserved for ship-it / payment moments (`Pay $1,500`, `Send invite`, `Book kickoff`):

```
class="px-6 py-3 bg-indigo-600 text-white rounded-md shadow-sm font-semibold
       hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500
       focus:ring-offset-2"
```

### 5.3 Secondary

```
class="px-5 py-2.5 bg-white text-gray-700 border border-gray-300 rounded-md
       shadow-sm font-medium hover:bg-gray-50 focus:outline-none focus:ring-2
       focus:ring-indigo-500 focus:ring-offset-2"
```

### 5.4 Tertiary / inline link

```
class="text-sm text-gray-600 hover:text-gray-900"
```

Used for **only**: in-chrome navigation (Exit to dashboard, ← Back), inline links inside copy. Never as a primary action.

### 5.5 Destructive

```
class="px-5 py-2.5 bg-white text-red-700 border border-red-300 rounded-md
       shadow-sm font-medium hover:bg-red-50"
```

Reserved for delete/cancel-membership-class actions.

---

## 6. Form inputs

**Non-negotiable baseline.** See `lib/memory/feedback_visible_form_inputs.md` for the why.

```
class="block w-full border border-gray-300 rounded-md shadow-sm px-3 py-2 text-sm
       focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
```

Applies to every `<input>`, `<select>`, and `<textarea>` unless the design *explicitly* calls for a chromeless surface (e.g., an inline-edit field), in which case it's annotated in the view as such.

### 6.1 Labels

```
<label class="block text-sm font-medium text-gray-700 mb-1">…</label>
```

Labels always precede their input. Required marker: `<span class="text-red-600">*</span>` immediately after the label text.

### 6.2 Field-level error

```
<p class="mt-1 text-sm text-red-600">…</p>
```

### 6.3 Help text

```
<p class="mt-1 text-sm text-gray-500">…</p>
```

### 6.4 Textareas

Add `min-h-24` or larger so the affordance is obvious before the user types.

### 6.5 Checkbox / radio rows

```
<label class="flex items-center gap-2 py-1 text-sm text-gray-700">
  <input type="checkbox|radio" class="rounded text-indigo-600 focus:ring-indigo-500">
  …
</label>
```

`accent-color` declarations are deprecated — use the explicit Tailwind classes above.

---

## 7. Status idioms

Three shared patterns. Don't invent fourth.

### 7.1 Waiting

```erb
<%= render "shared/waiting_state", heading: "…", body: "…" %>
```

Centered, indigo spinner in a circular indigo-50 background, heading, body. Used by: `verify`, `payment_complete_processing`, any "we're working on it" state. The SVG should live in the partial once, not be re-pasted per view.

### 7.2 Success / completion

```erb
<%= render "shared/success_state", emoji: "🎉", heading: "…", body: "…", cta: { href: …, label: "…" } %>
```

Centered. Single hero emoji or checkmark. 3xl/4xl bold heading. Body. One primary CTA. No coloured banners.

### 7.3 Empty (waiting for data)

Plain inline note inside the relevant card:

```html
<p class="text-sm text-gray-500">No conversions tracked yet. They'll appear here as they come in.</p>
```

No yellow / orange tinted alert boxes.

### 7.4 Error / alert

```html
<div class="p-3 bg-red-50 border border-red-200 rounded-md text-sm text-red-700">
  …
</div>
```

For inline form errors and full-screen failures alike.

---

## 8. Iconography

Three sanctioned families. Anything else needs a §11 entry.

- **Emoji** — only on the setup-choice cards (the choice is personality-driven), and on hero success states (one emoji, large).
- **Numbered indigo circles** — `w-8 h-8 rounded-full bg-indigo-50 text-indigo-700 font-bold flex items-center justify-center` — for ordered step lists *inside* content (the install-service "what you get" cards).
- **Inline SVG glyphs** — checkmark, spinner, arrow, GitHub mark. Use Heroicons-style 24×24 stroke=2. Colour via `text-*` classes.

Never mix three families on one screen. Pick one per role.

---

## 9. Voice & terminology

| Concept | Use | Don't use |
|---|---|---|
| The onboarding process | "Setup" | "Set up", "Onboarding", "Get started flow" |
| Branch choice prompt | "How do you want to set up mbuzz?" | "Who's handling your set up?", "How do you want to get set up?" |
| Forward (safe) | "Continue" | "Next", "Go", "Proceed" |
| Forward (commit) | "Pay $1,500", "Send invite", "Book kickoff" | "Submit", "Confirm" |
| Exit | "Exit to dashboard" (chrome only) | "Skip setup", "Skip" |
| Branch change | "Change my setup choice" (gated, chrome only) | "Change setup option", "Restart" |
| Completion | "You're all set." | "Setup complete!", "Done!", "Congrats!" |
| Pricing intro | "$1,500 today. Net cost: $0." | "$1500 fee", "Setup cost" |
| Empty data | "Nothing here yet." | "No data found", "(empty)" |

**Capitalisation.** Sentence case for headings and button labels. Title case only for proper nouns (mbuzz, Stripe, Meta).

**Punctuation.** Periods on full sentences (including help text). Never em dashes — they read as AI-written (see `feedback_no_em_dashes`). Use periods, commas, or colons.

---

## 10. Onboarding chrome

The unifier across self-serve, teammate, and assisted paths. Specified in `lib/mockups/onboarding-chrome.html` (open in a browser to inspect).

**Three structural elements:**

1. **Top bar.** `mbuzz · <branch label>` on the left. `Exit to dashboard ✕` (boxed link) on the right.
2. **Pip rail.** Branch-specific ordered milestone list. Done = filled, current = filled with halo, upcoming = outlined, locked = dashed outline.
3. **Body.** The actual step content — uses the layout, typography, and card rules above.

**Branch pip sequences:**

| Branch | Pips |
|---|---|
| Self-serve | Pick path · API key · Install · Verify event · Conversion · Done |
| Teammate | Pick path · Invite sent · Teammate installs · Done |
| Assisted | Pick path · Discovery · Book kickoff · Pay · Done |

For assisted, `Pay` is `locked` until the admin generates a payment link — communicates "this is in your future but not reachable yet".

**Resume nav:** the `Finish setup · NN%` pill in the main app top nav. Present whenever `current_account.onboarding_status` is `:in_progress`. Click target is `current_account.onboarding_resume_path` — the single resolver (see the onboarding spec).

---

## 11. Cross-cutting rules (already enforced via memory)

These design behaviours have hit a stronger-than-doc rule already and are tracked in `lib/memory/`:

- [Visible form inputs are non-negotiable](../memory/feedback_visible_form_inputs.md) — §6 codifies the baseline.
- [Plain inputs, empty-state-first, no mode-switching](../memory/feedback_ui_patterns.md) — text+datalist over fancy dropdowns; design the empty state first; no sentinel-mode hacks.
- [No em dashes in user-facing copy](../memory/feedback_no_em_dashes.md) — see §9.
- [Latest word supersedes earlier preference](../memory/feedback_latest_word_supersedes.md) — when the user simplifies, drop the superseded variant entirely, don't re-attach it citing what they said before.

---

## 12. Where to look first

| If you're building… | Read first |
|---|---|
| An onboarding screen | §10 (chrome) + `lib/mockups/onboarding-chrome.html` |
| Any new form | §6 + the input baseline in `lib/memory/feedback_visible_form_inputs.md` |
| A success / waiting / empty state | §7 (use the partials, don't reinvent) |
| A new admin surface | §11 + `lib/memory/feedback_admin_surfaces_register_in_admintools.md` |
| Copy/CTAs | §9 (verb glossary) |
| Anything with a card | §2.3 |

---

## 13. Open questions / TBD

- Shared partials `shared/_waiting_state.html.erb` and `shared/_success_state.html.erb` don't exist yet — to be extracted during onboarding cohesion work.
- Resume-nav pill needs an `onboarding_resume_path` resolver — specced in the onboarding cohesion work (see `lib/specs/guided_setup_service_spec.md`).
- Mobile breakpoints for the pip rail beyond a certain pip count (≥6) — current mockup assumes desktop; treatment for narrow viewports TBD.
- `lib/memory/` pointers above will move into a sourced `lib/memory/` index automatically once the design system gets its first migration commit; for now they're hand-linked.
