# Error Tracking & Log Archival Specification

**Date:** 2026-02-18
**Priority:** P1
**Status:** Draft
**Branch:** `feature/error-tracking`

---

## Summary

Production has zero error visibility. `ApplicationService` catches every `StandardError` and swallows it — no log line, no backtrace, no record. Background jobs complete "successfully" even when they fail. The only structured error tracking is `ApiRequestLog`, which covers API-layer failures (auth, validation, rate limits) but nothing below the controller.

When the attribution job silently failed for 40% of conversions (journey stitching spec, Pattern B), there was no way to know. The fix is two things: [Solid Errors](https://github.com/fractaledmind/solid_errors) for database-backed error tracking (same author as the rest of the Solid Stack), and daily log archival to DigitalOcean Spaces.

---

## Current State

### What Works

`ApiRequestLog` handles API-layer errors well — 21 enumerated error types, JSONB details, SDK version extraction, IP anonymization, indexed by account+time. Controllers call `log_request_failure()` explicitly for known failure paths (auth, validation, billing).

### What's Blind

| Layer | What Happens on Error | Visibility |
|-------|----------------------|------------|
| `ApplicationService` | Catches `StandardError`, returns `{ success: false }` | Zero — no log, no backtrace |
| `ApplicationJob` | No retry/discard policies, no error hooks | Zero — job "succeeds" |
| Unhandled controller exceptions | Rails default 500 | STDOUT only, ephemeral |
| Data integrity checks | Records to `DataIntegrityCheck` table | Good, but no alerting |

### Evidence

- `ApplicationService` (lines 2-10): catches `StandardError`, returns error hash, never calls `Rails.logger`
- `ApplicationJob` (lines 1-7): retry/discard both commented out, no `rescue_from`
- `production.rb` (line 38): logs to STDOUT only — lost when containers restart
- `config/deploy.yml`: no log volume, no log driver config

---

## Proposed Solution

### Phase 1: Solid Errors + Rails Error Reporter Integration

Use the `solid_errors` gem for database-backed error storage, dashboard UI, and auto-cleanup. Wire it into the app via Rails' built-in `Rails.error` reporter API — the standard interface since Rails 7.1. This gives us structured error tracking with zero custom models.

```
Service/Job/Controller raises exception
  → Rails.error.report(e, context: { ... })
  → Solid Errors subscriber captures it → stored in solid_errors DB table
  → Original behavior preserved (error_result returned / job retried)
```

Three integration points:
1. `ApplicationService#call` — report errors before returning `error_result`
2. `ApplicationJob` — retry policy + report on failure
3. `Api::V1::BaseController` — `rescue_from StandardError` for unhandled 500s

### Phase 2: DigitalOcean Spaces Log Archival

Daily compression of Rails logs, uploaded to DigitalOcean Spaces via `aws-sdk-s3` (Spaces is S3-compatible). Kamal volume mount for log persistence between deploys. Recurring Solid Queue job at 4am.

```
Rails logger → STDOUT (kamal logs) + log file (mounted volume)
  → Daily at 4am: compress yesterday's log → upload to DO Spaces → delete local
  → Spaces lifecycle policy: expire after 365 days
```

### Key Files

| File | Purpose | Changes |
|------|---------|---------|
| `Gemfile` | Dependencies | Add `solid_errors`, `aws-sdk-s3` |
| `config/database.yml` | Solid Errors DB | Add `errors` database entry |
| `app/services/application_service.rb` | Base service rescue | Add `Rails.error.report` |
| `app/jobs/application_job.rb` | Base job error handling | Add retry policy, error reporting |
| `app/controllers/api/v1/base_controller.rb` | Unhandled API exceptions | Add `rescue_from StandardError` |
| `config/environments/production.rb` | Logger + Solid Errors | Add file logger, Solid Errors config |
| `app/services/logs/archive_service.rb` | Compress + upload to Spaces | New service |
| `app/jobs/logs/archive_job.rb` | Daily archive trigger | New job |
| `config/recurring.yml` | Schedule archival | Add entry |
| `config/deploy.yml` | Log volume mount | Add volume |

---

## All States

| State | Condition | Expected Behavior |
|-------|-----------|-------------------|
| Service raises `StandardError` | `ApplicationService#call` rescue | Error reported via `Rails.error.report`, `error_result` returned (no behavior change) |
| Service raises `RecordInvalid` | `ApplicationService#call` rescue | Error reported with validation context, `error_result` returned |
| Job raises exception | `ApplicationJob` retry | Error reported, job retries (3 attempts, polynomial backoff) |
| Job exhausts retries | 3 failures | Error reported with `attempts_exhausted: true`, job discarded |
| Unhandled controller exception | `rescue_from StandardError` in `BaseController` | Error reported with request context, 500 JSON response |
| Solid Errors DB unavailable | Connection failure | Falls back to `Rails.logger.error` — Rails error reporter never raises |
| Spaces upload fails | Network/auth error | Error reported via `Rails.error.report`, retried next day, local file preserved |
| No log file for yesterday | Server just started, no prior day | Job completes silently, no error |

---

## Implementation Tasks

### Phase 1: Solid Errors + Integration

- [ ] **1.1** Add `gem "solid_errors"` to Gemfile, run `bin/rails solid_errors:install`, configure `errors` database in `config/database.yml` (same PostgreSQL server, separate database like Solid Queue/Cache)
- [ ] **1.2** Mount Solid Errors dashboard in `config/routes.rb` — behind authentication (admin-only)
- [ ] **1.3** Configure Solid Errors in `config/environments/production.rb` — set `config.solid_errors.connects_to = { database: { writing: :errors } }`
- [ ] **1.4** Update `ApplicationService#call` — add `Rails.error.report(e, context: { service: self.class.name })` in each rescue block before returning `error_result`. Include `account_id` when `@account` responds to `id`
- [ ] **1.5** Update `ApplicationJob` — add `retry_on StandardError, wait: :polynomially_longer, attempts: 3`. Add `after_discard` callback that reports via `Rails.error.report`. Add `discard_on ActiveJob::DeserializationError`
- [ ] **1.6** Update `Api::V1::BaseController` — add `rescue_from StandardError` that reports via `Rails.error.report` (with request context: path, method, account_id, request_id) and renders `{ error: "Internal server error" }` with 500 status
- [ ] **1.7** Test: service error reports to `Rails.error` with correct context
- [ ] **1.8** Test: job failure reports to `Rails.error` and retries
- [ ] **1.9** Test: unhandled controller exception reports to `Rails.error` and returns 500 JSON
- [ ] **1.10** Test: `ApplicationService` behavior unchanged — still returns `error_result` hash

### Phase 2: DigitalOcean Spaces Log Archival

- [ ] **2.1** Add `gem "aws-sdk-s3"` to Gemfile
- [ ] **2.2** Add Spaces credentials to Rails credentials (`do_spaces.access_key_id`, `do_spaces.secret_access_key`, `do_spaces.bucket`, `do_spaces.region`, `do_spaces.endpoint` e.g. `https://nyc3.digitaloceanspaces.com`)
- [ ] **2.3** Update `production.rb` — add file logger alongside STDOUT: `config.logger = ActiveSupport::BroadcastLogger.new(stdout_logger, file_logger)`. File writes to `/app/log/production.log`
- [ ] **2.4** Update `config/deploy.yml` — add volume mount: `- /var/log/mbuzz:/app/log`
- [ ] **2.5** Create `Logs::ArchiveService` — compresses yesterday's log (`gzip`), uploads to DO Spaces (`logs/YYYY/MM/DD.log.gz`), deletes local file. Not an `ApplicationService` (utility class, returns void). Configures `Aws::S3::Client` with `endpoint:` and `force_path_style: true` for DO compatibility
- [ ] **2.6** Create `Logs::ArchiveJob` — thin wrapper, runs daily at 4am
- [ ] **2.7** Add to `config/recurring.yml`: `log_archive` job
- [ ] **2.8** Set Spaces lifecycle policy: expire after 365 days (applied via DO console or `s3cmd`)
- [ ] **2.9** Test: `Logs::ArchiveService` compresses file and calls S3 put_object with correct key and endpoint
- [ ] **2.10** Test: missing log file for yesterday completes without error

---

## Testing Strategy

### Unit Tests

| Test | File | Verifies |
|------|------|----------|
| Service reports errors | `test/services/application_service_test.rb` | `StandardError` in service calls `Rails.error.report` with service class in context |
| Service returns error_result | Same | Behavior unchanged — still returns `{ success: false, errors: [...] }` |
| Job reports errors | `test/jobs/application_job_test.rb` | Failed job calls `Rails.error.report` with job metadata |
| Job retries | Same | Job retries up to 3 times on `StandardError` |
| Controller reports errors | `test/controllers/api/v1/base_controller_test.rb` | Unhandled exception returns 500 JSON + calls `Rails.error.report` |
| Archive compresses + uploads | `test/services/logs/archive_service_test.rb` | Gzip created, Spaces put_object called, local deleted |
| Archive handles missing file | Same | No error when yesterday's log doesn't exist |

### Manual QA

1. Deploy to production
2. Trigger a known error (e.g., send malformed API request that bypasses validation)
3. Visit Solid Errors dashboard — error should appear with backtrace and context
4. `kamal logs` still works (STDOUT not broken)
5. Next day: verify DO Spaces bucket has `logs/2026/MM/DD.log.gz`

---

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Solid Errors vs custom `ErrorLog` model | Solid Errors | Same author as Solid Queue/Cache/Cable. Database-backed, dashboard included, auto-cleanup, hooks into `Rails.error` API. No reason to rebuild what exists. |
| `Rails.error.report` vs custom service | Rails error reporter | Standard Rails 7.1+ API. Solid Errors subscribes automatically. Other subscribers (logging, future Slack alerts) can be added without changing call sites. |
| DigitalOcean Spaces vs AWS S3 | DO Spaces | Infrastructure already on DigitalOcean. Spaces is S3-compatible — same `aws-sdk-s3` gem, just a different endpoint. Keeps everything on one provider. |
| Direct `aws-sdk-s3` vs Active Storage for logs | Direct SDK | Active Storage creates DB records per blob, supports variants/attachments — overhead we don't need. Log archival is a fire-and-forget blob upload. |
| Separate `errors` database | Yes | Follows Solid Stack convention (Queue, Cache, Cable each have their own DB). Isolates error storage from application data. |

---

## Definition of Done

- [ ] Phase 1: Solid Errors installed, dashboard accessible, ApplicationService/Job/Controller wired up — all tested
- [ ] Phase 2: DO Spaces archival working, volume mounted, recurring job scheduled
- [ ] Existing `ApiRequestLog` behavior unchanged
- [ ] No silent failures remaining in `ApplicationService` or `ApplicationJob`
- [ ] Production verified: errors appearing in Solid Errors dashboard
- [ ] Spec updated and moved to `old/`

---

## Out of Scope

- **Real-time alerting** (Slack/email on error) — Solid Errors supports email notifications. Enable later if needed.
- **APM / performance monitoring** — use `rack-mini-profiler` in dev. Production perf debugging is a separate concern.
- **Distributed tracing** — `request_id` tag already exists. Cross-service tracing is overkill for a single-server deploy.
- **Log search/aggregation UI** — `ssh` + `zgrep` on Spaces-downloaded files. Not worth building until there's a real need.
- **Sentry/Bugsnag integration** — the whole point is to not pay for these.
