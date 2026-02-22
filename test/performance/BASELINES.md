# Performance Baselines

Measured on 2026-02-21 with fixture data. All tests in `test/performance/`.

## Ingestion

| Endpoint | Budget | Type |
|----------|--------|------|
| Session creation | < 50ms avg | timing |
| Event batch (10) | < 8x single event | timing (sub-linear) |
| Conversion tracking | < 75ms avg | timing |
| Identify | < 30ms avg | timing |
| Session creation | <= 20 queries | query budget |
| Event batch (10) | < 5x single event queries | query budget |
| Session creation | < 8,000 allocations | memory |
| Event batch (10) | < 8x single event allocations | memory |

## Attribution

| Operation | Budget | Type |
|-----------|--------|------|
| Calculator (fixture journey) | < 100ms avg | timing |
| CrossDeviceCalculator | < 100ms avg | timing |
| Calculator | <= 10 queries | query budget |
| CrossDeviceCalculator | <= 15 queries | query budget |
| Calculator | < 5,000 allocations | memory |

## Dashboard Queries

| Query | Budget | Type |
|-------|--------|------|
| TotalsQuery | < 200ms avg | timing |
| TimeSeriesQuery (30d) | < 300ms avg | timing |
| ByChannelQuery | < 200ms avg | timing |
| TotalsQuery | <= 10 queries | query budget |
| ByChannelQuery | <= 10 queries | query budget |

## How to Run

```bash
# All performance tests
bin/perf

# Specific category
bin/rails test test/performance/ingestion_performance_test.rb
bin/rails test test/performance/attribution_performance_test.rb
bin/rails test test/performance/dashboard_performance_test.rb
```

## Updating Baselines

When budgets need adjustment (new features, schema changes):
1. Run `bin/perf` and note actual values
2. Set budget to ~1.5x the actual value (headroom for CI variance)
3. Update this file with new budgets
