# Data Integrity Surveillance System

**Date:** 2026-02-09
**Priority:** P1
**Status:** Complete
**Branch:** `feature/e1s4-content`

---

## Summary

We've been blindsided by data quality issues multiple times (see incidents: `2026-01-15`, `2026-01-29`, `2026-02-09`). Each time, the issue was invisible until a client or manual audit surfaced it.

This spec adds automated data health checks per account, run on a schedule, surfaced on an admin dashboard with warning/critical severity. The goal: never be surprised by data rot again.

### Production Evidence (2026-02-09, Account 2)

These thresholds and checks are calibrated from real production data:
- **Ghost session rate**: 98.6% (all 48 hours sampled)
- **Attribution mismatch**: 88.3% of conversions (1,355/1,534 in 30 days)
- **Session inflation**: 1 visitor had 1,259 sessions over 42 days
- **Fingerprint instability**: Worst-case visitor had 434 distinct fingerprints + 348 nil-fingerprint sessions
- **Channel shift**: 956 conversions misattributed as referral/direct that should be paid_search/organic_search

If this surveillance system had existed, every one of these would have triggered **critical** alerts within the first 6-hour check window.

---

## Current State

- No automated data quality monitoring
- Issues discovered manually (client complaints, ad-hoc console queries)
- Admin dashboard only shows billing metrics (`Admin::BillingController`)
- Incident response is reactive — by the time we notice, weeks of bad data exist

---

## Proposed Solution

### Architecture

```
Solid Queue (scheduled)
  → DataIntegrity::SurveillanceJob (runs every hour per account)
    → DataIntegrity::CheckRunner.new(account).call
      → Runs each Check (service object)
      → Stores results in data_integrity_checks table
      → Marks account health status

Admin::DataIntegrityController
  → index: all accounts with health summary
  → show: single account detail with check history
```

### Health Checks

| Check | What It Measures | Warning | Critical |
|-------|-----------------|---------|----------|
| **Ghost Session Rate** | % of sessions with 0 events (24h) | > 20% | > 50% |
| **Session Inflation** | Sessions per unique device (7d) | > 2x | > 5x |
| **Visitor Inflation** | Visitors per unique device (7d) | > 1.5x | > 3x |
| **Self-Referral Rate** | % of "referral" sessions where referrer = page_host (7d) | > 15% | > 40% |
| **Attribution Mismatch** | % of conversions where conv_channel != landing_channel (7d) | > 25% | > 50% |
| **Sessions Per Converter** | Avg sessions for visitors with conversions (7d) | > 5 | > 15 |
| **Event Volume** | % change vs previous equivalent period (bi-directional) | > 30% drop OR > 200% spike | > 60% drop OR > 500% spike |
| **Fingerprint Instability** | % of visitors with 2+ distinct fingerprints in a single day (7d) | > 10% | > 25% |
| **Missing Fingerprint Rate** | % of sessions with nil device_fingerprint (24h) | > 5% | > 20% |
| **Extreme Session Visitors** | Visitors with > 50 sessions in 30 days | > 1% of visitors | > 5% of visitors |

### Health Status Per Account

Derived from the worst check result:

| Status | Condition | Display |
|--------|-----------|---------|
| `healthy` | All checks pass | Green |
| `warning` | Any check at warning level | Yellow |
| `critical` | Any check at critical level | Red |
| `unknown` | No checks run yet | Gray |

---

## Key Files

