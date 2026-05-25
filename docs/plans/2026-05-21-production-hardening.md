# Production Hardening — Implementation Plan

> **For Claude:** Используй superpowers:subagent-driven-development для реализации плана по задачам.
> Перед началом вызови superpowers:using-git-worktrees для изоляции изменений.

**Goal:** Исправить ~130 проблем безопасности, надёжности и качества кода в 9 микросервисах до production level.

**Architecture:** Работаем по категориям, каждая фаза = одна инъекция изменений в несколько сервисов параллельно. Агенты Opus для сложных задач, Sonnet для механических.

**Tech Stack:** Go 1.23+, chi/v5, segmentio/kafka-go, pgx/sqlx, Redis, MinIO, WebSocket

---

## ФАЗА 1: КРИТИЧЕСКИЕ — Безопасность + атомарность (5 задач, параллельно)

### Task 1.1: Internal header signing (все сервисы)

**Проблема:** Все сервисы доверяют `X-User-Id`, `X-User-Role`, `X-User-Email` без криптографической проверки.

**Решение:** В api-gateway подписывать внутренние заголовки HMAC-SHA256 с общим ключом. Во всех сервисах проверять подпись перед доверием.

**Files:**
- Create: `api-gateway/internal/auth/header_signer.go` — подпись заголовков
- Modify: `api-gateway/internal/middleware/auth.go:93-96` — вызывать SignHeaders после Set
- Modify: `api-gateway/internal/proxy/reverse_proxy.go:74-78` — фильтровать Cookie, добавлять подпись
- Create: `auth-service/internal/auth/header_verifier.go` — проверка подписи
- Modify: `auth-service/cmd/api/main.go` — инициализировать verifier с ключом
- Create: `pkg/header_auth/verifier.go` — общий verifier для user, order, offer, chat, file, notification
- Modify: `user-service/internal/interfaces/http/handler.go:249` — проверять подпись
- Modify: `order-service/internal/interfaces/http/handler.go:686-692` — проверять подпись
- Modify: `offer-service/internal/interfaces/http/handler.go` — проверять подпись
- Modify: `chat-service/internal/interfaces/http/handler.go:73` — проверять подпись
- Modify: `file-service/internal/interfaces/http/handler.go:79` — проверять подпись
- Modify: `notification-service/internal/interfaces/http/handler.go` — проверять подпись
- Modify: `docker-compose.yml` — добавить `HEADER_HMAC_KEY` в environment

### Task 1.2: Transactional registration (auth-service)

**Проблема:** Create + InsertRole + CreateProfile выполняются без транзакции.

**Решение:** Обернуть три операции в `pgx.BeginTx`.

**Files:**
- Modify: `auth-service/internal/infrastructure/db/credential_repo.go` — добавить `CreateTx(ctx, tx, cred)` метод
- Modify: `auth-service/internal/application/auth/register.go:126-151` — обернуть в транзакцию
- Modify: `auth-service/internal/infrastructure/db/postgres.go` — для работы с транзакциями

### Task 1.3: Atomic AcceptOffer (offer-service)

**Проблема:** UpdateStatus → RejectAllExcept → AssignOrder API → Kafka. При сбое AssignOrder — inconsistent state.

**Решение:** Добавить компенсирующие действия: при ошибке AssignOrder — rollback статуса оффера обратно на `pending`. Добавить retry для AssignOrder с exponential backoff.

**Files:**
- Modify: `offer-service/internal/domain/offer/service.go:162-174` — rollback при ошибке AssignOrder
- Modify: `offer-service/internal/app/order_client.go:89-112` — retry с backoff
- Modify: `offer-service/internal/domain/offer/errors.go` — добавить ErrAssignOrderFailed

### Task 1.4: SwitchRole fail-closed (user-service)

**Проблема:** При недоступности order-service проверка активных заказов пропускается (fail-open).

**Решение:** Возвращать ошибку, блокирующую смену роли, если order-service недоступен. Добавить retry (3 попытки с backoff).

**Files:**
- Modify: `user-service/internal/application/user/switch_role.go:50-57` — убрать Warn + proceed, заменить на return err
- Modify: `user-service/internal/application/user/switch_role.go:130-138` — то же для DisableMasterRole
- Modify: `user-service/internal/app/order_client.go` — добавить retry

### Task 1.5: Remove self-assign role (auth-service)

**Проблема:** Любой может указать `"role":"admin"` при регистрации.

