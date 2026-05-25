# Quicky Infrastructure

Infrastructure and integration assets for the Quicky diploma marketplace.

## Contents

- `docker-compose.yml` - local infrastructure: PostgreSQL databases, Redis, Kafka, Kafka UI, MinIO, Mailpit, Postfix.
- `seed/` - development seed data.
- `docs/` - architecture diagrams and planning artifacts.
- `backend_use_case_tests.py` and `frontend_test_report.py` - end-to-end verification scripts.

Application source code lives in separate repositories under the `CompanyOfCreators` organization.

## Local Services

- API Gateway: `http://localhost:8080`
- Kafka UI: `http://localhost:8088`
- MinIO console: `http://localhost:9001`
- Mailpit: `http://localhost:8025`