| File | Purpose |
|------|---------|
| `db/migrate/xxx_create_data_integrity_checks.rb` | Migration |
| `app/models/data_integrity_check.rb` | Check result model |
| `app/services/data_integrity/check_runner.rb` | Orchestrator — runs all checks for an account |
| `app/services/data_integrity/checks/base_check.rb` | Base class for checks |
| `app/services/data_integrity/checks/ghost_session_rate.rb` | Ghost session check |
| `app/services/data_integrity/checks/session_inflation.rb` | Session inflation check |
| `app/services/data_integrity/checks/visitor_inflation.rb` | Visitor inflation check |
| `app/services/data_integrity/checks/self_referral_rate.rb` | Self-referral check |
| `app/services/data_integrity/checks/attribution_mismatch.rb` | Conversion attribution check |
| `app/services/data_integrity/checks/sessions_per_converter.rb` | Session count per converter |
| `app/services/data_integrity/checks/event_volume.rb` | Volume anomaly detection |
| `app/services/data_integrity/checks/fingerprint_instability.rb` | Visitors with multiple fingerprints per day |
| `app/services/data_integrity/checks/missing_fingerprint_rate.rb` | Sessions without device fingerprint |
| `app/services/data_integrity/checks/extreme_session_visitors.rb` | Visitors with 50+ sessions in 30 days |
| `app/jobs/data_integrity/surveillance_job.rb` | Scheduled job (thin wrapper) |
| `app/jobs/data_integrity/surveillance_scheduler_job.rb` | Enqueues one SurveillanceJob per active account |
| `app/jobs/data_integrity/cleanup_job.rb` | Purges check results older than 30 days |
| `app/controllers/admin/data_integrity_controller.rb` | Admin dashboard (inherits `Admin::BaseController`) |
| `app/views/admin/data_integrity/index.html.erb` | Account list with health status |
| `app/views/admin/data_integrity/show.html.erb` | Account detail with check history |

---

## Data Model

### `data_integrity_checks` table

```ruby
create_table :data_integrity_checks do |t|
  t.references :account, null: false, foreign_key: true
  t.string :check_name, null: false        # e.g. "ghost_session_rate"
  t.string :status, null: false             # "healthy", "warning", "critical"
  t.float :value, null: false               # e.g. 98.6 (percent)
  t.float :warning_threshold, null: false   # e.g. 20.0
  t.float :critical_threshold, null: false  # e.g. 50.0
  t.jsonb :details, default: {}             # extra context (sample IDs, raw counts)
  t.timestamps
end

add_index :data_integrity_checks, [:account_id, :check_name, :created_at],
  name: "idx_integrity_checks_account_check_time"
```

Keep last 30 days of check history. Older rows purged by a periodic cleanup job.

---

## Service Design

### Base Check

```ruby
module DataIntegrity
  module Checks
    class BaseCheck
      WINDOW = 7.days

      def initialize(account)
        @account = account
      end

      def call
        {
          check_name: check_name,
          value: calculate_value,
          status: evaluate_status(calculate_value),
          warning_threshold: warning_threshold,
          critical_threshold: critical_threshold,
          details: details
        }
      end

      private

      attr_reader :account

      def evaluate_status(value)
        return :critical if critical?(value)
        return :warning if warning?(value)
        :healthy
      end

      # Subclasses implement these
      def check_name = raise(NotImplementedError)
      def calculate_value = raise(NotImplementedError)
      def warning_threshold = raise(NotImplementedError)
      def critical_threshold = raise(NotImplementedError)
      def warning?(value) = value >= warning_threshold
      def critical?(value) = value >= critical_threshold
      def details = {}
    end
  end
end
```

### Example: Ghost Session Rate

```ruby
module DataIntegrity
  module Checks
    class GhostSessionRate < BaseCheck
      WINDOW = 24.hours

      private

      def check_name = "ghost_session_rate"
      def warning_threshold = 20.0
      def critical_threshold = 50.0

      def calculate_value
        return 0.0 if total_sessions.zero?
        (ghost_sessions.to_f / total_sessions * 100).round(1)
      end

      def details
        { total_sessions: total_sessions, ghost_sessions: ghost_sessions }
      end

      def total_sessions
        @total_sessions ||= recent_sessions.count
      end

      def ghost_sessions
        @ghost_sessions ||= recent_sessions
          .where(initial_referrer: [nil, ""])
          .where("initial_utm IS NULL OR initial_utm = '{}'::jsonb")
          .where("click_ids IS NULL OR click_ids = '{}'::jsonb")
          .where(<<~SQL.squish)
            NOT EXISTS (SELECT 1 FROM events WHERE events.session_id = sessions.id)
          SQL
          .count
      end

      def recent_sessions
        account.sessions.where("started_at > ?", WINDOW.ago)
      end
    end
  end
end
```

