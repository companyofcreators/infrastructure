# Quicky API — Полная документация для Frontend

> **Base URL:** `http://localhost:8080`
> **API Docs UI:** `http://localhost:8080/docs` (Scalar UI, OpenAPI 3.0)
> **Версия:** 1.0.0
> **Дата:** 2026-05-23

---

## 1. Аутентификация

### Способ 1: Cookie (для браузерных HTTP-запросов)

После логина сервер устанавливает HTTP-only cookie `access_token`. Браузер автоматически отправляет её с каждым запросом.

### Способ 2: Query-параметр (для WebSocket)

WebSocket-соединения передают токен через URL: `ws://host/path?token=JWT_TOKEN`

---

## 2. Auth — Регистрация и вход

Все эндпоинты публичные (без авторизации).

### `POST /api/v1/auth/register` — Регистрация

**Request:**
```json
{
  "email": "user@example.com",
  "password": "TestPass123",
  "first_name": "Иван",
  "last_name": "Петров",
  "middle_name": "Сергеевич",
  "birthdate": "1990-01-15",
  "phone": "+79001234567"
}
```

**Поля:** `email`*, `password`*, `first_name`*, `last_name`*, `phone`*, `middle_name`, `birthdate` (YYYY-MM-DD)

**Валидация пароля:** минимум 8 символов, одна заглавная буква, одна цифра.

**Response `201`:**
```json
{
  "access_token": "eyJhbG...",
  "refresh_token": "a1b2c3...",
  "user_id": "uuid",
  "email": "user@example.com",
  "roles": ["user"]
}
```

**Ошибки:** `400` (валидация), `409` (email занят)

### `POST /api/v1/auth/login` — Вход

**Request:**
```json
{
  "email": "user@example.com",
  "password": "TestPass123"
}
```

**Response `200`:**
```json
{
  "access_token": "eyJhbG...",
  "refresh_token": "a1b2c3...",
  "user_id": "uuid",
  "email": "user@example.com",
  "roles": ["user"]
}
```

**Ошибки:** `401` (неверные учётные данные), `403` (email не подтверждён / пользователь заблокирован)

### `POST /api/v1/auth/refresh` — Обновить токены

Отправляет cookie `refresh_token`. Возвращает новую пару токенов.

### `DELETE /api/v1/auth/logout` — Выход

Удаляет refresh-токен, сбрасывает cookies.

### `GET /api/v1/auth/verify-email?token=xxx` — Подтверждение email

---

## 3. Profile — Агрегированный профиль

### `GET /api/v1/profile` — Профиль + последние заказы

Требует авторизацию.

**Response `200`:**
```json
{
  "profile": {
    "id": "uuid",
    "first_name": "Иван",
    "last_name": "Петров",
    "avatar_url": "",
    "phone": "+79001234567",
    "birthdate": "1990-01-15T00:00:00Z",
    "updated_at": "2026-05-23T12:00:00Z"
  },
  "master_profile": null,
  "roles": ["user"],
  "recent_orders": []
}
```

---

## 4. Users — Управление профилем

### `GET /api/v1/users/{id}` — Профиль пользователя

Доступ: свой профиль или admin.

### `PATCH /api/v1/users/{id}` — Обновить профиль

**Request (все поля опциональны):**
```json
{
  "first_name": "НовоеИмя",
  "last_name": "НоваяФамилия",
  "phone": "+79000000000",
  "birthdate": "1995-05-20",
  "avatar_url": "https://example.com/avatar.jpg"
}
```

### `POST /api/v1/users/{id}/roles/master` — Стать мастером

Включает роль `master`, создаёт профиль мастера. При следующем логине роль появится в JWT.

**Response `200`:**
```json
{
  "user_id": "uuid",
  "is_active": true,
  "description": "",
  "experience_years": 0,
  "rating": 0,
  "completed_orders": 0,
  "updated_at": "2026-05-23T12:00:00Z"
}
```

### `DELETE /api/v1/users/{id}/roles/master` — Отключить роль мастера

**Response `200`:**
```json
{
  "message": "роль мастера отключена"
}
```

---

## 5. Masters — Профиль мастера

