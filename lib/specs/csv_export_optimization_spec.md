# CSV Export Optimization

**Date:** 2026-04-13
**Priority:** P0
**Status:** Complete
**Branch:** `feature/session-bot-detection`

---

## Problem

CSV exports crash the production site. The current implementation holds a DB connection for minutes, executing 40+ queries per export (one batch query + one session preload query per 500 credits). On a DB with `max_connections=25`, a single export saturates the connection pool and takes the entire site offline. The funnel export is worse — it loads all sessions, events, and conversions into memory, sorts them in Ruby, and can consume gigabytes of RAM.

## Solution

Replace the batch-per-query Ruby approach with a single SQL query that computes all 20 CSV columns server-side. All Ruby logic (`journey_position_for`, `array.index`, date arithmetic) maps directly to PostgreSQL functions (`CASE WHEN`, `array_position`, date subtraction). Verified locally — single SQL query produces identical output to the existing Ruby approach, row for row.

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Single SQL vs batch queries | Single SQL | 1 query instead of 40+, one brief connection hold instead of minutes |
| Keep background job | Yes | Still need Turbo Stream broadcast for status, and request timeout protection for large exports |
| `array_position` for journey index | PostgreSQL native | Replaces Ruby `Array#index`, no application memory needed |
| Enum mapping in SQL | `CASE WHEN` on integer | Avoids loading ActiveRecord models just to resolve enum labels |
| Funnel export via UNION ALL | Single ordered query | Replaces 3 separate full-table loads + in-memory Ruby sort |

## Verified

SQL and Ruby outputs compared locally on test data — **exact match** across all 20 columns for `CsvExportService` and all 12 columns for `FunnelCsvExportService`.

---

## Current State

### CsvExportService (conversions export)

**File:** `app/services/dashboard/csv_export_service.rb`

```
credits_scope.find_in_batches(500)     → 1 query per batch
  preload_journey_sessions(batch)      → 1 query per batch (sessions WHERE id IN [...])
  batch.each { row_for(credit) }       → Ruby: array.index, date arithmetic, position calc

10K credits = 20 batches = 40+ queries, connection held for minutes
```

### FunnelCsvExportService (funnel export)

**File:** `app/services/dashboard/funnel_csv_export_service.rb`

```
sessions_scope.find_each.map { }       → loads ALL sessions into memory
events_scope.find_each.map { }         → loads ALL events into memory
conversions_scope.find_each.map { }    → loads ALL conversions into memory
(visits + events + conversions).sort_by → sorts everything in Ruby

Memory bomb for large accounts. 3 full table scans.
```

### SQL replacement query (verified)

```sql
SELECT
  conversions.converted_at::date,
  'conversion' AS type,
  conversions.conversion_type,
  conversions.funnel,
  attribution_models.name,
  CASE attribution_models.algorithm
    WHEN 0 THEN 'first_touch' WHEN 1 THEN 'last_touch'
    WHEN 2 THEN 'linear'      WHEN 3 THEN 'time_decay'
    WHEN 4 THEN 'u_shaped'    WHEN 6 THEN 'participation'
    WHEN 7 THEN 'markov_chain' WHEN 8 THEN 'shapley_value'
  END,
  attribution_credits.channel,
  attribution_credits.credit,
  conversions.revenue,
  attribution_credits.revenue_credit,
  conversions.currency,
  attribution_credits.utm_source,
  attribution_credits.utm_medium,
  attribution_credits.utm_campaign,
  conversions.is_acquisition,
  COALESCE(conversions.properties::text, '{}'),
  CASE
    WHEN array_position(journey_session_ids, attribution_credits.session_id) = 1
      THEN 'first_touch'
    WHEN array_position(journey_session_ids, attribution_credits.session_id)
      = array_length(journey_session_ids, 1)
      THEN 'last_touch'
    ELSE 'assisted'
  END,
  array_position(journey_session_ids, attribution_credits.session_id),
  array_length(journey_session_ids, 1),
  (conversions.converted_at::date - sessions.started_at::date)
FROM attribution_credits
INNER JOIN conversions ON conversions.id = attribution_credits.conversion_id
INNER JOIN attribution_models ON attribution_models.id = attribution_credits.attribution_model_id
LEFT JOIN sessions ON sessions.id = attribution_credits.session_id
  AND sessions.account_id = attribution_credits.account_id
WHERE attribution_credits.account_id = ?
  AND attribution_credits.is_test = false
  AND conversions.converted_at BETWEEN ? AND ?
ORDER BY conversions.converted_at
```

### Funnel replacement query

