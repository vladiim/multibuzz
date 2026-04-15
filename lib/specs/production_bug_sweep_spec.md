# Production Bug Sweep

**Date:** 2026-04-16
**Priority:** P1
**Status:** Draft
**Branch:** `fix/production-bug-sweep`

---

## Summary

Production Solid Errors reveals 29 errors across 6 categories. After filtering infrastructure noise (DB connection blips, transient migrations), 7 distinct bugs remain — ranging from a missing constant that crashes bot detection to a race condition in conversion idempotency. This spec documents each bug, its root cause, and the fix.

---

## Bug 1: `uninitialized constant BotPatterns` (Error #5, x4)

### Root Cause

`Sessions::BotClassifier` and `Sessions::CreationService` reference `BotPatterns::Matcher.bot?(user_agent)`, but the `BotPatterns` module lives on the `feature/session-bot-detection` branch — it hasn't been deployed to production yet. The initializer at `config/initializers/bot_patterns.rb` enqueues `BotPatterns::SyncJob` on boot, which fails immediately.

### Impact

Bot detection is fully broken in production. All bot traffic is being accepted as legitimate sessions.

### Fix

Deploy the bot detection branch. This is a deployment gap, not a code bug. Ensure the branch is merged and deployed.

### Key Files

| File | Line | Role |
|------|------|------|
| `app/services/sessions/bot_classifier.rb` | 36 | Calls `BotPatterns::Matcher.bot?` |
| `app/services/sessions/creation_service.rb` | 275 | Calls `BotPatterns::Matcher.bot?` |
| `config/initializers/bot_patterns.rb` | 16 | Enqueues `BotPatterns::SyncJob` on boot |
| `app/services/bot_patterns/matcher.rb` | — | Core matching module (on branch) |

---

## Bug 2: Visitor validation rejects valid visitor IDs (Error #10, x25)

### Root Cause

`Visitor::Validations` enforces `/\A[a-z0-9_-]{3,}\z/i` on `visitor_id`. This rejects:
- IDs shorter than 3 characters
- IDs containing dots, colons, or other characters common in third-party tracking systems (e.g., GA4 client IDs, Segment anonymous IDs)

SDKs generate 64-char hex strings that always pass, but the API accepts arbitrary `visitor_id` values from clients. Third-party integrations and Shopify webhooks may send IDs that fail this regex.

### Impact

25 legitimate sessions/events rejected. Visitors silently lost.

### Fix

Relax the validation:
- Lower minimum length to 1 character
- Allow dots and colons in addition to alphanumeric, underscores, hyphens
- New regex: `/\A[a-zA-Z0-9._:-]{1,255}\z/`

### Key Files

| File | Line | Role |
|------|------|------|
| `app/models/concerns/visitor/validations.rb` | 7-13 | Format validation |
| `app/services/sessions/creation_service.rb` | 171 | `find_or_create_by!` — raises on validation failure |
| `test/models/visitor_test.rb` | 47-75 | Validation tests |

### Acceptance Criteria

- [ ] Visitor IDs with dots, colons, and single characters pass validation
- [ ] Maximum length enforced (255 chars)
- [ ] Empty/blank visitor IDs still rejected
- [ ] Existing tests updated to reflect relaxed rules

---

## Bug 3: Conversion idempotency race condition (Errors #26, #28, x2)

### Root Cause

`Conversions::TrackingService#conversion` does a read-then-write:

```
1. existing_idempotent_conversion → SELECT ... WHERE idempotency_key = ?
2. create_conversion              → INSERT ... (create!)
```

Two concurrent requests with the same idempotency key both pass step 1 (neither committed yet), then both attempt step 2. The second hits `PG::UniqueViolation` on `index_conversions_on_account_idempotency_key`, and `create!` raises unrescued.

### Impact

Duplicate conversion requests return 500 instead of being gracefully deduplicated.

### Fix

Rescue `ActiveRecord::RecordNotUnique` in `create_conversion` and retry the lookup:

```ruby
def create_conversion
  Conversion.create!( ... )
rescue ActiveRecord::RecordNotUnique
  @duplicate = true
  account.conversions.find_by!(idempotency_key: idempotency_key)
end
```

### Key Files

| File | Line | Role |
|------|------|------|
| `app/services/conversions/tracking_service.rb` | 111-147 | Race-prone read-then-write |
| `test/services/conversions/tracking_service_test.rb` | 585-641 | Missing concurrent test |

### Acceptance Criteria

- [ ] Duplicate idempotency key returns the existing conversion (no error)
- [ ] `duplicate?` returns true for the race-condition path
- [ ] No `RecordNotUnique` exceptions reach Solid Errors

---

## Bug 4: Docs layout links to non-existent pages (Errors #1, #3, #4, #14-17, #20-22, x194)

### Root Cause

The docs layout (`app/views/layouts/docs.html.erb`, lines 20-21) renders navigation links to:
- `/docs/api-reference`
- `/docs/examples`

Neither page exists:
- Not in `DocsController::ALLOWED_PAGES`
- No partials `_api_reference.html.erb` or `_examples.html.erb`

The `_authentication.html.erb` template also links to both (lines 292, 296-297).

`DocsController` now has an `ALLOWED_PAGES` guard that renders 404, so these errors are likely from before that guard was added, or from crawlers that cached the old URLs. The nav links still render and point to dead pages.

### Impact

Broken navigation. Users clicking "API Reference" or "Examples" get 404. Crawlers generate error noise.

### Fix

Remove the nav links from the docs layout until those pages are built. Remove the references from `_authentication.html.erb`.

### Key Files