### `GET /api/v1/masters/{id}` — Профиль мастера

Доступ: любой аутентифицированный пользователь.

**Response `200`:**
```json
{
  "user_id": "uuid",
  "is_active": true,
  "description": "Веб-разработчик с 10-летним стажем",
  "experience_years": 10,
  "rating": 4.8,
  "completed_orders": 142,
  "updated_at": "2026-05-23T12:00:00Z"
}
```

### `PATCH /api/v1/masters/{id}` — Обновить профиль мастера

**Request (все поля опциональны):**
```json
{
  "description": "Новое описание",
  "experience_years": 5
}
```

---

## 6. Orders — Заказы

### `POST /api/v1/orders` — Создать заказ

Роль: любой аутентифицированный пользователь.

**Request:**
```json
{
  "title": "Нужен лендинг",
  "description": "Описание задачи, требования, сроки",
  "price": 50000,
  "category_id": "uuid-категории",
  "latitude": 55.7558,
  "longitude": 37.6176
}
```

**Поля:** `title`* (1-200 символов), `description` (до 5000), `price`* (>0, в рублях), `category_id`* (UUID), `latitude`* (float64), `longitude`* (float64)

**Response `201`:**
```json
{
  "order": {
    "id": "uuid",
    "customer_id": "uuid",
    "category_id": "uuid",
    "status": "created",
    "price": 50000,
    "currency": "RUB",
    "title": "Нужен лендинг",
    "description": "Описание задачи...",
    "latitude": 55.7558,
    "longitude": 37.6176,
    "created_at": "2026-05-23T12:00:00Z",
    "updated_at": "2026-05-23T12:00:00Z"
  }
}
```

**Статусы заказа:** `created` → `negotiation` / `assigned` → `in_progress` → `completed` | `cancelled`

### `GET /api/v1/orders` — Список заказов

**Query-параметры:**
| Параметр | Тип | Описание |
|----------|-----|----------|
| `status` | string | Фильтр по статусу |
| `category_id` | uuid | Фильтр по категории |
| `customer_id` | uuid | Фильтр по заказчику |
| `limit` | int | Лимит (по умолчанию 20) |
| `offset` | int | Смещение |

**Response `200`:**
```json
{
  "orders": [ { "...": "..." } ],
  "total": 42,
  "limit": 20,
  "offset": 0
}
```

### `GET /api/v1/orders/{id}` — Получить заказ

Доступ: владелец, admin, moderator.

**Response `200`:**
```json
{
  "order": {
    "id": "uuid",
    "customer_id": "uuid",
    "category_id": "uuid",
    "status": "created",
    "price": 50000,
    "title": "Нужен лендинг",
    "description": "Описание...",
    "accepted_offer_id": null,
    "created_at": "2026-05-23T12:00:00Z",
    "updated_at": "2026-05-23T12:00:00Z"
  }
}
```

### `PATCH /api/v1/orders/{id}/status` — Сменить статус

Роль: admin, moderator, master.

**Request:**
```json
{
  "status": "in_progress"
}
```

### `POST /api/v1/orders/{id}/cancel` — Отменить заказ

Роль: заказчик, admin, moderator.

### `POST /api/v1/orders/{id}/complete` — Завершить заказ

Роль: заказчик. Статус должен быть `in_progress`.

### `GET /api/v1/orders/{id}/history` — История статусов

**Response `200`:**
```json
{
  "history": [
    {
      "id": "uuid",
      "order_id": "uuid",
      "old_status": null,
      "new_status": "created",
      "changed_by": "uuid",
      "created_at": "2026-05-23T12:00:00Z"
    }
  ]
}
```

---

## 7. Categories — Категории заказов

### `GET /api/v1/categories` — Список категорий (публичный)

**Response `200`:**
```json
{
  "categories": [
    {
      "id": "uuid",
      "parent_id": "uuid или null",
      "name": "Веб-разработка",
      "slug": "web-development",
      "created_at": "2026-05-23T12:00:00Z"
    }
  ]
}
```

### `POST /api/v1/categories` — Создать категорию (admin)

