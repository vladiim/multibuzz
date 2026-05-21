# Onboarding Copy & UX Revamp

**Date:** 2026-05-22
**Priority:** P1
**Status:** Complete (2026-05-22)
**Branch:** `feat/guided-setup-service`

---

## Summary

User-feedback pass over the signup + onboarding flow. The Guided Setup mechanics ([[guided_setup_service_spec]]) stay intact — this spec only revises copy, layout, and the welcome/kickoff-confirmation pages.

Six phases, one commit per phase.

---

## Phase 1 — Signup page (`/signup/new`)

**File:** `app/views/signup/new.html.erb`

- Drop the top "mbuzz" brand header (`<h1>` + subhead).
- Drop the duplicate "Create your account" / "No credit card required" inside the card.
- New header above the card: bold `Create your account` (h1, 2xl). Subhead `No credit card required` styled to stand out — green check icon + medium font, indigo or gray-900.

### Acceptance

- `assert_select "h1", /Create your account/`
- "mbuzz" brand string is gone from the page body.
- "No credit card required" appears exactly once.

---

## Phase 2 — Remove `/signup/welcome`

The welcome page is bullshit (user's word): one click between signup and onboarding with no value.

- `SignupController#welcome` action removed; route removed.
- `SignupController#create` redirects to `onboarding_path`.
- The GTM `signup_complete` block (with `user_id_hashed` SHA256 of lowercase email) moves to `app/views/onboarding/show.html.erb`. Renders once per session: only when `current_account.setup_path.blank?` (the natural post-signup landing state).
- `SignupController` no longer needs `welcome` or `signup_welcome_path`. Computes `user_id_hashed` and stores in session for the next request? **No** — recomputed in `OnboardingController#show` from `current_user.email`. Simpler.
- The `signup_welcome` flash banner used to confirm. Replaced by direct landing on onboarding setup-choice.

### Acceptance

- `post signup_path` redirects to `onboarding_path` (not `signup_welcome_path`).
- `get onboarding_path` while signed in renders the GTM dataLayer push for `signup_complete` with `user_id_hashed`.
- `signup_welcome_path` no longer resolves (route removed).
- The 3 `signup_welcome` tests in `signup_controller_test.rb` are removed; new test in `onboarding_controller_test.rb` asserts GTM event fires on first landing.

**Note:** the GTM event currently fires on welcome → fires on `/onboarding` on first land. To avoid double-firing if the user revisits `/onboarding`, only render the dataLayer block when `current_account.setup_path.blank?`. Once they click a card, `setup_path` is set and the block stops rendering. Acceptable because the post-signup land is the only state where it should fire.

---

## Phase 3 — `/onboarding` (3-option cards)

**File:** `app/views/onboarding/show.html.erb`

| Card | New title | New description |
|---|---|---|
| Self-serve | `I'll do it` | `You install the SDK and API calls.` |
| Teammate | `My teammate will` | `Invite a developer to handle the install.` (unchanged) |
| Assisted | `We'll do the install` | `We'll do the install for a fee.` |

### Acceptance

- `assert_select "h3", /I'll do it/`
- `assert_select "h3", /My teammate will/`
- `assert_select "h3", /We'll do the install/`
- Body text "You install the SDK and API calls" present.

---

## Phase 4 — `/onboarding/discovery`

**Files:** `app/views/onboarding/discovery.html.erb`, `Onboarding::AssistedPath#discovery_params`

- Header: `Let's get started`
- Subhead: `4 quick questions`
- **Q1 (attribution goal): multiselect.** Switch `radio_button_tag` → `check_box_tag` for `setup_profile[attribution_goal][]`. The "Other" option also becomes a checkbox + text field.
- `discovery_params`: `attribution_goal` permits an array (`attribution_goal: []`); keep `attribution_goal_other` as scalar.
- **Q3:** legend changes from "Which platform(s) is mbuzz going on?" to `Which platform/s do you use?`. Append a final checkbox `I'm not sure yet` with value `unsure`.

### Data shape

`setup_profile.attribution_goal` becomes an array of strings (was a single string). All readers must tolerate either shape during the transition.

Audit:

- `lib/specs/guided_setup_service_spec.md` — references the field
- `app/services/internal_notifications/signup_stats_service.rb` — if it reads the field, normalize via `Array.wrap`
- `GuidedSetup.integration_target_for(setup_profile)` — confirm it only reads `ad_platforms`, not `attribution_goal`
- Admin views

Anywhere that displays `attribution_goal` should `Array.wrap(...).join(", ")`. Anywhere that branches on its value should treat it as `include?`.

### Acceptance

- `assert_select "h2", /Let's get started/`
- `assert_select "p", /4 quick questions/`
- `assert_select "input[type=checkbox][name='setup_profile[attribution_goal][]']", count: 3` (ecommerce, b2b_leads, signups; "other" via Other field still a checkbox)
- `assert_select "input[type=checkbox][name='setup_profile[install_platforms][]'][value='unsure']"`
- `assert_select "legend", /Which platform.s do you use\?/`
- Posting `setup_profile[attribution_goal][]=ecommerce&setup_profile[attribution_goal][]=b2b_leads` persists `["ecommerce", "b2b_leads"]`.

---

## Phase 5 — `/onboarding/guided_setup`

**File:** `app/views/onboarding/guided_setup.html.erb`

### Structure (top-to-bottom)

1. Page header: `Last step` (h2)
2. **Booking form card** (titled `Book your kickoff`):
   - Helper line under title: `We'll respond within one business day with options.`
   - Timezone: **searchable select**. Plain `<select>` + a filter `<input>` enhanced by a small Stimulus controller (`searchable-select`) that hides non-matching options. No external library. Default option is "Select your time zone". Drop the "We need this to schedule the kickoff call" hint entirely.
   - Days: label `Your preferred days`. Single hint: `Tick all the days that work.` Chip pills unchanged.
   - Times: label `Your preferred times`. Single hint: `Tick all the times that work. Times are in your time zone.` Chip pills unchanged.
   - Submit: `Book kickoff call` (unchanged)
3. Section header `What happens next` followed by the 4-step cards. Step 3 description updated: `Connect Meta Ads, Google Ads, or server-side GTM — or we'll build one for you if you don't have one.` (note: per repo style, use an en-dash not an em-dash; the rule is no em-dashes — en-dashes for ranges are fine, but for clause separators use a period or comma. So rewrite: `Connect Meta Ads, Google Ads, or server-side GTM. We'll build one for you if you don't have one.`)
4. Section header `Install service inclusions` with three lines:
   - `Price: $1,500 USD` (bold)
   - `Non-refundable mbuzz credit`
   - `Payment due after the kickoff call`
5. Delete the existing "Pricing & plan covered on the kickoff call" indigo panel — superseded.

### Stimulus controller

`app/javascript/controllers/searchable_select_controller.js` — small, no deps:
- Targets: `input` (filter), `select` (the real select).
- Action: `input->searchable-select#filter` hides options whose label doesn't contain the filter string (case-insensitive). Selected value still posts via the underlying `<select>`.

### Acceptance

- `assert_select "h2", /Last step/`
- `assert_select "[data-testid='book-kickoff-form'] h3", /Book your kickoff/`
- Form appears in DOM before the "What happens next" section (order assertion via `index`).
- Timezone is a `<select name='scheduling_preferences[timezone]'>` (was `<input list=...>`).
- `assert_select "[data-controller~='searchable-select']"`
- Day label assertion: `Your preferred days` (no "optional").
- Time label assertion: `Your preferred times` (no "optional").
- "We need this to schedule the kickoff call" is gone.
- Old "Pricing & plan covered on the kickoff call" panel gone.
- New inclusions block contains `Price: $1,500 USD`, `Non-refundable mbuzz credit`, `Payment due after the kickoff call`.

---

## Phase 6 — Kickoff confirmation goes to dashboard

Replace the standalone `kickoff_booked` page with a dashboard banner.

- `book_kickoff` now does: `redirect_to dashboard_path, notice: "Kickoff booked. We'll be in touch."`
- `kickoff_booked` route, action, and view are deleted.
- `Onboarding::AssistedPath` no longer redirects to `kickoff_booked_path`; remove `before_action` reference and the `kickoff_booked` filter list.
- `guided_setup` action's "redirect if already booked" branch redirects to `dashboard_path` instead.
- Dashboard layout renders flash. Add `<%= render "shared/flash" %>` to `app/views/dashboard/show.html.erb` (top of page). Create `app/views/shared/_flash.html.erb` rendering `notice` and `alert` as toast banners. Apply same to other authenticated layouts if no global flash render exists.

### Acceptance

- `post onboarding_book_kickoff_path` with valid params redirects to `dashboard_path`, not `onboarding_kickoff_booked_path`.
- `flash[:notice]` is `"Kickoff booked. We'll be in touch."`
- `get dashboard_path` with that flash renders the banner text.
- `onboarding_kickoff_booked_path` route no longer resolves.
- The 4 `kickoff_booked` tests in `onboarding_controller_test.rb` are removed.
- `guided_setup` action with a pre-existing booking redirects to `dashboard_path` (test updated).

---

## Out of scope

- The `kickoff_booked` recap card ("What you told us") goes away with the page. Specialist still receives full prefs via `GuidedSetupMailer.welcome`.
- No DB migration. `attribution_goal` array storage uses existing JSONB.
- Welcome mailer copy (`onboarding_mailer/welcome.html.erb`) unchanged.

---

## Commit plan

One commit per phase:

1. `feat(signup): clean up signup form headers`
2. `refactor(signup): drop welcome page, redirect to onboarding`
3. `feat(onboarding): update setup-choice card copy`
4. `feat(onboarding): multiselect discovery Q1, rephrase Q3, add unsure option`
5. `feat(onboarding): restructure guided_setup with form-first and service inclusions`
6. `refactor(onboarding): replace kickoff_booked page with dashboard flash banner`