| File | Line | Role |
|------|------|------|
| `app/views/layouts/docs.html.erb` | 20-21 | Nav links to missing pages |
| `app/views/docs/_authentication.html.erb` | 292, 296-297 | Inline links to missing pages |
| `app/controllers/docs_controller.rb` | 6 | `ALLOWED_PAGES` guard |

### Acceptance Criteria

- [ ] No nav links to pages that don't exist
- [ ] Authentication page doesn't link to non-existent pages
- [ ] No more `MissingTemplate` errors in Solid Errors

---

## Bug 5: ERB heredoc syntax errors in docs templates (Errors #7, #11, #12, #13, x28)

### Root Cause

Multiple docs partials use `<%= render_markdown <<~MD ... MD %>` heredoc syntax. These errors have high occurrence counts suggesting they were persistent during a period but may now be resolved (the `_dsl_editor.html.erb` heredoc is currently valid).

Need to verify each template renders cleanly in production.

### Impact

Docs pages return 500 when the broken templates are hit.

### Fix

Verify each template renders. If any still fail, fix the heredoc syntax (ensure `MD` terminator is at the start of its line, ERB tags are properly closed).

### Key Files

| File | Role |
|------|------|
| `app/views/docs/_getting_started.html.erb` | 16 heredoc blocks |
| `app/views/docs/_authentication.html.erb` | 4 heredoc blocks |
| `app/views/docs/_attribution_models.html.erb` | 21 heredoc blocks |
| `app/views/docs/_platforms_shopify.html.erb` | 1 heredoc block |
| `app/views/articles/embeds/_dsl_editor.html.erb` | 1 heredoc block (currently valid) |

### Acceptance Criteria

- [ ] All docs pages render without ERB syntax errors
- [ ] Manual smoke test of each docs page

---

## Bug 6: `sessions.prefix_id` column query (Error #23, x1)

### Root Cause

Code somewhere queries `sessions.prefix_id` as a database column, but `prefix_id` is a virtual attribute provided by the `prefixed_ids` gem (`has_prefix_id :sess` in `Session` model). It's computed in-memory from `id`, not stored in the database.

Likely culprit: a `.select(:prefix_id)`, `.pluck(:prefix_id)`, or `.where(prefix_id: ...)` call.

### Impact

One-off error. Low frequency but indicates a code path that treats `prefix_id` as a column.

### Fix

Find the query using `prefix_id` as a column and replace with in-memory lookup (load records first, then call `.prefix_id`).

### Acceptance Criteria

- [ ] No SQL queries reference `sessions.prefix_id` as a column
- [ ] Affected code path uses `.prefix_id` method on loaded records

---

## Bug 7: `sessions.request_id` column missing (Error #24, x1)

### Root Cause

Migration `20260313045737_add_request_id_to_sessions_and_events.rb` exists and `db/schema.rb` includes `request_id`. The error suggests this migration wasn't applied to production at the time of the error.

### Impact

One-off — likely resolved once migration was applied. Verify in production.

### Fix

Verify `request_id` column exists in production sessions table. If not, run the migration.

### Acceptance Criteria

- [ ] `request_id` column exists in production sessions table
- [ ] No more `UndefinedColumn` errors for `request_id`

---

## Noise Errors (Resolve in Bulk)

These are transient infrastructure issues, not code bugs:

| Error IDs | Count | Issue | Action |
|-----------|-------|-------|--------|
| #9, #18, #25, #27, #29 | x50 | DB connection errors to managed DB (10.120.0.3) | Resolve — transient network |
| #6 | x4 | `PreparedStatementCacheExpired` | Resolve — post-migration transient |

### Cleanup Command

```ruby
# Resolve transient infrastructure errors
SolidErrors::Error.where(id: [6, 9, 18, 25, 27, 29]).update_all(resolved_at: Time.current)

# Resolve all errors that have already been fixed (old heredoc, old migration)
SolidErrors::Error.where(id: [7, 8, 11, 12, 13, 23, 24]).update_all(resolved_at: Time.current)
```

---

## Implementation Tasks

### Phase 1: Critical Fixes

- [ ] **1.1** Merge bot detection branch (Bug 1) — resolves `BotPatterns` constant error
- [ ] **1.2** Relax visitor_id validation (Bug 2) — update regex, update tests
- [ ] **1.3** Rescue `RecordNotUnique` in conversion tracking (Bug 3) — add rescue + retry

### Phase 2: Docs Cleanup

- [ ] **2.1** Remove dead nav links from docs layout (Bug 4)
- [ ] **2.2** Remove dead links from `_authentication.html.erb` (Bug 4)
- [ ] **2.3** Smoke test all docs pages for heredoc errors (Bug 5)

### Phase 3: Verify & Clean

- [ ] **3.1** Verify `request_id` column exists in production (Bug 7)
- [ ] **3.2** Find and fix `prefix_id` column query (Bug 6)
- [ ] **3.3** Resolve noise errors in Solid Errors (cleanup command above)

---

## Testing Strategy

### Unit Tests

| Test | File | Verifies |
|------|------|----------|
| Visitor accepts dots/colons | `test/models/visitor_test.rb` | Relaxed validation |
| Conversion idempotency race | `test/services/conversions/tracking_service_test.rb` | `RecordNotUnique` rescue |

### Manual QA

1. Visit all docs pages — no 500 errors
2. Submit conversion with duplicate idempotency key — returns existing, no error
3. Create visitor with short/dotted ID via API — succeeds
4. Boot app — no `BotPatterns` constant error in logs

---

## Definition of Done

- [ ] All phase 1-3 tasks completed
- [ ] Tests pass (unit + integration)
- [ ] Manual QA on staging
- [ ] No regressions
- [ ] Noise errors resolved in production Solid Errors
- [ ] Spec moved to `old/`