**Request:**
```json
{
  "name": "Новая категория",
  "parent_id": "uuid или null"
}
```

### `PATCH /api/v1/categories/{id}` — Обновить (admin)

### `DELETE /api/v1/categories/{id}` — Удалить (admin)

---

## 8. Offers — Предложения мастеров

### `POST /api/v1/offers` — Отправить предложение

Роль: **master**. Нельзя иметь более одного pending-оффера на один заказ.

**Request:**
```json
{
  "order_id": "uuid-заказа",
  "price": 45000,
  "message": "Могу сделать за 45к за 3 дня"
}
```

**Response `201`:**
```json
{
  "id": "uuid",
  "order_id": "uuid",
  "master_id": "uuid",
  "price": 45000,
  "message": "Могу сделать за 45к за 3 дня",
  "status": "pending",
  "created_at": "2026-05-23T12:00:00Z"
}
```

**Статусы оффера:** `pending` → `accepted` / `rejected` / `withdrawn`

### `GET /api/v1/offers?order_id={uuid}` — Список предложений по заказу

### `GET /api/v1/offers/{id}` — Получить предложение

### `GET /api/v1/offers/{id}/history` — История переговоров по офферу

**Response:** массив NegotiationEvent:
```json
[
  {
    "id": "uuid",
    "offer_id": "uuid",
    "type": "offer.sent",
    "actor_id": "uuid",
    "actor_role": "master",
    "price": 45000,
    "message": "Могу сделать",
    "created_at": "2026-05-23T12:00:00Z"
  }
]
```

**Типы событий:** `offer.sent`, `offer.countered`, `offer.accepted`, `offer.rejected`, `offer.withdrawn`

### `POST /api/v1/offers/{id}/withdraw` — Отозвать предложение

Роль: **master**. Только свой pending-оффер.

### `POST /api/v1/offers/{id}/accept` — Принять предложение

Роль: **customer** (владелец заказа).

При принятии:
- Оффер получает статус `accepted`
- Все остальные pending-офферы по этому заказу автоматически отклоняются
- Заказ получает статус `assigned`, устанавливается `accepted_offer_id`

### `POST /api/v1/offers/{id}/reject` — Отклонить предложение

Роль: **customer** (владелец заказа).

### `POST /api/v1/offers/{id}/counter` — Контр-предложение

Роль: **customer** (владелец заказа). Не создаёт новый оффер, а создаёт переговорное событие типа `offer.countered`.

**Request:**
```json
{
  "price": 48000,
  "message": "Давайте договоримся на 48к"
}
```

**Response `200`:**
```json
{
  "id": "uuid",
  "offer_id": "uuid",
  "type": "offer.countered",
  "actor_id": "uuid",
  "actor_role": "customer",
  "price": 48000,
  "message": "Давайте договоримся на 48к",
  "created_at": "2026-05-23T12:00:00Z"
}
```

---

## 9. Chat — Чат

### REST эндпоинты

| Метод | Путь | Описание |
|--------|------|----------|
| `GET` | `/api/v1/chats` | Список чатов пользователя |
| `POST` | `/api/v1/chats` | Создать чат (после accept оффера, только для customer и назначенного master) |
| `GET` | `/api/v1/chats/{id}` | Информация о чате |
| `GET` | `/api/v1/chats/{id}/messages` | Сообщения (с пагинацией `?limit=&offset=`) |
| `POST` | `/api/v1/chats/{id}/messages` | Отправить сообщение (REST fallback) |
| `POST` | `/api/v1/chats/{id}/read` | Отметить прочитанным |

**Создание чата `POST /api/v1/chats`:**
```json
{
  "order_id": "uuid"
}
```

**Отправка сообщения `POST /api/v1/chats/{id}/messages`:**
```json
{
  "message": "Текст сообщения",
  "attachment_file_id": null
}
```

### WebSocket — Реальное время

**Connect:** `ws://localhost:8080/api/v1/chat/ws?token=JWT_TOKEN`
(или напрямую: `ws://localhost:8085/ws?token=JWT_TOKEN`)

#### Client → Server:

```json
{"type": "message.send",    "chat_id": "uuid", "message": "Привет!", "attachment_file_id": null}
{"type": "typing.start",    "chat_id": "uuid"}
{"type": "typing.stop",     "chat_id": "uuid"}
{"type": "messages.read",   "chat_id": "uuid"}
{"type": "ping"}
```

#### Server → Client:

```json
{"type": "message.new",     "chat_id": "uuid", "message": { "id": "uuid", "chat_id": "uuid", "sender_id": "uuid", "message": "Привет!", "attachment_file_id": null, "created_at": "2026-05-23T12:00:00Z" }}
{"type": "typing",          "chat_id": "uuid", "user_id": "uuid", "is_typing": true}
{"type": "messages.read",   "chat_id": "uuid", "user_id": "uuid"}
{"type": "pong"}
{"type": "error",           "message": "текст ошибки"}
```

---

## 10. Notifications — Уведомления

### REST эндпоинты

| Метод | Путь | Описание |
|--------|------|----------|
| `GET` | `/api/v1/notifications` | Список уведомлений |
| `GET` | `/api/v1/notifications/unread-count` | Счётчик непрочитанных |
| `POST` | `/api/v1/notifications/read-all` | Отметить все прочитанными |
| `POST` | `/api/v1/notifications/{id}/read` | Отметить одно прочитанным |
| `DELETE` | `/api/v1/notifications/{id}` | Удалить уведомление |

**Response уведомления:**
```json
{
  "id": "uuid",
  "user_id": "uuid",
  "type": "order.assigned",
  "title": "Заказ назначен",
  "message": "Ваш заказ \"Нужен лендинг\" назначен мастеру Ивану Петрову",
  "is_read": false,
  "created_at": "2026-05-23T12:00:00Z"
}
```

### WebSocket — Push-уведомления

**Connect:** `ws://localhost:8080/api/v1/notifications/ws?token=JWT_TOKEN`
(или напрямую: `ws://localhost:8087/ws?user_id=UUID`)

#### Server → Client:

```json
{"type": "notification.connected"}
{"type": "notification.new", "notification": { "id": "uuid", "type": "order.assigned", "title": "...", "message": "...", "is_read": false, "created_at": "..." }}
{"type": "notification.unread_count", "count": 5}
```

---

## 11. Orders WebSocket — Лента заказов (Real-time)

**Connect:** `ws://localhost:8080/api/v1/orders/ws?token=JWT_TOKEN`
(или напрямую: `ws://localhost:8083/ws?token=JWT_TOKEN`)

Подписка на все новые заказы и изменения статусов в реальном времени.

#### Server → Client:

```json
{"type": "order.connected"}
{"type": "order.created", "order": { "id": "uuid", "customer_id": "uuid", "category_id": "uuid", "title": "...", "description": "...", "price": 50000, "status": "created", "created_at": "...", "updated_at": "..." }}
{"type": "order.updated", "order": { "id": "uuid", "...": "...", "status": "assigned", "accepted_offer_id": "uuid" }}
```

События отправляются при: создании заказа, смене статуса, назначении мастера, завершении, отмене.

---

## 12. Offers WebSocket — Офферы по заказу (Real-time)

**Connect:** `ws://localhost:8080/api/v1/offers/ws?token=JWT_TOKEN&order_id=UUID`
(или напрямую: `ws://localhost:8084/ws?token=JWT_TOKEN&order_id=UUID`)

Подписка на все новые офферы и изменения по конкретному заказу.

#### Server → Client:

```json
{"type": "offer.connected"}
{"type": "offer.created",  "offer": { "id": "uuid", "order_id": "uuid", "master_id": "uuid", "price": 45000, "message": "...", "status": "pending", "created_at": "..." }}
{"type": "offer.updated",  "offer": { "id": "uuid", "...": "...", "status": "accepted" }}
{"type": "offer.countered","offer": { "id": "uuid", "offer_id": "uuid", "type": "offer.countered", "actor_id": "uuid", "actor_role": "customer", "price": 48000, "message": "...", "created_at": "..." }}
```

События отправляются при: новом оффере, отзыве, принятии, отклонении, контр-предложении.

---

## 13. Files — Файлы