**Note on ghost definition:** The ghost check is intentionally narrow — sessions with 0 events AND nil referrer AND empty UTM AND empty click_ids. Self-referral sessions are caught separately by the `SelfReferralRate` check. This avoids double-counting.

### CheckRunner (Orchestrator)

Inherits `ApplicationService` — persists to DB, can fail.

```ruby
module DataIntegrity
  class CheckRunner < ApplicationService
    CHECKS = [
      Checks::GhostSessionRate,
      Checks::SessionInflation,
      Checks::VisitorInflation,
      Checks::SelfReferralRate,
      Checks::AttributionMismatch,
      Checks::SessionsPerConverter,
      Checks::EventVolume,
      Checks::FingerprintInstability,
      Checks::MissingFingerprintRate,
      Checks::ExtremeSessionVisitors
    ].freeze

    def initialize(account)
      @account = account
    end

    private

    attr_reader :account

    def run
      results = CHECKS.map { |check_class| check_class.new(account).call }
      persist_results(results)
      success_result(results: results)
    end

    def persist_results(results)
      results.each do |result|
        DataIntegrityCheck.create!(
          account: account,
          check_name: result[:check_name],
          status: result[:status],
          value: result[:value],
          warning_threshold: result[:warning_threshold],
          critical_threshold: result[:critical_threshold],
          details: result[:details]
        )
      end
    end
  end
end
```

### Surveillance Job

```ruby
module DataIntegrity
  class SurveillanceJob < ApplicationJob
    queue_as :default

    def perform(account_id)
      DataIntegrity::CheckRunner.new(Account.find(account_id)).call
    end
  end
end
```

Scheduled via Solid Queue recurring config in `config/recurring.yml`:

```yaml
production:
  # ... existing jobs ...

  data_integrity_surveillance:
    class: DataIntegrity::SurveillanceSchedulerJob
    schedule: every 6 hours

  data_integrity_cleanup:
    class: DataIntegrity::CleanupJob
    schedule: at 3am every day
```

The scheduler job enqueues one `SurveillanceJob` per active account.

**Note:** `Account` model needs `has_many :data_integrity_checks, dependent: :destroy` in its relationships concern.

---

## Admin Dashboard

### Routes

```ruby
namespace :admin do
  # existing...
  resources :data_integrity, only: [:index, :show]
end
```

### Index View (All Accounts)

Table showing each account with their overall health status and worst check:

| Account | Status | Worst Check | Value | Last Run |
|---------|--------|-------------|-------|----------|
| PetPro360 | Critical | ghost_session_rate | 98.6% | 2h ago |
| Acme Corp | Healthy | — | — | 1h ago |
| Example Ltd | Warning | session_inflation | 2.3x | 3h ago |

Sort by status (critical first), then by last run time.

### Show View (Account Detail)

All checks for a single account with current values and sparkline history:

| Check | Status | Current | Threshold (W/C) | Trend (7d) |
|-------|--------|---------|-----------------|------------|
| Ghost Session Rate | Critical | 98.6% | 20% / 50% | [sparkline] |
| Session Inflation | Critical | 37x | 2x / 5x | [sparkline] |
| Attribution Mismatch | Critical | 88.3% | 25% / 50% | [sparkline] |
| Self-Referral Rate | Critical | 72% | 15% / 40% | [sparkline] |
| Fingerprint Instability | Critical | 34% | 10% / 25% | [sparkline] |
| Missing Fingerprint Rate | Critical | 27.6% | 5% / 20% | [sparkline] |
| Extreme Session Visitors | Critical | 8.2% | 1% / 5% | [sparkline] |
| Event Volume | Healthy | +5% | -30% / -60% | [sparkline] |

Each check links to the relevant diagnostic query from the data integrity runbook.

---

## All States

