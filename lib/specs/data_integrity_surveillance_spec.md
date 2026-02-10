# Data Integrity Surveillance System

**Date:** 2026-02-09
**Priority:** P1
**Status:** Draft
**Branch:** TBD (after `fix/session-continuity`)

---

## Summary

We've been blindsided by data quality issues multiple times (see incidents: `2026-01-15`, `2026-01-29`, `2026-02-09`). Each time, the issue was invisible until a client or manual audit surfaced it.

This spec adds automated data health checks per account, run on a schedule, surfaced on an admin dashboard with warning/critical severity. The goal: never be surprised by data rot again.

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
  → DataIntegrity::SurveillanceJob (runs every 6 hours per account)
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
| **Event Volume Drop** | % decrease vs previous equivalent period | > 30% drop | > 60% drop |
| **Event Volume Spike** | % increase vs previous equivalent period | > 200% spike | > 500% spike |

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
| `app/jobs/data_integrity/surveillance_job.rb` | Scheduled job (thin wrapper) |
| `app/controllers/admin/data_integrity_controller.rb` | Admin dashboard |
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

### CheckRunner (Orchestrator)

```ruby
module DataIntegrity
  class CheckRunner
    CHECKS = [
      Checks::GhostSessionRate,
      Checks::SessionInflation,
      Checks::VisitorInflation,
      Checks::SelfReferralRate,
      Checks::AttributionMismatch,
      Checks::SessionsPerConverter,
      Checks::EventVolume
    ].freeze

    def initialize(account)
      @account = account
    end

    def call
      results = CHECKS.map { |check_class| check_class.new(account).call }
      persist_results(results)
      results
    end

    private

    attr_reader :account

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
data_integrity_surveillance:
  class: DataIntegrity::SurveillanceSchedulerJob
  schedule: every 6 hours
```

The scheduler job enqueues one `SurveillanceJob` per active account.

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
| Attribution Mismatch | Critical | 86% | 25% / 50% | [sparkline] |
| Self-Referral Rate | Critical | 72% | 15% / 40% | [sparkline] |
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

---

## Implementation Tasks

### Phase 1: Data Model + Base Infrastructure

- [ ] **1.1** Create migration for `data_integrity_checks` table
- [ ] **1.2** Create `DataIntegrityCheck` model with validations
- [ ] **1.3** Create `DataIntegrity::Checks::BaseCheck` base class
- [ ] **1.4** Create `DataIntegrity::CheckRunner` orchestrator
- [ ] **1.5** Write tests for BaseCheck and CheckRunner

### Phase 2: Individual Checks

- [ ] **2.1** `GhostSessionRate` check + tests
- [ ] **2.2** `SessionInflation` check + tests
- [ ] **2.3** `VisitorInflation` check + tests
- [ ] **2.4** `SelfReferralRate` check + tests
- [ ] **2.5** `AttributionMismatch` check + tests
- [ ] **2.6** `SessionsPerConverter` check + tests
- [ ] **2.7** `EventVolume` check + tests

### Phase 3: Scheduled Job

- [ ] **3.1** Create `SurveillanceJob` (thin wrapper)
- [ ] **3.2** Create `SurveillanceSchedulerJob` (enqueues per account)
- [ ] **3.3** Add to `config/recurring.yml`
- [ ] **3.4** Add cleanup job for old check results (>30 days)

### Phase 4: Admin Dashboard

- [ ] **4.1** Add routes for `admin/data_integrity`
- [ ] **4.2** Create `Admin::DataIntegrityController` (index + show)
- [ ] **4.3** Create index view (account list with health status)
- [ ] **4.4** Create show view (check detail with history)
- [ ] **4.5** Add navigation link in admin layout

---

## Testing Strategy

### Unit Tests

| Test | File | Verifies |
|------|------|----------|
| Ghost check returns healthy at 10% | `test/services/data_integrity/checks/ghost_session_rate_test.rb` | Below warning threshold |
| Ghost check returns warning at 25% | same | Between warning and critical |
| Ghost check returns critical at 60% | same | Above critical threshold |
| Ghost check returns healthy with 0 sessions | same | Division by zero handled |
| CheckRunner runs all checks | `test/services/data_integrity/check_runner_test.rb` | All checks executed and persisted |
| CheckRunner persists results | same | Records created in DB |
| Attribution mismatch compares sessions | `test/services/data_integrity/checks/attribution_mismatch_test.rb` | Conversion vs landing session comparison |
| Event volume detects drop | `test/services/data_integrity/checks/event_volume_test.rb` | Period-over-period comparison |
| Event volume detects spike | same | Spike detection |

### Controller Tests

| Test | Verifies |
|------|----------|
| Non-admin gets redirected | Access control works |
| Index shows all accounts with status | Dashboard renders |
| Show displays check history | Detail page renders |

---

## Definition of Done

- [ ] All checks implemented with tests
- [ ] Scheduled job runs every 6 hours
- [ ] Admin dashboard shows account health
- [ ] Critical accounts appear first
- [ ] Check history visible for last 30 days
- [ ] No performance impact on production (checks use read replicas if available)

---

## Out of Scope

- Email/Slack alerting (future: send notification when account goes critical)
- Auto-remediation (future: trigger data repair when certain checks fail)
- Client-facing health dashboard (this is admin-only)
- Real-time monitoring (this is periodic — 6-hour intervals)
- SDK version detection from User-Agent (useful but requires log parsing)

---

## Future Enhancements

1. **Alerting**: Slack webhook when account status changes to critical
2. **Trend analysis**: Detect gradual degradation (week-over-week comparison)
3. **Auto-repair**: When ghost_session_rate > 80% and stable for 24h, auto-run ghost purge
4. **Client health page**: Expose simplified version to account owners
5. **SDK version tracking**: Parse `User-Agent: mbuzz-ruby/X.Y.Z` from API request logs
