# Error Email Flood — Solid Errors Investigation

**Date:** 2026-05-13
**Status:** Resolved (dedup + visitor-format fix shipped; deploy-artifact errors accepted)
**Severity:** Low (noise only — no user-facing impact)

---

## What Happened

`hello@mbuzz.co` was emailing `vlad@mbuzz.co` once per occurrence for every captured exception, with no dedup window. Four screenshots arrived in one afternoon for three distinct errors:

| # | Exception | First seen | Cause | Class |
|---|-----------|------------|-------|-------|
| 1 | `ActiveRecord::RecordInvalid` ("Visitor must contain only letters, numbers, underscores, hyphens, dots, and colons") | 27 days ago | Client posts bad `visitor_id` to `POST /api/v1/sessions` | Application bug |
| 2 | `ActiveRecord::StatementInvalid` ("could not open relation with OID 17300") | 1 minute ago (May 12) | Stale relation OID in long-lived Puma DB connection after a deploy migration | Post-deploy artifact |
| 3 | `ActiveRecord::PreparedStatementCacheExpired` ("cached plan must not change result type") | 3 months ago | Cached prepared statement against schema that changed under it | Post-deploy artifact |

Errors #2 and #3 line up with the May 10 migrations: `add_match_keys_to_sessions`, `add_hashed_pii_to_identities`, `create_conversion_destinations`, `create_conversion_dispatches`.

---

## Root Causes

### 1. Visitor format `RecordInvalid` (recurring 27 days)

Validation on `Visitor.visitor_id`:

```ruby
# app/models/concerns/visitor/validations.rb
validates :visitor_id,
  presence: true,
  uniqueness: { scope: :account_id },
  length: { maximum: 255 },
  format: {
    with: /\A[a-zA-Z0-9._:\-]{1,}\z/,
    message: "must contain only letters, numbers, underscores, hyphens, dots, and colons"
  }
```

`Sessions::CreationService#find_or_create_by_visitor_id` calls the bang variant:

```ruby
# app/services/sessions/creation_service.rb:171
account.visitors.find_or_create_by!(visitor_id: visitor_id) do |v|
  ...
end
```

When a client posts a `visitor_id` containing characters outside `[a-zA-Z0-9._:\-]` (UUIDs with braces, spaces, base64 with `+/=`, unicode, etc.), `find_or_create_by!` raises `ActiveRecord::RecordInvalid`. `Api::V1::BaseController#handle_unexpected_error` rescues every `StandardError`, reports to `Rails.error`, returns 500.

Wrong on two counts:
- Client gets 500 (no signal that their payload is malformed); should be 422 with the validation message.
- Each failed request emails Vlad.

### 2. `StatementInvalid` — could not open relation with OID 17300

PostgreSQL emits this when a relation referenced by a session has been dropped/recreated underneath it. Common after migrations that drop and re-add tables, or that interact with materialized views. Self-healing — clears once the affected Puma connection cycles. First seen May 12, 1 minute before the email arrived — matches the deploy window.

### 3. `PreparedStatementCacheExpired` — cached plan must not change result type

Postgres rejects an execution of a prepared statement when the underlying schema (column types, return columns) has changed since the plan was cached. Rails 5.2+ auto-retries the statement once on this error, which usually recovers transparently — but Solid Errors still records the first miss before the retry succeeds. First seen 3 months ago = recurring on every deploy with DDL.

---

## Mitigation Shipped

### Email dedup (24h window per error fingerprint)

`config/initializers/solid_errors.rb` overrides `SolidErrors::Occurrence#send_email` to suppress the email if another occurrence of the same `error_id` was created in the last 24 hours.

```ruby
Rails.application.config.to_prepare do
  SolidErrors::Occurrence.class_eval <<~RUBY, __FILE__, __LINE__ + 1
    EMAIL_DEDUP_WINDOW = 24.hours unless const_defined?(:EMAIL_DEDUP_WINDOW)

    private

    def send_email
      return if duplicate_within_window?

      SolidErrors::ErrorMailer.error_occurred(self).deliver_later
    end

    def duplicate_within_window?
      self.class
        .where(error_id: error_id)
        .where.not(id: id)
        .where(created_at: EMAIL_DEDUP_WINDOW.ago..)
        .exists?
    end
  RUBY
end
```

Notes:
- Per-error-fingerprint, not global — a brand-new exception type still mails on first hit.
- All occurrences are still recorded in `solid_errors_occurrences`; only the email is suppressed.
- Patch uses string `class_eval` so constants resolve correctly to `SolidErrors::Occurrence::EMAIL_DEDUP_WINDOW` (block form leaks them to top-level — found and fixed during implementation).
- The mailer reference is fully qualified (`SolidErrors::ErrorMailer`) because string `class_eval` does not inherit the enclosing module's lexical scope.

Verified locally: two occurrences of the same error created back-to-back → only the first mailed.

### Visitor format 422 fix at the service boundary

`Sessions::CreationService#validation_error` now rejects malformed `visitor_id`s before reaching `find_or_create_by!`. Clients get a 422 with the same human-readable message the model would have raised, and `RecordInvalid` no longer leaks out of the service.

```ruby
# app/services/sessions/creation_service.rb
def validation_error
  return error_result([ "visitor_id is required" ]) unless visitor_id.present?
  return error_result([ "visitor_id #{Visitor::Validations::ID_FORMAT_MESSAGE}" ]) unless valid_visitor_id_format?
  return error_result([ "session_id is required" ]) unless session_id.present?
  error_result([ "url is required" ]) unless url.present?
end

def valid_visitor_id_format?
  visitor_id.to_s.match?(Visitor::Validations::ID_FORMAT)
end
```

The regex and message are extracted to constants on the `Visitor::Validations` concern so the rule lives in one place:

```ruby
# app/models/concerns/visitor/validations.rb
ID_FORMAT = /\A[a-zA-Z0-9._:\-]{1,}\z/
ID_FORMAT_MESSAGE = "must contain only letters, numbers, underscores, hyphens, dots, and colons"
```

Verified locally against `bad{visitor}`, `has space`, `with+plus/equals=`, `🐱emoji`, empty, whitespace-only, and a valid `v_abc-123:xyz.456` — all return the expected service result without raising.

---

## Deferred

### Puma restart on deploy

Errors #2 and #3 are post-deploy artifacts. The clean fix is a Kamal post-migrate Puma restart hook, but dedup makes them invisible day-to-day. Only worth doing if these errors start firing outside deploy windows.

---

## Files Touched

- `config/initializers/solid_errors.rb` — new — email dedup patch.
- `app/services/sessions/creation_service.rb` — format check before `find_or_create_by!`.
- `app/models/concerns/visitor/validations.rb` — extracted regex + message to constants.
