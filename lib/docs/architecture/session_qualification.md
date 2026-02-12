# Session Qualification

**Updated:** 2026-02-13

Every session in mbuzz is classified as either **qualified** or **suspect** at creation time. This classification is the primary filter between real visitor traffic and noise (bots, prefetch requests, asset hits). All dashboard queries and attribution models operate on qualified sessions only.

---

## The `suspect` Flag

`Sessions::CreationService` sets `suspect: true` when a session has **none** of:

- Referrer
- UTM parameters
- Click IDs (gclid, fbclid, etc.)

```ruby
# app/services/sessions/creation_service.rb
def suspect_session?
  referrer.blank? &&
    normalized_utm.values.none?(&:present?) &&
    click_ids.empty?
end
```

A session with any attribution signal — even just a referrer — is `suspect: false` (qualified).

---

## The `qualified` Scope

```ruby
# app/models/concerns/session/scopes.rb
scope :qualified, -> { where(suspect: false) }
```

This scope is the single gate between raw session data and analysis. It chains naturally with existing scopes:

```ruby
account.sessions.production.qualified  # All real, non-test sessions
```

---

## Where Qualification Is Enforced

| Layer | File | How |
|-------|------|-----|
| **Dashboard** | `Dashboard::Scopes::SessionsScope` | `base_scope` chains `.qualified` — all dashboard queries (funnel, totals, time series, channel breakdowns) inherit this filter automatically |
| **Attribution journeys** | `Attribution::JourneyBuilder` | `sessions_in_window` chains `.qualified` — suspect sessions never become touchpoints in conversion journeys |
| **Cross-device journeys** | `Attribution::CrossDeviceJourneyBuilder` | Same as above for identity-linked visitors |

Because filtering happens at these two entry points, all downstream consumers — `FunnelStagesQuery`, `TotalsQuery`, `AttributionCalculationService`, `Markov::ConversionPathsQuery`, etc. — operate on clean data without needing their own filters.

---

## What Suspect Sessions Are

Most suspect sessions are:

1. **Bot traffic** — Crawlers and scanners that don't send `Sec-Fetch-*` headers and bypass the SDK's navigation detection blacklist
2. **Prefetch/prerender requests** — Browser and CDN preflight requests that look like page loads
3. **Concurrent burst noise** — Multiple requests from rotating IPs that create separate fingerprints for the same logical visit

Suspect sessions are **not deleted**. They remain in the database for:

- Surveillance checks (`DataIntegrity::Checks::GhostSessionRate`)
- Bot traffic analysis
- Debugging SDK integration issues
- Audit trail

---

## Why Not Delete Them?

Deleting suspect sessions would:

- Destroy evidence needed to diagnose SDK issues
- Make surveillance checks impossible (can't measure what you've deleted)
- Remove the ability to reclassify if the heuristic improves
- Break referential integrity if any events were somehow linked

The `qualified` scope gives us the same analytical benefit as deletion without the data loss.

---

## Impact on Metrics

Before qualification filtering was added, a production account showed:

| Metric | Unfiltered | Filtered (qualified) | GA4 (ground truth) |
|--------|-----------|---------------------|---------------------|
| Visitors | 13,702 | ~2,758 | 2,430 |
| Ghost rate | 64.2% | 0% (by definition) | N/A |
| Direct channel | 10,944 | ~200 | ~200 |

Non-direct channels (paid, organic, referral, email) were largely unaffected — suspect sessions have no attribution signals, so they all land in "direct."

---

## Adding New Query Paths

If you add a new service or query that reads sessions for display or attribution:

**Use the scope.** Chain `.qualified` or build on `SessionsScope` which includes it automatically.

```ruby
# GOOD — inherits qualified filter
sessions_scope = Dashboard::Scopes::SessionsScope.new(
  account: account, date_range: date_range
).call

# GOOD — explicit qualified filter
account.sessions.production.qualified.where(channel: "paid_search")

# BAD — raw query includes suspect sessions
account.sessions.production.where(channel: "paid_search")
```

The only code that should query unfiltered sessions is:

- `Sessions::CreationService` (creating/finding sessions)
- `Sessions::ResolutionService` (resolving events to sessions)
- `DataIntegrity::Checks::*` (measuring data quality)
- Debugging/repair scripts