| Метод | Путь | Описание |
|--------|------|----------|
| `POST` | `/api/v1/files/upload` | Загрузить файл (multipart, поле `file`) |
| `GET` | `/api/v1/files/{id}` | Метаданные файла |
| `GET` | `/api/v1/files/{id}/download` | Скачать файл |
| `DELETE` | `/api/v1/files/{id}` | Удалить файл |
| `GET` | `/api/v1/files` | Список файлов пользователя |

**Загрузка:** `multipart/form-data`, поле `file`. Допустимые MIME-типы: изображения, документы, архивы (png, jpg, jpeg, gif, webp, pdf, doc, docx, txt, zip).

**Response `201`:**
```json
{
  "id": "uuid",
  "owner_id": "uuid",
  "filename": "test.txt",
  "object_key": "path/in/minio/test.txt",
  "size": 1024,
  "content_type": "text/plain",
  "created_at": "2026-05-23T12:00:00Z"
}
```

---

## 14. Reviews — Отзывы

### `POST /api/v1/reviews` — Создать отзыв

**Request:**
```json
{
  "order_id": "uuid",
  "to_user_id": "uuid",
  "rating": 5,
  "comment": "Отличная работа!"
}
```

### `GET /api/v1/reviews/user/{id}` — Отзывы пользователя

**Response `200`:**
```json
{
  "reviews": [
    {
      "id": "uuid",
      "order_id": "uuid",
      "from_user_id": "uuid",
      "to_user_id": "uuid",
      "rating": 5,
      "comment": "Отлично!",
      "created_at": "2026-05-23T12:00:00Z"
    }
  ],
  "total": 15
}
```

---

## 15. Complaints — Жалобы

### `POST /api/v1/complaints` — Создать жалобу

**Request:**
```json
{
  "order_id": "uuid",
  "target_user_id": "uuid",
  "reason": "Описание проблемы"
}
```

### `GET /api/v1/complaints` — Список жалоб (admin, moderator)

### `PATCH /api/v1/complaints/{id}` — Обновить статус (admin, moderator)

**Request:**
```json
{
  "status": "resolved",
  "resolution": "Описание решения"
}
```

---

## 16. Admin — Администрирование

### `DELETE /api/v1/admin/users/{id}` — Удалить пользователя

Роль: **admin**.

### `PATCH /api/v1/admin/complaints/{id}` — Обработать жалобу

Роли: **moderator**, **admin**.

**Request:**
```json
{
  "status": "resolved",
  "resolution": "Жалоба рассмотрена, пользователь предупреждён"
}
```

---

## 17. Сводка WebSocket эндпоинтов

| Сервис | Gateway URL | Прямой URL | Параметры | События |
|--------|------------|-----------|-----------|---------|
| **Chat** | `/api/v1/chat/ws` | `ws://host:8085/ws` | `?token=JWT` | `message.new`, `typing`, `messages.read`, `pong`, `error` |
| **Notifications** | `/api/v1/notifications/ws` | `ws://host:8087/ws` | `?token=JWT` (gateway) или `?user_id=UUID` (direct) | `notification.new`, `notification.unread_count`, `notification.connected` |
| **Orders** | `/api/v1/orders/ws` | `ws://host:8083/ws` | `?token=JWT` | `order.created`, `order.updated`, `order.connected` |
| **Offers** | `/api/v1/offers/ws` | `ws://host:8084/ws` | `?token=JWT&order_id=UUID` | `offer.created`, `offer.updated`, `offer.countered`, `offer.connected` |

**Рекомендация для фронтенда:** использовать Gateway URL (`/api/v1/*/ws`), передавая JWT-токен в query-параметре `?token=...`.

---

## 18. Общая информация

### Формат ошибок

Все ошибки возвращаются в JSON:
```json
{
  "error": "краткое описание",
  "message": "подробное сообщение",
  "request_id": "uuid"
}
```

Ошибки валидации:
```json
{
  "errors": {
    "email": "некорректный формат email",
    "password": "обязательное поле"
  }
}
```

### HTTP-статусы