**Решение:** Убрать `Role` поле из `RegisterRequest`. Всегда создавать с ролью `user`. Админ назначает роль через `PUT /api/v1/admin/users/{id}`.

**Files:**
- Modify: `auth-service/internal/interfaces/http/dto.go:12` — убрать Role из RegisterRequest
- Modify: `auth-service/internal/interfaces/http/handler/auth_handler.go:22` — убрать Role
- Modify: `auth-service/internal/application/auth/register.go:88-100` — всегда `user`
- Modify: `auth-service/internal/interfaces/http/router.go` — роут для admin change-role эндпоинта

---

## ФАЗА 2: ВЫСОКИЕ — Надёжность инфраструктуры (5 параллельных групп)

### Task 2.1: HTTP client with timeout (api-gateway)

**Files:**
- Modify: `api-gateway/internal/proxy/reverse_proxy.go` — создать `http.Client{Timeout: 30s}`, убрать `http.DefaultClient`
- Modify: `api-gateway/internal/app/container.go:84` — прокинуть клиент в ReverseProxy

### Task 2.2: Kafka production configs (5 сервисов)

**Files:**
- Modify: `auth-service/internal/infrastructure/kafka/producer.go:26-33` — RequireQuorum, sync, убрать AllowAutoTopicCreation
- Modify: `order-service/internal/infrastructure/kafka/producer.go:74-77` — RequireQuorum, sync
- Modify: `offer-service/internal/infrastructure/kafka/producer.go:24-31` — RequireQuorum, sync, добавить WriteTimeout
- Modify: `chat-service/internal/infrastructure/kafka/producer.go:29` — убрать AllowAutoTopicCreation
- Modify: `file-service/internal/infrastructure/kafka/producer.go:21` — убрать AllowAutoTopicCreation
- Modify: `notification-service/internal/infrastructure/kafka/producer.go:57-92` — RequireQuorum
- Modify: `docker-compose.yml` — предсоздать все Kafka топики через kafka-init

### Task 2.3: context.Background() elimination (order-service + notification-service)

**Files:**
- Modify: `order-service/internal/application/order/create_order.go:72-83` — передавать ctx с timeout
- Modify: `order-service/internal/application/order/cancel_order.go:70-78` — то же
- Modify: `order-service/internal/application/order/complete_order.go:69-88` — то же
- Modify: `order-service/internal/application/order/create_review.go:57-67` — то же
- Modify: `order-service/internal/application/order/create_complaint.go:51-65` — то же
- Modify: `order-service/internal/application/order/update_status.go:60,72` — то же
- Modify: `notification-service/internal/application/notification/process_event.go` — все Kafka publish с ctx

### Task 2.4: Remove in-memory rate limiter (auth-service)

**Files:**
- Modify: `auth-service/internal/interfaces/http/router.go:15-117` — убрать rateLimitStore, cleanup goroutine, LoginRateLimiter
- Проверить: rate-limit уже есть на gateway (100 req/min), дублирование не нужно

### Task 2.5: Startup hardening (auth + notification)

**Files:**
- Modify: `auth-service/cmd/api/main.go:55-57` — `log.Fatal` вместо `logger.Warn` при ошибке миграции
- Modify: `notification-service/internal/application/notification/process_event.go:468-471` — `uuid.Parse` вместо `uuid.MustParse`
- Modify: `offer-service/internal/pkg/logger.go:29` — убрать `slog.SetDefault`
- Modify: `user-service/internal/pkg/logger.go` — убрать `slog.SetDefault` (если есть)

### Task 2.6: Body size limits (все HTTP handlers)

**Files:**
- Modify: `api-gateway/internal/transport/http/router.go` — добавить `middleware.RequestSizeLimiter`
- Modify: `auth-service/internal/interfaces/http/router.go` — добавить лимит
- Modify: `order-service/internal/interfaces/http/router.go` — добавить лимит
- Modify: `offer-service/internal/interfaces/http/router.go` — добавить лимит
- Modify: `user-service/internal/interfaces/http/router.go` — добавить лимит
- Modify: `chat-service/internal/interfaces/http/router.go` — добавить лимит
- Modify: `file-service/internal/interfaces/http/router.go` — добавить лимит (учесть upload)
- Modify: `notification-service/internal/interfaces/http/router.go` — добавить лимит

---

## ФАЗА 3: СРЕДНИЕ — Качество кода (5 параллельных групп)

