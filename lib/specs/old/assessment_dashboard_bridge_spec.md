# Assessment ↔ Dashboard Bridge Specification

**Date:** 2026-05-08
**Priority:** P1
**Status:** Complete
**Branch:** `develop` (shipped directly)

---

## Summary

The Measurement Maturity Assessment dashboard (`/measurement-maturity-assessment/dashboard`) and the mbuzz product dashboard (`/dashboard`) live in complete isolation. A user finishes the assessment, sees their Level X result, and has no path forward into the product. Once they're in the product, there is no way back to their score. This spec adds two bridges and re-scopes the assessment from per-user to per-account so the maturity score becomes a property of the org, not the individual:

1. A permanent CTA on the score dashboard pointing into mbuzz.
2. The current account's score surfaced from inside the product (account dropdown + settings sidebar) — never in the top nav itself.
3. **Data model change:** `ScoreAssessment` gains `account_id`. The canonical lookup becomes `current_account.score_assessments`. `user_id` stays as "who took it" provenance, but is no longer how we route.

---

## Current State

### Assessment dashboard (`app/views/score/dashboard/show.html.erb`)
- Header: Level pill + insight paragraph.
- Tabs: Overview / Dimensions / Roadmap / Business Case.
- Bottom actions: "Retake Assessment" + "Share Assessment Link".
- No CTA to start using mbuzz. The conversion moment (Business Case shows estimated $20K–$200K misallocated spend) is buried behind a tab.

### Product nav (`app/views/layouts/_nav.html.erb`)
- Logo · Account dropdown (TEST ▾) · User avatar dropdown.
- Account dropdown: account list, Create Account, Account Settings.
- User dropdown: email, Logout.
- No reference to the user's measurement maturity score.

### Account settings sidebar (`app/views/layouts/_account_nav.html.erb`)
- General · Billing · Team · API Keys · Integrations · Attribution.
- No Maturity entry.

### Data
- `score_assessments` table has `user_id` (nullable), `claim_token`, `overall_score`, `overall_level`, `dimension_scores` JSONB, etc. **No `account_id` column today.**
- `User#score_assessments` (`has_many ... dependent: :nullify`).
- `current_user.score_assessments.order(created_at: :desc).first` is what `Score::DashboardController` uses today.
- `ScoreAssessment#overall_level` (1–4) and `#level_name` give display values.
- Score dashboard requires login; the route is `score_dashboard_path`.

### Anonymous → claim → signup flow (for context — assessment lifecycle today)

```
POST /measurement-maturity-assessment/assessments  → ScoreAssessment created, claim_token generated, no user_id, no account_id
GET  /measurement-maturity-assessment/r/:code      → results page
POST /measurement-maturity-assessment/claim        → email captured (still no user)
POST /measurement-maturity-assessment/join         → SignupService creates User, sets assessment.user_id via claim_token
[mbuzz signup separately]                          → Account + Membership created, but assessment.account_id never set (column doesn't exist)
```

The disconnect this spec is fixing extends beyond UI: the assessment never gets stitched to the account.

---

## Proposed Solution

### Direction A — Assessment → mbuzz (permanent CTA)

A CTA block placed **directly under the insight paragraph in the report header**, above the tab bar. Visible regardless of which tab the user is on (Overview, Dimensions, Roadmap, Business Case), not buried inside Business Case.

Structure: short body copy on the left/top, a tight button label on the right/bottom. The body copy carries the message; the button is just the door.

| State | Body copy | Button label | Button target |
|-------|-----------|--------------|---------------|
| Signed-out | "Start measuring properly with mbuzz. Stop grading the homework of the channels you're paying." | `Go to mbuzz →` | `score_signup_path` |
| Signed-in, no account | "Finish setup so the numbers above stop being self-graded by your platforms." | `Go to mbuzz →` | `signup_path` |
| Signed-in, has account | "Pick up where you left off. Your account is wired and waiting." | `Go to mbuzz →` | `dashboard_path` |

Body copy is first-draft (still an open question). Button stays `Go to mbuzz →` across all states for consistency.

The existing "Retake Assessment" / "Share Assessment Link" buttons stay where they are at the bottom as quiet secondary actions.

### Direction B — mbuzz → Assessment (no nav clutter, account-scoped)

The score is now a property of the **current account**. Switching accounts switches the displayed score. Two touchpoints, neither adds chrome to the top bar:

1. **Account dropdown** (the menu currently showing TEST ▾ / Create Account / Account Settings). Two additions:
   - Inline level on each account row in the list — small `L1` / `L2` / `L3` / `L4` pill next to the role badge — so when a user has multiple accounts, they can see at-a-glance which orgs are at which maturity level.
   - A new entry below "Account Settings": `Measurement Maturity` with the current account's level shown inline (e.g., `Measurement Maturity · Level 1`) → `score_dashboard_path`. If the current account has no assessment, the entry reads `Take Measurement Assessment` → `score_path`.

2. **Account Settings sidebar** (`_account_nav.html.erb`) — add a `Maturity` entry, after `Attribution`. Links to `score_dashboard_path` when the current account has an assessment, else `score_path`. Durable deep-link home for users who go looking in settings.

The user dropdown (avatar) stays as it is. Maturity is account-level, not user-level.

### Data Flow (Proposed)

```
Anonymous quiz → /score/r/:code → claim → join (mbuzz signup)
                                            ↓
                                  User created + first Account + Membership
                                            ↓
                          [NEW: assessment.account_id = first account]
                                            ↓
                                       score_dashboard (loads via current_account)
                                            ↓
                          [NEW: CTA "Open your mbuzz dashboard →"]
                                            ↓
                                       /dashboard
                                            ↓
                  [NEW: account dropdown · "Measurement Maturity · Level 1"]
                  [NEW: settings sidebar · "Maturity"]
                                            ↓
                                       score_dashboard
```

### Multi-account behaviour

- Each account has its own assessment(s). `current_account.score_assessments.order(created_at: :desc).first` is the displayed score.
- A user who is a member of N accounts will see different levels in each — the account dropdown shows them inline.
- A newly-created account (e.g., via "Create Account") starts with no assessment. Sidebar/dropdown shows "Take Measurement Assessment" until one is taken.
- A user retaking the assessment after they're already in an account: the new assessment's `account_id` is set to `current_account` at create time. Latest wins on display.

---

## Key Files

| File | Purpose | Changes |
|------|---------|---------|
| `db/migrate/<ts>_add_account_id_to_score_assessments.rb` *(new)* | Schema | Add `account_id` (bigint, nullable, indexed, FK to accounts). Nullable so anonymous-stage rows still work. |
| `db/migrate/<ts>_backfill_score_assessment_account_ids.rb` *(new, data migration)* | Backfill | For each `ScoreAssessment` with `user_id` set, copy `account_id` from the user's earliest owned-or-only membership. Skip rows where the user has zero or ambiguous memberships (admin can fix manually). |
| `app/models/score_assessment.rb` | Model | `belongs_to :account, optional: true`. Add `validates :account_id, presence: true, on: :update` once backfill is complete (or guard with a state). Keep `belongs_to :user, optional: true`. |
| `app/models/concerns/account/relationships.rb` | Account relationships | `has_many :score_assessments, dependent: :nullify`. |
| `app/services/score/signup_service.rb` | Signup → assessment claim | After User + Account + Membership are created, set `assessment.account_id = account.id` and save. |
| `app/controllers/score/dashboard_controller.rb` | Score dashboard | Switch from `current_user.score_assessments...` to `current_account.score_assessments.order(created_at: :desc).first`. Multi-tenancy compliant. |
| `app/views/score/dashboard/show.html.erb` | Score report | Insert primary CTA block under `.report-header` insight paragraph, above `.report-tabs`. |
| `app/views/score/dashboard/no_assessment.html.erb` | Empty state | Verify it points to `score_path` for retake/take. |
| `app/helpers/score/dashboard_helper.rb` *(or existing)* | CTA logic | Add `score_to_app_cta` returning `{ href:, label:, subtext: }` based on user/account state. |
| `app/views/layouts/_nav.html.erb` | Top nav — account dropdown | (a) Inline `L<N>` pill on each account list row. (b) New "Measurement Maturity · Level N" entry below "Account Settings". |
| `app/views/layouts/_account_nav.html.erb` | Settings sidebar | Add `Maturity` entry after `Attribution`. |
| `app/helpers/application_helper.rb` | Helpers | `current_account_latest_assessment` memoized per request. `account_maturity_level(account)` for inline pills. |
| `app/assets/stylesheets/score/dashboard.css` (or equivalent) | New CTA styles | Full-width primary button consistent with brand. |

---

## All States