| Код | Описание |
|-----|----------|
| 200 | Успех |
| 201 | Создано |
| 400 | Неверный запрос / валидация |
| 401 | Не авторизован |
| 403 | Доступ запрещён |
| 404 | Не найдено |
| 409 | Конфликт |
| 422 | Ошибка валидации полей |
| 500 | Внутренняя ошибка сервера |

### Роли

| Роль | Права |
|------|-------|
| `user` | Базовая роль: создание заказов, чат, отзывы, жалобы |
| `master` | Отправка предложений, выполнение заказов |
| `moderator` | Обработка жалоб |
| `admin` | Всё выше + управление пользователями, категориями |

### Поток заказ↔оффер (основной сценарий)

```
1. Customer создаёт заказ:        POST /api/v1/orders
2. Masters видят заказ в ленте:   WS /api/v1/orders/ws → order.created
3. Master отправляет оффер:       POST /api/v1/offers
4. Customer видит оффер:          WS /api/v1/offers/ws → offer.created
5. Customer контр-предлагает:     POST /api/v1/offers/{id}/counter
6. Обе стороны видят переговоры:  WS /api/v1/offers/ws → offer.countered
7. Customer принимает оффер:      POST /api/v1/offers/{id}/accept
8. Статус заказа → assigned:      WS /api/v1/orders/ws → order.updated
9. Чат создаётся автоматически
10. Общение в чате:               WS /api/v1/chat/ws
11. Master выполняет → статус in_progress → completed
12. Customer оставляет отзыв:     POST /api/v1/reviews
```

### Доступные seed-пользователи (для разработки)

| Email | Пароль | Роли |
|-------|--------|------|
| `admin@example.com` | `admin123` | admin, user |
| `customer@example.com` | `password123` | user |
| `master@example.com` | `password123` | master, user |

---

## 15. Chat — Чаты

Все эндпоинты требуют авторизации. Один чат на один заказ (уникальный `order_id`).

### `GET /api/v1/chats` — Список чатов

**Response `200`:**
```json
{
  "chats": [
    {
      "id": "uuid",
      "order_id": "uuid",
      "customer_id": "uuid",
      "master_id": "uuid",
      "last_message": { "id": "uuid", "message": "...", "created_at": "..." },
      "unread_count": 2
    }
  ],
  "total": 8
}
```

### `POST /api/v1/chats` — Создать чат

**Request:**
```json
{
  "order_id": "uuid",
  "customer_id": "uuid",
  "master_id": "uuid"
}
```

**Важно:** Все три поля обязательны. Используйте `customer_id` из заказа и `master_id` из принятого оффера.

**Response `200`:**
```json
{
  "id": "uuid",
  "order_id": "uuid",
  "customer_id": "uuid",
  "master_id": "uuid",
  "created_at": "2026-05-24T11:14:16Z"
}
```

**Ошибки:**
- `400` — недействительный customer_id/master_id/order_id
- `409` — чат для этого заказа уже существует

### `GET /api/v1/chats/{id}` — Получить чат по ID

### `GET /api/v1/chats/{id}/messages?limit=50` — Сообщения чата

**Response `200`:**
```json
[
  {
    "id": "uuid",
    "chat_id": "uuid",
    "sender_id": "uuid",
    "message": "Здравствуйте!",
    "attachment_file_id": null,
    "created_at": "2026-05-24T12:30:00Z"
  }
]
```

### `POST /api/v1/chats/{id}/messages` — Отправить сообщение (REST)

**Request:**
```json
{
  "message": "Текст сообщения (макс. 4096 символов)",
  "attachment_file_id": "uuid (опционально)"
}
```

### `POST /api/v1/chats/{id}/read` — Отметить как прочитанное

---

## 16. Files — Файлы

Все эндпоинты требуют авторизации. Файлы хранятся в MinIO (S3).

### `POST /api/v1/files/upload` — Загрузить файл

**Content-Type:** `multipart/form-data`

**Поля формы:**
- `file` — бинарные данные файла
- `file_type` — одно из: `avatar`, `order_attachment`, `chat_attachment`, `document`

