import http from "k6/http";
import { check, fail } from "k6";

const baseUrl = (__ENV.BASE_URL || "http://localhost:8080").replace(/\/$/, "");
const expectedStatus = Number(__ENV.EXPECTED_STATUS || "201");
const vus = Number(__ENV.VUS || "250");
const iterations = Number(__ENV.ITERATIONS || "20000");
const userCount = Number(__ENV.USER_COUNT || "20");
const maxDuration = __ENV.MAX_DURATION || "10m";
const requestTimeout = __ENV.REQUEST_TIMEOUT || "20s";
const runID = __ENV.RUN_ID || `kafka-gateway-${Date.now()}`;
const categoryID = __ENV.CATEGORY_ID || "d0000000-0000-0000-0000-000000000011";
const summaryJSON = __ENV.K6_SUMMARY_JSON || "load-tests/results/k6-kafka-gateway-orders-summary.json";
const summaryMD = __ENV.K6_SUMMARY_MD || "load-tests/results/k6-kafka-gateway-orders-summary.md";

export const options = {
  scenarios: {
    orders: {
      executor: "shared-iterations",
      vus,
      iterations,
      maxDuration,
    },
  },
  summaryTrendStats: ["min", "avg", "med", "p(90)", "p(95)", "p(99)", "max"],
};

export function setup() {
  const users = [];
  for (let i = 0; i < userCount; i += 1) {
    const email = `${runID}-user-${i}-${Date.now()}@example.test`;
    const payload = JSON.stringify({
      email,
      password: "LoadTest123",
      first_name: "Load",
      last_name: `User${i}`,
      phone: `+7999${String(i).padStart(7, "0")}`,
    });

    const response = http.post(`${baseUrl}/api/v1/auth/register`, payload, {
      headers: {
        "Content-Type": "application/json",
        "X-Forwarded-For": ipFor(i),
      },
      timeout: requestTimeout,
    });

    if (response.status !== 201) {
      fail(`register failed: status=${response.status} body=${response.body}`);
    }

    const body = response.json();
    users.push({
      user_id: body.user_id,
      access_token: body.access_token,
    });
  }

  return { users };
}

export default function (data) {
  const users = data.users || [];
  if (users.length === 0) {
    fail("no users available from setup");
  }

  const user = users[(__VU + __ITER) % users.length];
  const payload = JSON.stringify({
    category_id: categoryID,
    price: 1500 + (__ITER % 10) * 250,
    currency: "RUB",
    address: "Yakutsk, Gateway load street",
    title: `k6 Kafka gateway order #${__ITER + 1}`,
    description: "Created by user-to-system Kafka gateway load test",
    latitude: 62.0355,
    longitude: 129.6755,
  });

  const response = http.post(`${baseUrl}/api/v1/orders`, payload, {
    headers: {
      "Content-Type": "application/json",
      "Cookie": `access_token=${user.access_token}`,
      "X-Forwarded-For": ipFor(__VU),
      "X-Load-Test-Run": runID,
    },
    timeout: requestTimeout,
  });

  check(response, {
    [`status is ${expectedStatus}`]: (r) => r.status === expectedStatus,
  });
}

export function handleSummary(data) {
  return {
    stdout: textSummary(data),
    [summaryJSON]: JSON.stringify(data, null, 2),
    [summaryMD]: markdownSummary(data),
  };
}

function ipFor(seed) {
  const value = Number(seed || 0);
  const third = Math.floor(value / 240) % 240;
  const fourth = (value % 240) + 10;
  return `10.77.${third}.${fourth}`;
}

function metric(data, name) {
  return data.metrics[name]?.values || {};
}

function value(data, name, key) {
  const raw = metric(data, name)[key];
  if (raw === undefined || raw === null || Number.isNaN(raw)) {
    return 0;
  }
  return Number(raw);
}

function fmt(value) {
  return Number(value || 0).toFixed(3);
}

function textSummary(data) {
  const httpReqs = value(data, "http_reqs", "count");
  const failedRate = value(data, "http_req_failed", "rate");
  const checksRate = value(data, "checks", "rate");
  const duration = metric(data, "http_req_duration");

  return [
    "Grafana k6 Kafka gateway orders completed",
    `requests=${httpReqs}`,
    `failed_rate=${fmt(failedRate * 100)}%`,
    `checks_rate=${fmt(checksRate * 100)}%`,
    `latency p50=${fmt(duration.med)}ms p95=${fmt(duration["p(95)"])}ms p99=${fmt(duration["p(99)"])}ms`,
    `JSON: ${summaryJSON}`,
    `Report: ${summaryMD}`,
    "",
  ].join("\n");
}

function markdownSummary(data) {
  const httpReqs = value(data, "http_reqs", "count");
  const failedRate = value(data, "http_req_failed", "rate");
  const checksRate = value(data, "checks", "rate");
  const duration = metric(data, "http_req_duration");
  const waiting = metric(data, "http_req_waiting");
  const iterationDuration = metric(data, "iteration_duration");

  return `# Grafana k6 Kafka Gateway Orders Report

Generated: \`${new Date().toISOString()}\`

## Scenario

The test registers users through \`API Gateway -> auth-service\`, then sends user-facing \`POST /api/v1/orders\` requests through the API Gateway. The order-service persists the order and publishes the follow-up notification workflow through Kafka instead of waiting for notification-service synchronously.

## Configuration

| Parameter | Value |
|---|---:|
| Base URL | \`${baseUrl}\` |
| Expected status | ${expectedStatus} |
| VUs | ${vus} |
| Iterations | ${iterations} |
| Setup users | ${userCount} |
| Category ID | \`${categoryID}\` |
| Max duration | \`${maxDuration}\` |
| Request timeout | \`${requestTimeout}\` |

## Summary

| Requests | Failed rate | Check rate | p50, ms | p95, ms | p99, ms |
|---:|---:|---:|---:|---:|---:|
| ${httpReqs} | ${fmt(failedRate * 100)}% | ${fmt(checksRate * 100)}% | ${fmt(duration.med)} | ${fmt(duration["p(95)"])} | ${fmt(duration["p(99)"])} |

## HTTP Duration

| Min | Avg | p50 | p90 | p95 | p99 | Max |
|---:|---:|---:|---:|---:|---:|---:|
| ${fmt(duration.min)} | ${fmt(duration.avg)} | ${fmt(duration.med)} | ${fmt(duration["p(90)"])} | ${fmt(duration["p(95)"])} | ${fmt(duration["p(99)"])} | ${fmt(duration.max)} |

## Waiting Time

| Min | Avg | p50 | p90 | p95 | p99 | Max |
|---:|---:|---:|---:|---:|---:|---:|
| ${fmt(waiting.min)} | ${fmt(waiting.avg)} | ${fmt(waiting.med)} | ${fmt(waiting["p(90)"])} | ${fmt(waiting["p(95)"])} | ${fmt(waiting["p(99)"])} | ${fmt(waiting.max)} |

## Iteration Duration

| Min | Avg | p50 | p90 | p95 | p99 | Max |
|---:|---:|---:|---:|---:|---:|---:|
| ${fmt(iterationDuration.min)} | ${fmt(iterationDuration.avg)} | ${fmt(iterationDuration.med)} | ${fmt(iterationDuration["p(90)"])} | ${fmt(iterationDuration["p(95)"])} | ${fmt(iterationDuration["p(99)"])} | ${fmt(iterationDuration.max)} |
`;
}