| State | Condition | Expected Behavior |
|-------|-----------|-------------------|
| Anonymous on results page | No `current_user`, only `claim_token` | Existing claim flow. Out of scope for this spec. |
| Signed-in, no account yet | `current_user.active_memberships.empty?` | Score dashboard CTA → `signup_path` (mbuzz account creation). Account dropdown N/A — user isn't past signup. |
| Signed-in, account has assessment | `current_account.score_assessments.any?` | Score dashboard CTA → `dashboard_path` ("Open your mbuzz dashboard →"). Account dropdown row shows `L<N>` pill, dropdown shows `Measurement Maturity · Level <N>`. Settings sidebar shows `Maturity`. |
| Signed-in, account has no assessment | `current_account.score_assessments.empty?` | Account dropdown shows `Take Measurement Assessment` → `score_path`. Per-account row shows no pill (or a faint dash). Settings sidebar `Maturity` → `score_path`. |
| User in multiple accounts, mixed coverage | Some accounts assessed, some not | Each row pill reflects its own account. Switching accounts changes the dropdown's main "Measurement Maturity" entry. |
| Account has multiple assessments | `account.score_assessments.count > 1` | Show latest by `created_at desc`. Older ones retained (history). |
| Backfill ambiguity | User has multiple account memberships at backfill time | Skip. No tiebreaker. Logged to a count-only summary. Row stays user-only and is invisible to any account dashboard. |

---

## Implementation Tasks