**Ограничения:**
- Макс. размер: 50 МБ
- Разрешённые MIME-типы: `image/jpeg`, `image/png`, `image/webp`, `image/gif`, `video/mp4`, `application/pdf`

**Response `200`:**
```json
{
  "id": "uuid",
  "owner_id": "uuid",
  "bucket": "diploma-files",
  "object_key": "...",
  "mime_type": "image/png",
  "size": 12345,
  "file_type": "avatar",
  "created_at": "2026-05-24T12:00:00Z"
}
```

### `GET /api/v1/files` — Список файлов пользователя

### `GET /api/v1/files/{id}` — Метаданные файла

### `GET /api/v1/files/{id}/download` — Скачать файл

Возвращает presigned URL для прямого скачивания из MinIO.

### `DELETE /api/v1/files/{id}` — Удалить файл

Доступно владельцу файла или админу.

---

## 17. Notifications — Уведомления

Все эндпоинты требуют авторизации.

### `GET /api/v1/notifications` — Список уведомлений

**Response `200`:**
```json
{
  "notifications": [
    {
      "id": "uuid",
      "user_id": "uuid",
      "type": "new_offer",
      "title": "Новый оффер",
      "body": "Мастер предложил цену...",
      "is_read": false,
      "data": {},
      "created_at": "2026-05-24T12:00:00Z"
    }
  ],
  "total": 39
}
```

### `GET /api/v1/notifications/unread-count` — Счётчик непрочитанных

**Response `200`:**
```json
{ "success": true, "data": { "count": 5 } }
```

### `POST /api/v1/notifications/read-all` — Отметить все прочитанными

### `POST /api/v1/notifications/{id}/read` — Отметить одно прочитанным

### `DELETE /api/v1/notifications/{id}` — Удалить уведомление

---

## 18. WebSocket — Real-time соединения

Все WebSocket-эндпоинты требуют аутентификацию через query-параметр `?token=JWT_TOKEN`.

| Эндпоинт | Назначение |
|----------|-----------|
| `ws://localhost:8080/api/v1/orders/ws?token=...` | Real-time лента заказов |
| `ws://localhost:8080/api/v1/offers/ws?order_id=UUID&token=...` | Офферы по конкретному заказу |
| `ws://localhost:8080/api/v1/chat/ws?token=...` | Чат-сообщения |
| `ws://localhost:8080/api/v1/notifications/ws?user_id=UUID&token=...` | Push-уведомления |

### Протокол (JSON-сообщения)

**Order feed:**
- Сервер → Клиент: `{"type":"order.connected"}` / `{"type":"order.created","order":{...}}` / `{"type":"order.updated","order":{...}}`

**Chat:**
- Клиент → Сервер: `{"type":"message.send","chat_id":"...","message":"..."}`
- Клиент → Сервер: `{"type":"typing.start","chat_id":"..."}` / `{"type":"typing.stop","chat_id":"..."}`
- Клиент → Сервер: `{"type":"messages.read","chat_id":"..."}`
- Сервер → Клиент: `{"type":"message.new","chat_id":"...","message":{...}}`

**Notifications:**
- Сервер → Клиент: `{"type":"notification.new","notification":{...}}` / `{"type":"notification.unread_count","count":N}`

---

## 19. Admin — Администрирование (дополнительно)

### `POST /api/v1/admin/users/{id}/ban` — Заблокировать пользователя

Требует роль `admin`.

### `POST /api/v1/admin/users/{id}/unban` — Разблокировать пользователя

Требует роль `admin`.

---

## 20. Инфраструктура (для справки)

| Компонент | Порт | URL |
|-----------|------|-----|
| API Gateway | 8080 | `http://localhost:8080` |
| Auth Service | 8081 | — |
| User Service | 8082 | — |
| Order Service | 8083 | — |
| Offer Service | 8084 | — |
| Chat Service | 8085 | — |
| File Service | 8086 | — |
| Notification Service | 8087 | — |
| Kafka UI | 8088 | `http://localhost:8088` |
| MinIO (S3) | 9000-9001 | `http://localhost:9001` (minioadmin/minioadmin) |
| Mailpit (SMTP dev) | 1025, 8025 | `http://localhost:8025` |