```sql
-- Visits
SELECT started_at::date, 'visit', NULL, NULL, channel,
  initial_utm->>'utm_source', initial_utm->>'utm_medium', initial_utm->>'utm_campaign',
  NULL, NULL, NULL, NULL
FROM sessions WHERE account_id = ? AND ...

UNION ALL

-- Events
SELECT e.occurred_at::date, 'event', e.event_type, e.funnel, s.channel,
  s.initial_utm->>'utm_source', s.initial_utm->>'utm_medium', s.initial_utm->>'utm_campaign',
  NULL, NULL, NULL, e.properties::text
FROM events e INNER JOIN sessions s ON ...

UNION ALL

-- Conversions
SELECT c.converted_at::date, 'conversion', c.conversion_type, c.funnel, s.channel,
  s.initial_utm->>'utm_source', s.initial_utm->>'utm_medium', s.initial_utm->>'utm_campaign',
  c.revenue, c.currency, c.is_acquisition, c.properties::text
FROM conversions c LEFT JOIN sessions s ON ...

ORDER BY 1
```

Single query, sorted by PostgreSQL, zero Ruby memory overhead.

---

## All States

| State | Condition | Expected Behavior |
|-------|-----------|-------------------|
| Normal export | 1 month, ~10K credits | Completes in < 10s, 1 query, 1 connection |
| Large export | 6 months, ~100K credits | Completes in < 60s via cursor streaming |
| Empty date range | No credits in range | CSV with headers only, no error |
| NULL journey_session_ids | Conversion has no journey | journey_position/index/length/days all NULL |
| NULL session_id on credit | Session deleted | LEFT JOIN returns NULLs for session columns |
| Funnel export | All 3 stages | Single UNION ALL query, sorted by date |
| Concurrent exports | 2 users export simultaneously | Each holds 1 connection briefly, no contention |

---

## Implementation Phases

### Phase 1: CsvExportService (TDD)

- [x] **1.1** RED: Test service does not use find_in_batches or preload_journey_sessions
- [x] **1.2** RED: Test all algorithm enum values resolve correctly
- [x] **1.3** Existing 17 tests cover headers, columns, journey position, days_to_conversion, NULL handling, filters
- [x] **1.4** GREEN: Rewrite `CsvExportService#write_to` with single SQL query
- [x] **1.5** GREEN: Removed `preload_journey_sessions`, `find_in_batches`, `credits_scope`, `journey_data`, `journey_position_for`
- [x] **1.6** Run full test suite — 19 tests, 71 assertions, 0 failures, 0 new regressions

### Phase 2: FunnelCsvExportService (TDD)

- [x] **2.1** RED: Test service does not use find_each or in-memory sort_by
- [x] **2.2** Fixed pre-existing test failure (properties assertion matching wrong event)
- [x] **2.3** Existing 22 tests cover visits/events/conversions, date ordering, UTM, filters, isolation
- [x] **2.4** GREEN: Rewrite with UNION ALL query (visits + events + conversions, ORDER BY date)
- [x] **2.5** GREEN: Removed `find_each.map`, `sort_by`, `sessions_by_id`, all in-memory patterns
- [x] **2.6** Run full test suite — 23 tests, 38 assertions, 0 failures, 0 new regressions

---

## Testing Strategy

### Unit Tests

| Test | File | Verifies |
|------|------|----------|
| Headers match HEADERS constant | `test/services/dashboard/csv_export_service_test.rb` | First line of CSV |
| Credit columns from SQL | same | All 20 columns present and correct |
| Journey position logic | same | first_touch/last_touch/assisted computed correctly |
| Days to conversion | same | Date arithmetic matches Ruby computation |
| NULL journey handling | same | No crash, NULL values in journey columns |
| Empty range | same | Headers-only CSV |
| Funnel visit/event/conversion rows | `test/services/dashboard/funnel_csv_export_service_test.rb` | All 3 types present |
| Funnel date ordering | same | Rows sorted by date across types |
| Funnel UTM from JSONB | same | utm_source/medium/campaign extracted correctly |

---

## Definition of Done

- [ ] `CsvExportService` uses single SQL query (no `find_in_batches`, no `preload_journey_sessions`)
- [ ] `FunnelCsvExportService` uses UNION ALL query (no in-memory sort, no `find_each.map`)
- [ ] CSV output identical to current implementation (verified by tests)
- [ ] Export completes in < 60s for 6-month date range
- [ ] All tests pass
- [ ] Spec moved to `old/`

---

## Out of Scope

- Streaming HTTP response (keep background job + Turbo Stream for now)
- Progress bar during export
- Export pagination / row limits
- DB droplet resize (tracked in `db_resilience_spec.md`)