### Phase 1 — Re-scope assessment to account (data model)
- [ ] **1.1** Migration: add `account_id` (nullable bigint, FK, indexed) to `score_assessments`.
- [ ] **1.2** `ScoreAssessment`: `belongs_to :account, optional: true`.
- [ ] **1.3** `Account` (or `Account::Relationships` concern): `has_many :score_assessments, dependent: :nullify`.
- [ ] **1.4** Update `Score::SignupService` so that on first account creation post-claim, the assessment is associated with the new account.
- [ ] **1.5** Tests: model association, signup flow attaches assessment to account, multi-tenancy isolation (account A cannot see account B's assessment).

### Phase 2 — Backfill
- [ ] **2.1** Data migration: for each `ScoreAssessment` with `user_id` and `account_id IS NULL`, set `account_id` only when the user has **exactly one** active account membership. Multi-membership users are skipped, no fallback. (No Owner-role tiebreaker — keep it dumb and safe.)
- [ ] **2.2** Print a summary at the end (assigned count, skipped count). Skipped rows are acceptable — they remain user-only and won't show in any account's dashboard.
- [ ] **2.3** Run on staging first, verify counts, then prod.

### Phase 3 — Score dashboard reads from account
- [ ] **3.1** `Score::DashboardController` switches to `current_account.score_assessments.order(created_at: :desc).first`. Handle `current_account.nil?` → redirect to mbuzz signup.
- [ ] **3.2** Tests: account isolation; user in two accounts sees different scores when switching `current_account`.

### Phase 4 — Helper + reusable lookup
- [ ] **4.1** `current_account_latest_assessment` helper (memoized per request, nil-safe for signed-out / no-account users).
- [ ] **4.2** `account_maturity_level(account)` for inline rendering on the account dropdown rows.
- [ ] **4.3** Helper tests.

### Phase 5 — Assessment → mbuzz CTA
- [ ] **5.1** Add CTA partial `app/views/score/dashboard/_to_app_cta.html.erb` — uses helper to determine href and copy based on user/account state.
- [ ] **5.2** Render partial in `show.html.erb` between `.report-header` and `.report-tabs`.
- [ ] **5.3** Full-width primary button, visually elevated vs the secondary `.report-cta-btn`. No em-dashes.
- [ ] **5.4** System tests: CTA visible on every tab; href varies by user state.

### Phase 6 — Account dropdown (mbuzz → Assessment)
- [ ] **6.1** In `_nav.html.erb` account dropdown row, add a small `L<N>` pill next to the role badge (faint dash if no assessment).
- [ ] **6.2** Add a new entry below "Account Settings": `Measurement Maturity · Level <N>` → `score_dashboard_path`. Falls back to `Take Measurement Assessment` → `score_path` when absent.
- [ ] **6.3** System tests: dropdown shows correct level for current account; switching account updates pill and entry.

### Phase 7 — Settings sidebar
- [ ] **7.1** In `_account_nav.html.erb`, add `Maturity` entry after `Attribution`. Icon: a small radar/target SVG.
- [ ] **7.2** Active state when on `score_dashboard_path` (note: score uses `layouts/score.html.erb` so sidebar won't render there; the active state matters only when we eventually move score under the account layout — out of scope).
- [ ] **7.3** System tests.

### Phase 8 — QA + polish
- [ ] **8.1** Manual QA of all states in the All States table.
- [ ] **8.2** No regression on score dashboard tab switching, claim flow, signup flow.
- [ ] **8.3** Verify multi-account user sees distinct scores per account.
- [ ] **8.4** Update spec status to Complete, move to `old/`.

---

## Testing Strategy

### Model / Service Tests

| Test | File | Verifies |
|------|------|----------|
| `ScoreAssessment belongs_to :account` | `test/models/score_assessment_test.rb` | Association works, optional |
| `Account#score_assessments` returns only its own | `test/models/account_test.rb` | Multi-tenancy: account A scope excludes account B's rows |
| `Score::SignupService` attaches assessment to new account | `test/services/score/signup_service_test.rb` | After signup, `assessment.account_id == account.id` |
| Backfill assigns when unambiguous, skips when not | `test/migrations/...` or `test/lib/...` | One-membership users get assigned; multi-membership users skipped |

### System Tests

| Test | File | Verifies |
|------|------|----------|
| Score dashboard renders to-app CTA above tabs | `test/system/score/dashboard_test.rb` | CTA present regardless of active tab |
| To-app CTA href reflects user state | `test/system/score/dashboard_test.rb` | Has-account → `dashboard_path`; no-account → `signup_path` |
| Score dashboard reads from current_account | `test/system/score/dashboard_test.rb` | User switches accounts → score updates accordingly |
| Account dropdown shows L<N> pill per row | `test/system/dashboard_nav_test.rb` | User with two accounts at different levels sees both pills |
| Account dropdown shows "Measurement Maturity · Level N" entry | `test/system/dashboard_nav_test.rb` | Reflects current account's level |
| Account dropdown shows "Take Measurement Assessment" when absent | `test/system/dashboard_nav_test.rb` | New account, no assessment yet |
| Settings sidebar exposes Maturity entry | `test/system/account/settings_nav_test.rb` | Link present and routes correctly |

### Helper Tests

| Test | File | Verifies |
|------|------|----------|
| `current_account_latest_assessment` returns nil when no current_account | `test/helpers/application_helper_test.rb` | Nil-safe |
| Returns latest by created_at | `test/helpers/application_helper_test.rb` | Most-recent wins |
| `account_maturity_level(account)` returns Integer or nil | `test/helpers/application_helper_test.rb` | Used by inline pill rendering |

### Manual QA

1. Sign up via the assessment claim flow → land on `/measurement-maturity-assessment/dashboard`. Confirm CTA visible under the insight, on every tab.
2. Click "Open your mbuzz dashboard →" → land on `/dashboard`.
3. Open the user (avatar) dropdown → confirm `Maturity · Level <N>` is shown. Click it → land back on score dashboard.
4. Open Account Settings → confirm `Maturity` in sidebar. Click it → score dashboard.
5. As a user with no assessment, confirm dropdown and sidebar show the "Take" prompts and route to `score_path`.

---

## Definition of Done

- [ ] All tasks completed.
- [ ] Tests pass (system + helper).
- [ ] Manual QA on dev — all four user states.
- [ ] No regression on score dashboard tab toggling.
- [ ] No nav chrome added to top bar (account dropdown unchanged in shape).
- [ ] No em-dashes in any new user-facing copy.
- [ ] Spec moved to `lib/specs/old/`.

---

## Out of Scope

- Showing the score level **persistently in the top nav** (explicit user direction: don't busy the nav).
- Re-running or re-prompting the assessment from inside the product (separate concern).
- Email nudges from score dashboard to mbuzz (separate growth spec).
- Showing maturity level inside the homepage / public surfaces.
- **Per-member assessment averaging within an account.** Today an account's score is the latest single assessment. Aggregating across all members of an account is a future question — the existing `ScoreTeam` concept (separate from accounts) already does cross-member alignment for non-account use cases and stays orthogonal.
- Migrating `score_team_memberships` to be account-scoped. Score teams remain a separate, user-scoped concept.

---

## Open Questions

1. **Body copy** above the CTA button — drafts in the table above. Three variants (signed-out / signed-in-no-account / signed-in-with-account) are first-draft and need a polish pass before ship.

## Decisions

- Button label: `Go to mbuzz →` (single label across all states).
- Retake from inside the product: new assessment gets `account_id = current_account.id` at create time. Latest wins on display; older assessments retained as history.
- Backfill rule: assign `account_id` only when user has exactly one active membership. No tiebreaker. Skipped rows stay user-only and invisible to any account dashboard.
- Score layout (`layouts/score.html.erb`) is unchanged — no product top nav inside the score dashboard.
