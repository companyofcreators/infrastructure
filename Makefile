.PHONY: up down build migrate keys-generate reset help

# Default network name used in docker-compose
NETWORK_NAME := diploma-network
KEY_DIR := ./keys

## help: Show this help
help:
	@grep -E '^##' $(MAKEFILE_LIST) | sed 's/^## //'

## up: Start all infrastructure services in detached mode
up:
	docker compose up -d

## down: Stop all infrastructure services
down:
	docker compose down

## build: Build all service Docker images
build:
	@echo "Building all services..."
	@for service in api-gateway auth-service user-service order-service offer-service chat-service file-service notification-service mail-service; do \
		if [ -f "$$service/Dockerfile" ]; then \
			echo "Building $$service..."; \
			docker build -t diploma/$$service:latest ./$$service; \
		else \
			echo "Skipping $$service (no Dockerfile)"; \
		fi; \
	done
	@echo "Build complete."

## migrate: Run all database migrations (requires running databases)
migrate:
	@echo "Running migrations for all services..."
	@for service in auth-service user-service order-service offer-service chat-service file-service notification-service; do \
		if [ -d "$$service/migrations" ]; then \
			short=$$(echo $$service | sed 's/-service//'); \
			container="postgres-$$short"; \
			db="$${short}_db"; \
			echo "Migrating $$service ($$container/$$db)..."; \
			for sql in $$service/migrations/*.up.sql; do \
				echo "  Running $$sql..."; \
				cat "$$sql" | docker exec -i $$container psql -U postgres -d $$db; \
			done; \
		else \
			echo "Skipping $$service (no migrations directory)"; \
		fi; \
	done
	@echo "Migrations complete."

## keys-generate: Generate RSA 256 key pair for JWT signing
keys-generate:
	@mkdir -p $(KEY_DIR)
	@openssl genrsa -out $(KEY_DIR)/private.pem 2048
	@openssl rsa -in $(KEY_DIR)/private.pem -pubout -out $(KEY_DIR)/public.pem
	@chmod 600 $(KEY_DIR)/private.pem
	@chmod 644 $(KEY_DIR)/public.pem
	@echo "RSA keys generated in $(KEY_DIR)/"

## reset: Full teardown including volumes (destroys all data)
reset:
	docker compose down -v
	@echo "Full reset complete. All volumes removed."
