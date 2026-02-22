// k6 load test: ingestion endpoints (sessions + events)
// Usage: k6 run test/load/ingestion_load.js --env API_KEY=sk_test_xxx
//
// Scenarios:
//   steady_state: 100 req/s for 60s
//   spike:        ramp to 500 req/s for 30s, recover

import http from "k6/http";
import { check, sleep } from "k6";

const BASE_URL = __ENV.BASE_URL || "http://localhost:3000";
const API_KEY = __ENV.API_KEY || "sk_test_replaceme";

const headers = {
  Authorization: `Bearer ${API_KEY}`,
  "Content-Type": "application/json",
};

export const options = {
  scenarios: {
    steady_state: {
      executor: "constant-arrival-rate",
      rate: 100,
      timeUnit: "1s",
      duration: "60s",
      preAllocatedVUs: 50,
    },
    spike: {
      executor: "ramping-arrival-rate",
      startRate: 100,
      timeUnit: "1s",
      stages: [
        { duration: "10s", target: 500 },
        { duration: "30s", target: 500 },
        { duration: "10s", target: 100 },
      ],
      preAllocatedVUs: 200,
      startTime: "70s",
    },
  },
  thresholds: {
    http_req_duration: ["p95<100", "p99<250"],
    http_req_failed: ["rate<0.01"],
  },
};

function randomHex(len) {
  let result = "";
  const chars = "0123456789abcdef";
  for (let i = 0; i < len; i++) {
    result += chars.charAt(Math.floor(Math.random() * 16));
  }
  return result;
}

export default function () {
  const visitorId = randomHex(64);
  const sessionId = randomHex(64);

  // 1. Session creation
  const sessionRes = http.post(
    `${BASE_URL}/api/v1/sessions`,
    JSON.stringify({
      session: {
        visitor_id: visitorId,
        session_id: sessionId,
        url: `https://example.com/landing?utm_source=google&utm_medium=cpc&utm_campaign=load_test_${randomHex(4)}`,
      },
    }),
    { headers }
  );

  check(sessionRes, {
    "session status is 202": (r) => r.status === 202,
  });

  sleep(0.1);

  // 2. Event tracking
  const eventRes = http.post(
    `${BASE_URL}/api/v1/events`,
    JSON.stringify({
      events: [
        {
          event_type: "page_view",
          visitor_id: visitorId,
          session_id: sessionId,
          properties: { url: `https://example.com/product/${randomHex(8)}` },
        },
      ],
    }),
    { headers }
  );

  check(eventRes, {
    "event status is 202": (r) => r.status === 202,
  });
}