### Task 3.1: Error handling — all `_` fixes

**Файлы по каждому сервису:**

**api-gateway:**
- `internal/transport/http/router.go:44` — проверить w.Write error
- `internal/middleware/rate_limit.go:76-78` — проверить w.Write error
- `internal/middleware/recovery.go:42` — log error from Encode
- `internal/middleware/auth.go:118` — log error from Encode
- `internal/client/order_client.go:61` — проверить io.ReadAll error
- `internal/client/user_client.go:60` — проверить io.ReadAll error
- `internal/config/config.go:44` — log warning from godotenv.Load

**auth-service:**
- `internal/config/config.go:30` — log godotenv error
- `internal/infrastructure/db/credential_repo.go:75` — проверить RowsAffected error
- `internal/infrastructure/redis/refresh_token_repo.go:61,77` — проверить Del errors

**user-service:**
- `internal/config/config.go:19` — log godotenv error
- `internal/infrastructure/db/user_repo.go:97,180,219,242,309` — проверить RowsAffected
- `pkg/validator.go:83` — проверить Encode error
- `internal/interfaces/http/handler.go:306-307` — буферизовать перед WriteHeader

**order-service:**
- `internal/config/config.go:31` — log godotenv error
- `internal/app/container.go:191,200` — log ignored errors
- `internal/interfaces/http/handler.go:709-710` — буферизовать перед WriteHeader

**offer-service:**
- `internal/config/config.go:19` — log godotenv error
- `internal/app/order_client.go:93` — проверить json.Marshal error
- `internal/infrastructure/db/offer_repo.go:148` — проверить RowsAffected
- `internal/interfaces/http/handler.go:295-298` — проверить Atoi errors

**chat-service:**
- `internal/config/config.go:21` — log godotenv error
- `internal/app/container.go:175` — проверить pem.Decode
- `internal/infrastructure/websocket/hub.go:146-147,367,372` — error handling
- `internal/interfaces/ws/handler.go:171,246` — проверить errors

**file-service:**
- `internal/config/config.go:28` — log godotenv error
- `internal/application/file/download.go:52` — log thumbnail error
- `internal/application/file/upload.go:120,136` — log errors (не `_ = err`)

**notification-service:**
- `internal/config/config.go:21` — log godotenv error
- `internal/infrastructure/db/notification_repo.go:150,191` — проверить RowsAffected
- `internal/application/notification/process_event.go` — 19 json.Marshal → проверять ошибки

**mail-service:**
- `internal/config/config.go:27` — log godotenv error
- `internal/infrastructure/smtp/smtp_mailer.go:261` — log Close error

### Task 3.2: Remove splitAndTrim ×4 → strings.Split

**Files:**
- `chat-service/internal/config/config.go:38-69` — заменить на strings.Split + TrimSpace
- `notification-service/internal/config/config.go:55-86` — заменить
- `mail-service/internal/config/config.go:45-76` — заменить
- `offer-service/internal/config/config.go:53-84` — заменить
- `user-service/internal/config/config.go:36-66` — заменить
- `order-service/internal/config/config.go:64-95` — заменить

### Task 3.3: Dead code removal

**Files:**
- DELETE: `auth-service/internal/interfaces/http/dto.go` — дубликат (всё в auth_handler.go)
- Modify: `auth-service/internal/interfaces/http/handler/auth_handler.go:324-334` — удалить getUserIDFromContext
- Modify: `auth-service/internal/interfaces/http/handler/auth_handler.go:244-268` — удалить Validate handler (или добавить роут)
- Modify: `order-service/internal/application/order/create_order.go:16` — удалить historyRepo
- Modify: `offer-service/internal/infrastructure/db/offer_repo.go:83,97,132` — удалить argIdx
- Modify: `offer-service/pkg/validator.go:13-25` — удалить глобальную Validate переменную
- Modify: `notification-service/internal/infrastructure/db/notification_repo.go:257` — удалить `var _ = time.Now`

### Task 3.4: N+1 query fixes + string error discrimination

**Files:**
- Modify: `order-service/internal/infrastructure/db/review_repo.go:104-138` — объединить 3 запроса CanReview в 1 JOIN
- Modify: `order-service/internal/application/order/create_review.go:40-41` — использовать sentinel error для проверки
- Modify: `order-service/internal/interfaces/http/handler.go:534` — `errors.Is` вместо `strings.Contains`
- Modify: `chat-service/internal/application/chat/list_chats.go:48-65` — batch-запрос для LastMessage + UnreadCount