| # | State | Condition | Expected |
|---|-------|-----------|----------|
| 1 | New account | No sessions/events yet | All checks return `healthy` (0 values) |
| 2 | Healthy account | Normal data patterns | All green |
| 3 | Ghost session spike | SDK bug or bot traffic | ghost_session_rate → warning/critical |
| 4 | Session inflation | Session continuity broken | session_inflation → warning/critical |
| 5 | Self-referral outbreak | page_host nil or missing | self_referral_rate → warning/critical |
| 6 | Attribution drift | Event linking to wrong session | attribution_mismatch → warning/critical |
| 7 | Event volume drop | SDK not sending, API down, client broke integration | event_volume → warning/critical |
| 8 | Event volume spike | Bot attack, duplicate events | event_volume → warning/critical |
| 9 | Test account | `is_test: true` sessions | Excluded from checks |
| 10 | Inactive account | No sessions in 30 days | Skip surveillance (no job enqueued) |
| 11 | Multiple warnings | Several checks at warning | Account status = warning (worst wins) |
| 12 | Mixed warning+critical | Some warning, some critical | Account status = critical (worst wins) |
| 13 | Fingerprint instability | Visitor IP/UA changing mid-session (mobile networks, proxies) | fingerprint_instability → warning/critical |
| 14 | Missing fingerprints | SDK not sending IP/UA, old SDK version, or proxy stripping headers | missing_fingerprint_rate → warning/critical |
| 15 | Suspicious dedup merge | Visitor with 50+ distinct fingerprints — likely incorrect merge of multiple real visitors | extreme_session_visitors → investigate dedup logic |

---

## Implementation Tasks

### Phase 1: Data Model + Base Infrastructure

- [x] **1.1** Create migration for `data_integrity_checks` table
- [x] **1.2** Create `DataIntegrityCheck` model with validations
- [x] **1.3** Create `DataIntegrity::Checks::BaseCheck` base class
- [x] **1.4** Create `DataIntegrity::CheckRunner` orchestrator
- [x] **1.5** Write tests for BaseCheck and CheckRunner

### Phase 2: Individual Checks

- [x] **2.1** `GhostSessionRate` check + tests (7 tests)
- [x] **2.2** `SessionInflation` check + tests (7 tests)
- [x] **2.3** `VisitorInflation` check + tests (7 tests)
- [x] **2.4** `SelfReferralRate` check + tests (7 tests)
- [x] **2.5** `AttributionMismatch` check + tests (6 tests)
- [x] **2.6** `SessionsPerConverter` check + tests (6 tests)
- [x] **2.7** `EventVolume` check + tests (9 tests, bi-directional)
- [x] **2.8** `FingerprintInstability` check + tests (6 tests)
- [x] **2.9** `MissingFingerprintRate` check + tests (6 tests)
- [x] **2.10** `ExtremeSessionVisitors` check + tests (6 tests)

### Phase 3: Scheduled Job

- [x] **3.1** Create `SurveillanceJob` (thin wrapper)
- [x] **3.2** Create `SurveillanceSchedulerJob` (enqueues per account)
- [x] **3.3** Add to `config/recurring.yml` (surveillance every 6h, cleanup at 3am daily)
- [x] **3.4** Create `CleanupJob` — deletes checks older than 30 days

### Phase 4: Admin Dashboard

- [x] **4.1** Add routes for `admin/data_integrity`
- [x] **4.2** Create `Admin::DataIntegrityController` (index + show)
- [x] **4.3** Create index view (account list with health status, sorted critical-first)
- [x] **4.4** Create show view (current checks + 7-day history with details)
- [x] **4.5** Add navigation links in billing + submissions admin pages

---

## Testing Strategy

### Unit Tests

