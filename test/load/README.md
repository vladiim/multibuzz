# Load Tests

Load tests for mbuzz using [k6](https://k6.io). Not CI-gated — run manually before deploys.

## Prerequisites

```bash
brew install k6
```

## Ingestion Load Test

Tests session creation + event tracking under sustained and spike load.

```bash
# Against local server
k6 run test/load/ingestion_load.js --env API_KEY=sk_test_your_key

# Against staging/production
k6 run test/load/ingestion_load.js --env BASE_URL=https://mbuzz.co --env API_KEY=sk_test_your_key
```

**Thresholds:**
- p95 response time < 100ms
- p99 response time < 250ms
- Error rate < 1%

**Scenarios:**
- Steady state: 100 req/s for 60s
- Spike: ramp to 500 req/s for 30s, then recover

## Dashboard Load Test

Tests dashboard queries under concurrent user load.

```bash
# Get a session cookie by logging in via browser, then:
k6 run test/load/dashboard_load.js --env SESSION_COOKIE="_mbuzz_session=your_cookie"
```

**Thresholds:**
- p95 response time < 500ms
- p99 response time < 1s
- Error rate < 1%

**Scenario:** 20 concurrent users for 60s with simulated think time.