### Task 3.5: Security hardening (WebSocket, CORS, cookies, headers)

**Files:**
- Modify: `chat-service/internal/interfaces/ws/handler.go:66-68` — убрать InsecureSkipVerify, брать origin из конфига
- Modify: `notification-service/internal/interfaces/ws/handler.go:28-30` — убрать `return true`, брать из конфига
- Modify: `file-service/internal/interfaces/http/router.go:46-59` — CORS origin из конфига
- Modify: `auth-service/internal/interfaces/http/handler/auth_handler.go:279,290` — SameSiteStrictMode
- Modify: `auth-service/internal/application/auth/refresh.go:63-92` — save before delete
- Modify: `auth-service/internal/interfaces/http/router.go:79-81` — убрать ручной X-Forwarded-For
- Modify: `api-gateway/internal/proxy/reverse_proxy.go:75-78` — фильтровать Cookie заголовок
- Modify: `api-gateway/internal/middleware/rate_limit.go:90` — убрать `middleware.GetReqID`, использовать `r.RemoteAddr`

---

## ФАЗА 4: НИЗКИЕ — Косметика и конфигурация (3 параллельные группы)

### Task 4.1: Cleanup binaries + .env from git

**Files:**
- DELETE: `auth-service/svc.exe`, `auth-service/api.exe`
- DELETE: `user-service/svc.exe`, `user-service/api.exe`
- DELETE: `order-service/svc.exe`, `order-service/api.exe`, `order-service/order-svc.exe`
- DELETE: `offer-service/svc.exe`, `offer-service/api.exe`, `offer-service/offer-svc.exe`
- DELETE: `chat-service/svc.exe`, `chat-service/api.exe`
- DELETE: `file-service/svc.exe`, `file-service/api.exe`
- DELETE: `notification-service/svc.exe`, `notification-service/api.exe`
- DELETE: `mail-service/mail-svc.exe`, `mail-service/api.exe`
- DELETE: `api-gateway/svc.exe`, `api-gateway/api.exe`
- Modify: все `.gitignore` — добавить `*.exe` и `.env`
- Bash: `git rm --cached */**/*.exe && git rm --cached */.env`

### Task 4.2: Health check + error channels

**Files:**
- Modify: `api-gateway/internal/transport/http/router.go:41-44` — health проверяет Redis ping
- Modify: `api-gateway/internal/transport/http/router.go:30` — `panic` → `log.Warn` + skip docs
- Modify: `api-gateway/cmd/api/main.go:25-31` — `Fatalf` → send error via channel
- Modify: `auth-service/cmd/api/main.go:155-161` — `os.Exit` в goroutine → error channel
- Modify: `user-service/cmd/api/main.go:82-87` — `os.Exit` в goroutine → error channel
- Modify: `chat-service/cmd/api/main.go` — `panic` → `log.Fatal`
- Modify: `file-service/cmd/api/main.go:40` — `os.Exit` в goroutine → error channel
- Modify: `api-gateway/internal/proxy/reverse_proxy.go:96-107` — заменить на `io.Copy`

### Task 4.3: Input validation hardening

**Files:**
- Modify: `auth-service/internal/interfaces/http/handler/auth_handler.go:16` — password min=8, добавить min=1 uppercase, digit
- Modify: `auth-service/internal/interfaces/http/handler/auth_handler.go:22` — phone format валидация
- Modify: `chat-service/internal/application/chat/send_message.go:43` — max message length 4096
- Modify: `mail-service/internal/application/mail/send_transactional.go:29-49` — email format validation
- Modify: `mail-service/internal/application/mail/process_command.go` — проверка валидности URL
- Modify: `api-gateway/internal/aggregator/user_profile.go:28` — UUID validation
- Modify: `api-gateway/internal/client/order_client.go:41` — URL encoding
- Modify: `api-gateway/internal/client/user_client.go:41` — URL encoding

---

## Порядок реализации

Фаза 1 (критические): 5 агентов Opus параллельно → review → commit
Фаза 2 (высокие): 6 агентов параллельно → review → commit
Фаза 3 (средние): 5 агентов параллельно → review → commit
Фаза 4 (низкие): 3 агента параллельно → review → commit

После каждой фазы: `make down && make up && make migrate && проверить health + дымовые тесты`