| Test | File | Verifies |
|------|------|----------|
| Ghost check returns healthy at 10% | `test/services/data_integrity/checks/ghost_session_rate_test.rb` | Below warning threshold |
| Ghost check returns warning at 25% | same | Between warning and critical |
| Ghost check returns critical at 60% | same | Above critical threshold |
| Ghost check returns healthy with 0 sessions | same | Division by zero handled |
| Session inflation returns healthy at 1.2x | `test/services/data_integrity/checks/session_inflation_test.rb` | Below warning threshold |
| Session inflation returns critical at 6x | same | Above critical threshold |
| Visitor inflation returns healthy at 1.1x | `test/services/data_integrity/checks/visitor_inflation_test.rb` | Below warning threshold |
| Visitor inflation returns critical at 4x | same | Above critical threshold |
| Self-referral returns healthy at 5% | `test/services/data_integrity/checks/self_referral_rate_test.rb` | Below warning threshold |
| Self-referral returns critical at 50% | same | Above critical threshold |
| Sessions per converter returns healthy at 3 | `test/services/data_integrity/checks/sessions_per_converter_test.rb` | Below warning threshold |
| Sessions per converter returns critical at 20 | same | Above critical threshold |
| CheckRunner runs all checks | `test/services/data_integrity/check_runner_test.rb` | All checks executed and persisted |
| CheckRunner persists results | same | Records created in DB |
| Attribution mismatch compares sessions | `test/services/data_integrity/checks/attribution_mismatch_test.rb` | Conversion vs landing session comparison |
| Event volume detects drop | `test/services/data_integrity/checks/event_volume_test.rb` | Period-over-period comparison |
| Event volume detects spike | same | Spike detection |
| Fingerprint instability detects multi-fp visitors | `test/services/data_integrity/checks/fingerprint_instability_test.rb` | Visitors with 2+ fingerprints per day |
| Fingerprint instability healthy when stable | same | All visitors have 1 fingerprint |
| Missing fingerprint detects nil fp sessions | `test/services/data_integrity/checks/missing_fingerprint_rate_test.rb` | Sessions without device_fingerprint |
| Extreme session visitors detects outliers | `test/services/data_integrity/checks/extreme_session_visitors_test.rb` | Visitors with 50+ sessions flagged |
| Extreme session visitors healthy when normal | same | All visitors have < 50 sessions |

### Controller Tests

| Test | Verifies |
|------|----------|
| Non-admin gets redirected | Access control works |
| Index shows all accounts with status | Dashboard renders |
| Show displays check history | Detail page renders |

---

### Phase 5: Real-Time Data Quality

**Problem:** With 6-hour check intervals, up to 6 hours of degraded data can flow into customer dashboards undetected. Customers see potentially unreliable data with no indication of quality issues.

**Solution:** Three complementary changes that close the detection gap.

- [x] **5.1** Tighten surveillance to hourly
- [x] **5.2** Add ingestion-time suspect flag to sessions
- [x] **5.3** Add customer-facing data quality banner

#### 5.1 Hourly Surveillance

Change `config/recurring.yml` from `every 6 hours` to `every hour`. Detection latency drops from 6h → 1h.

Trade-off: 6x more check rows per day (10 checks × 24 runs × N accounts). Mitigated by existing 30-day cleanup job.

#### 5.2 Ingestion-Time Suspect Flag

Add `suspect` boolean to sessions. Set at creation time in `Sessions::CreationService` when a session has **all** of:
- No referrer (nil or empty)
- No UTM params (nil or empty jsonb)
- No click_ids (nil or empty jsonb)

