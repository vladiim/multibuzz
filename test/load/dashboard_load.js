// k6 load test: dashboard queries under concurrent load
// Usage: k6 run test/load/dashboard_load.js --env SESSION_COOKIE=xxx
//
// Scenario: 20 concurrent users querying dashboard for 60s

import http from "k6/http";
import { check, sleep } from "k6";

const BASE_URL = __ENV.BASE_URL || "http://localhost:3000";
const SESSION_COOKIE = __ENV.SESSION_COOKIE || "_mbuzz_session=replaceme";

const headers = {
  Cookie: SESSION_COOKIE,
  Accept: "text/html, application/json",
};

export const options = {
  scenarios: {
    dashboard_users: {
      executor: "constant-vus",
      vus: 20,
      duration: "60s",
    },
  },
  thresholds: {
    http_req_duration: ["p95<500", "p99<1000"],
    http_req_failed: ["rate<0.01"],
  },
};

const DASHBOARD_PATHS = [
  "/dashboard",
  "/dashboard/conversions",
  "/dashboard/conversions?date_range=7d",
  "/dashboard/conversions?date_range=30d",
  "/dashboard/conversions?date_range=90d",
];

export default function () {
  const path = DASHBOARD_PATHS[Math.floor(Math.random() * DASHBOARD_PATHS.length)];

  const res = http.get(`${BASE_URL}${path}`, { headers });

  check(res, {
    "status is 200 or 302": (r) => r.status === 200 || r.status === 302,
  });

  sleep(1 + Math.random() * 2); // simulate user think time
}
