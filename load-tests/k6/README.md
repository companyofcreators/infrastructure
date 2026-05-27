# Grafana k6 API Gateway Tests

## Kafka Gateway Orders

`kafka-gateway-orders.js` checks the user-facing Kafka project path:

```text
k6 -> API Gateway -> auth-service register -> access_token cookie
k6 -> API Gateway -> order-service -> Kafka -> notification-service
```

Run normal load:

```powershell
cd C:\Users\ostap\Work\diploma
$env:BASE_URL='http://localhost:8080'
$env:USER_COUNT='20'
$env:VUS='250'
$env:ITERATIONS='20000'
$env:EXPECTED_STATUS='201'
$env:REQUEST_TIMEOUT='20s'
$env:K6_SUMMARY_JSON='load-tests/results/k6-kafka-gateway-normal.json'
$env:K6_SUMMARY_MD='load-tests/results/k6-kafka-gateway-normal.md'
k6.exe run .\load-tests\k6\kafka-gateway-orders.js
```

For the notification outage scenario, stop `notification-service` on port `8087`, keep Kafka and `order-service` running, and run:

```powershell
$env:USER_COUNT='5'
$env:VUS='50'
$env:ITERATIONS='1000'
$env:EXPECTED_STATUS='201'
k6.exe run .\load-tests\k6\kafka-gateway-orders.js
```

The final comparison report is in:

```text
C:\Users\ostap\Work\diploma-sync\GATEWAY_LOAD_TEST_REPORT.md
```