These are the hallmarks of a ghost session (the only missing signal is "0 events", which can't be known at creation time). Flagging at ingestion gives immediate signal without waiting for the next surveillance run.

```ruby
# In Sessions::CreationService, when building session attributes:
def suspect_session?
  referrer.blank? &&
    normalized_utm.values.none?(&:present?) &&
    click_ids.empty?
end
```

The `suspect` flag is informational — it doesn't block or hide anything. It enables:
- Fast queries: `account.sessions.where(suspect: true).count` (no subquery)
- Real-time dashboards can show "X% of recent sessions are suspect"
- GhostSessionRate check can use it as a pre-filter for faster execution

**Migration:**

```ruby
add_column :sessions, :suspect, :boolean, default: false, null: false
```

**Note:** TimescaleDB hypertable — must use `ALTER TABLE` directly, not `add_column` with index. Guard with `return if Rails.env.test?` for any TimescaleDB-specific DDL.

#### 5.3 Customer-Facing Data Quality Banner

Add `_data_quality_banner.html.erb` to `app/views/shared/`. Rendered on the customer dashboard (same pattern as `_billing_banner.html.erb`).

Uses the latest surveillance results for the account:

| Account Status | Banner |
|----------------|--------|
| `healthy` | None (hidden) |
| `warning` | Amber: "Some data quality metrics are outside normal ranges. Recent data may be less reliable." |
| `critical` | Red: "Data quality issues detected. Recent data may be unreliable. Our team has been notified." |
| `unknown` | None (no checks run yet) |

**Service:** `DataIntegrity::AccountHealthService` — thin query service that returns the account's current health status from the latest check run. Cached for 5 minutes via Solid Cache.

```ruby
module DataIntegrity
  class AccountHealthService
    def initialize(account)
      @account = account
    end

    def call
      Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
        latest_worst_status
      end
    end

    private

    attr_reader :account

    def latest_worst_status
      account.data_integrity_checks
        .where("created_at >= ?", 2.hours.ago)
        .order(Arel.sql("CASE status WHEN 'critical' THEN 0 WHEN 'warning' THEN 1 ELSE 2 END"))
        .pick(:status) || "unknown"
    end

    def cache_key
      "data_integrity/health/#{account.id}"
    end
  end
end
```

**Key Files (Phase 5):**

| File | Purpose |
|------|---------|
| `config/recurring.yml` | Change to hourly |
| `db/migrate/xxx_add_suspect_to_sessions.rb` | Migration |
| `app/services/sessions/creation_service.rb` | Set suspect flag |
| `app/services/data_integrity/account_health_service.rb` | Query health status |
| `app/views/shared/_data_quality_banner.html.erb` | Customer banner |
| `app/views/dashboard/show.html.erb` | Render banner |
| `app/controllers/dashboard_controller.rb` | Pass health status |

**Tests (Phase 5):**

| Test | File | Verifies |
|------|------|----------|
| Suspect flag set when no referrer/utm/click_ids | `test/services/sessions/creation_service_test.rb` | Flag set on ghost-like sessions |
| Suspect flag false when session has referrer | same | Flag not set on normal sessions |
| Suspect flag false when session has UTM | same | Flag not set on campaign sessions |
| AccountHealthService returns critical | `test/services/data_integrity/account_health_service_test.rb` | Worst status surfaced |
| AccountHealthService returns unknown with no checks | same | Graceful nil handling |
| AccountHealthService caches result | same | Cache key used |
| Data quality banner renders for critical | `test/views/shared/data_quality_banner_test.rb` or controller test | Banner visible |
| Data quality banner hidden for healthy | same | Banner not rendered |

---

## Definition of Done

- [x] All checks implemented with tests
- [x] Scheduled job runs every 6 hours
- [x] Scheduled job tightened to hourly
- [x] Admin dashboard shows account health
- [x] Critical accounts appear first
- [x] Check history visible for last 30 days
- [x] Ingestion-time suspect flag on sessions
- [x] Customer-facing data quality banner
- [ ] No performance impact on production (checks use read replicas if available)

---

## Out of Scope

- Email/Slack alerting (future: send notification when account goes critical)
- Auto-remediation (future: trigger data repair when certain checks fail)
- SDK version detection from User-Agent (useful but requires log parsing)

---

## Future Enhancements

1. **Alerting**: Slack webhook when account status changes to critical
2. **Trend analysis**: Detect gradual degradation (week-over-week comparison)
3. **Auto-repair**: When ghost_session_rate > 80% and stable for 24h, auto-run ghost purge
4. **SDK version tracking**: Parse `User-Agent: mbuzz-ruby/X.Y.Z` from API request logs
5. **Suspect session dashboard**: Admin view showing suspect session trends per account
6. **Auto-exclude suspect**: Option to exclude suspect sessions from dashboard calculations
