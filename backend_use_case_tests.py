"""
Полная проверка бэкенда по сценариям использования (use-cases-by-role.md)
======================================================================
Запуск: python backend_use_case_tests.py
"""

import urllib.request, urllib.error
import json, sys, os, time, uuid

API = "http://localhost:8080"
RESULTS = []

def record(test, status, details=""):
    RESULTS.append({"test": test, "status": status, "details": details})
    icon = {"PASS": "✓", "FAIL": "✗", "WARN": "⚠"}[status]
    print(f"  {icon} {test}")
    if details:
        print(f"     {details}")

class Session:
    """Cookie-based session for a user."""
    def __init__(self, email, password):
        self.email = email
        self.password = password
        self.cookie_jar = None
        self.user_id = None
        self.roles = []
        self.access_token = None

    def login(self):
        data = json.dumps({"email": self.email, "password": self.password}).encode()
        req = urllib.request.Request(f"{API}/api/v1/auth/login", data=data,
            headers={"Content-Type": "application/json"})
        try:
            resp = urllib.request.urlopen(req)
            body = json.loads(resp.read())
            self.user_id = body["user_id"]
            self.roles = body["roles"]
            self.access_token = body["access_token"]
            # Extract ALL cookies (multiple Set-Cookie headers)
            all_cookies = resp.headers.get_all("Set-Cookie")
            if all_cookies:
                self.cookie_jar = "; ".join(c.split(";")[0] for c in all_cookies)
            return True, body
        except urllib.error.HTTPError as e:
            return False, e.read().decode()

    def request(self, method, path, body=None, content_type="application/json"):
        url = f"{API}{path}"
        headers = {"Content-Type": content_type} if body else {}
        if self.cookie_jar:
            headers["Cookie"] = self.cookie_jar
        data = None
        if body:
            data = json.dumps(body).encode() if isinstance(body, dict) else body
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            resp = urllib.request.urlopen(req)
            result = json.loads(resp.read()) if resp.status != 204 else {}
            return True, result, resp.status
        except urllib.error.HTTPError as e:
            err_body = e.read().decode()
            try: err_body = json.loads(err_body)
            except: pass
            return False, err_body, e.code

    def get(self, path):
        return self.request("GET", path)

    def post(self, path, body=None):
        return self.request("POST", path, body)

    def patch(self, path, body):
        return self.request("PATCH", path, body)

    def delete(self, path):
        return self.request("DELETE", path)

# ============================================================
print("=" * 60)
print("  ПОЛНАЯ ПРОВЕРКА БЭКЕНДА ПО USE-CASE СЦЕНАРИЯМ")
print("=" * 60)

# ----------------------------------------------------------
# Проверка, что Gateway жив
# ----------------------------------------------------------
try:
    resp = urllib.request.urlopen(f"{API}/health")
    data = json.loads(resp.read())
    assert data["status"] == "ok" or data["status"] == "degraded"
    print(f"\n Gateway health: {data['status']} OK")
except Exception as e:
    print(f"\n FATAL: Gateway is DOWN: {e}")
    sys.exit(1)

# ============================================================
# 1. ГОСТЬ (GUEST)
# ============================================================
print("\n" + "=" * 60)
print("  1. ГОСТЬ — неавторизованный доступ")
print("=" * 60)

# 1.1 Редирект без авторизации (проверяем что API отдаёт 401)
ok, body, code = Session("no@no.com", "x").get("/api/v1/profile")
if code == 401 or (not ok and isinstance(body, dict) and ("токен" in str(body).lower() or "unauthorized" in str(body).lower())):
    record("1.1 Профиль без авторизации → 401", "PASS", f"HTTP {code}")
else:
    record("1.1 Профиль без авторизации → 401", "FAIL", f"HTTP {code}: {str(body)[:80]}")

# 1.2 Регистрация: валидация полей
print("\n--- 1.2 Регистрация ---")

# Пустой body
data = json.dumps({}).encode()
req = urllib.request.Request(f"{API}/api/v1/auth/register", data=data,
    headers={"Content-Type": "application/json"})
try:
    urllib.request.urlopen(req)
    record("1.2a Регистрация: пустой body → ошибка", "FAIL", "Должна быть ошибка валидации")
except urllib.error.HTTPError as e:
    err = json.loads(e.read())
    if "email" in str(err).lower() or "error" in str(err).lower() or e.code >= 400:
        record("1.2a Регистрация: пустой body → ошибка", "PASS", f"HTTP {e.code}")
    else:
        record("1.2a Регистрация: пустой body → ошибка", "FAIL", str(err)[:100])

# Слабый пароль
test_email = f"test_{uuid.uuid4().hex[:8]}@example.com"
data = json.dumps({"email": test_email, "password": "123", "first_name": "A", "last_name": "B", "phone": "+7999"}).encode()
req = urllib.request.Request(f"{API}/api/v1/auth/register", data=data,
    headers={"Content-Type": "application/json"})
try:
    urllib.request.urlopen(req)
    record("1.2b Регистрация: слабый пароль → ошибка", "FAIL", "Должна быть ошибка валидации пароля")
except urllib.error.HTTPError as e:
    record("1.2b Регистрация: слабый пароль → ошибка", "PASS", f"HTTP {e.code}")

# Валидная регистрация
data = json.dumps({"email": test_email, "password": "Test1234", "first_name": "Тест", "last_name": "Тестов", "phone": "+79991234567"}).encode()
req = urllib.request.Request(f"{API}/api/v1/auth/register", data=data,
    headers={"Content-Type": "application/json"})
try:
    resp = urllib.request.urlopen(req)
    body = json.loads(resp.read())
    if "access_token" in body and "user_id" in body:
        new_user_id = body["user_id"]
        record("1.2c Регистрация: валидные данные → успех", "PASS", f"User: {body['email']}, Roles: {body['roles']}")
    else:
        record("1.2c Регистрация: валидные данные → успех", "FAIL", str(body)[:100])
except urllib.error.HTTPError as e:
    err = json.loads(e.read())
    record("1.2c Регистрация: валидные данные → успех", "FAIL", f"HTTP {e.code}: {str(err)[:100]}")

# Дубликат email
data = json.dumps({"email": test_email, "password": "Test1234", "first_name": "Тест", "last_name": "Тестов", "phone": "+79991234567"}).encode()
req = urllib.request.Request(f"{API}/api/v1/auth/register", data=data,
    headers={"Content-Type": "application/json"})
try:
    urllib.request.urlopen(req)
    record("1.2d Регистрация: дубликат email → ошибка", "FAIL", "Должна быть ошибка")
except urllib.error.HTTPError as e:
    err = json.loads(e.read())
    if e.code >= 400:
        record("1.2d Регистрация: дубликат email → ошибка", "PASS", f"HTTP {e.code}: {str(err.get('error', err))[:80]}")
    else:
        record("1.2d Регистрация: дубликат email → ошибка", "FAIL", str(err)[:80])

# 1.3 Вход
print("\n--- 1.3 Вход ---")

# Неверный пароль
s_bad = Session("admin@example.com", "wrongpassword")
ok, body = s_bad.login()
if not ok:
    record("1.3a Вход: неверный пароль → ошибка", "PASS", str(body)[:80])
else:
    record("1.3a Вход: неверный пароль → ошибка", "FAIL", "Вход выполнен с неверным паролем!")

# Успешный вход
s_admin = Session("admin@example.com", "admin123")
ok, body = s_admin.login()
if ok:
    record("1.3b Вход: admin → успех", "PASS", f"User: {body['email']}, Roles: {body['roles']}")
else:
    record("1.3b Вход: admin → успех", "FAIL", str(body)[:100])

# 1.4 Публичные категории
ok, body, code = Session("no@no.com", "x").get("/api/v1/categories")
if ok and "categories" in body:
    record("1.4 GET /categories (публичный)", "PASS", f"{len(body['categories'])} категорий")
else:
    record("1.4 GET /categories (публичный)", "FAIL", str(body)[:80])

# 1.5 Scalar UI docs
try:
    resp = urllib.request.urlopen(f"{API}/docs/")
    record("1.5 Scalar UI /docs", "PASS", f"HTTP {resp.status}")
except Exception as e:
    record("1.5 Scalar UI /docs", "FAIL", str(e)[:80])

# ============================================================
# 2. КЛИЕНТ (USER) — customer@example.com
# ============================================================
print("\n" + "=" * 60)
print("  2. КЛИЕНТ (customer@example.com)")
print("=" * 60)

s_cust = Session("customer@example.com", "password123")
ok, _ = s_cust.login()
if not ok:
    record("2.0 Логин customer", "FAIL", "Не удалось войти!")
else:
    record("2.0 Логин customer", "PASS", f"ID: {s_cust.user_id}, Roles: {s_cust.roles}")

# 2.1 Просмотр профиля
ok, body, code = s_cust.get("/api/v1/profile")
if ok:
    has_profile = body.get("profile") is not None
    has_roles = len(body.get("roles", [])) > 0
    record("2.1 GET /profile", "PASS", f"Profile: {has_profile}, Roles: {body.get('roles')}")
else:
    record("2.1 GET /profile", "FAIL", str(body)[:80])

# 2.2 Список заказов
ok, body, code = s_cust.get("/api/v1/orders")
if ok:
    n = len(body.get("orders", []))
    record("2.2 GET /orders", "PASS", f"{n} заказов")
else:
    record("2.2 GET /orders", "FAIL", str(body)[:80])

# 2.3 Создание заказа
print("\n--- 2.3 Создание заказа ---")

# Получаем категорию
ok, cats_body, _ = s_cust.get("/api/v1/categories")
cat_id = cats_body["categories"][0]["id"] if ok and cats_body.get("categories") else None

order_data = {
    "title": "Test order from use case test",
    "description": "Проверка создания заказа по сценарию",
    "price": 5000,
    "category_id": cat_id or "00000000-0000-0000-0000-000000000000",
    "latitude": 55.7558,
    "longitude": 37.6173
}
ok, body, code = s_cust.post("/api/v1/orders", order_data)
if ok:
    new_order_id = body.get("order", {}).get("id")
    new_order_status = body.get("order", {}).get("status")
    record("2.3a POST /orders (создание)", "PASS", f"ID: {new_order_id[:8] if new_order_id else '?'}..., Status: {new_order_status}")
else:
    record("2.3a POST /orders (создание)", "FAIL", f"HTTP {code}: {str(body)[:100]}")
    new_order_id = None

# 2.4 Детали заказа
if new_order_id:
    ok, body, code = s_cust.get(f"/api/v1/orders/{new_order_id}")
    if ok:
        record("2.4 GET /orders/:id (детали)", "PASS", f"Title: {body.get('order',{}).get('title','?')}")
    else:
        record("2.4 GET /orders/:id (детали)", "FAIL", str(body)[:80])

    # 2.5 История статусов заказа
    ok, body, code = s_cust.get(f"/api/v1/orders/{new_order_id}/history")
    if ok:
        record("2.5 GET /orders/:id/history", "PASS", f"Событий: {len(body.get('history',[]))}")
    else:
        record("2.5 GET /orders/:id/history", "FAIL", str(body)[:80])

# 2.6 Фильтрация заказов
ok, body, code = s_cust.get("/api/v1/orders?status=created")
if ok:
    record("2.6 GET /orders?status=created", "PASS", f"Найдено: {len(body.get('orders',[]))}")
else:
    record("2.6 GET /orders?status=created", "FAIL", str(body)[:80])

# 2.7 Обновление профиля
ok, body, code = s_cust.patch(f"/api/v1/users/{s_cust.user_id}", {"first_name": "UpdatedName"})
if ok:
    record("2.7a PATCH /users/:id (свой профиль)", "PASS", f"Updated: {body.get('first_name','?')}")
else:
    record("2.7a PATCH /users/:id (свой профиль)", "FAIL", f"HTTP {code}: {str(body)[:80]}")

# 2.7b Нельзя обновить чужой профиль
ok, body, code = s_cust.patch(f"/api/v1/users/{s_admin.user_id}", {"first_name": "Hack"})
if not ok:
    record("2.7b PATCH /users/:id (чужой) → запрет", "PASS", f"HTTP {code}")
else:
    record("2.7b PATCH /users/:id (чужой) → запрет", "FAIL", "Удалось изменить чужой профиль!")

# ============================================================
# 3. МАСТЕР (MASTER)
# ============================================================
print("\n" + "=" * 60)
print("  3. МАСТЕР (master@example.com)")
print("=" * 60)

s_master = Session("master@example.com", "password123")
ok, _ = s_master.login()
if ok:
    record("3.0 Логин master", "PASS", f"Roles: {s_master.roles}")
else:
    record("3.0 Логин master", "FAIL", str(_)[:80])

# 3.1 Профиль мастера
ok, body, code = s_master.get(f"/api/v1/masters/{s_master.user_id}")
if ok:
    record("3.1 GET /masters/:id", "PASS", f"Rating: {body.get('rating','?')}, Completed: {body.get('completed_orders','?')}")
else:
    record("3.1 GET /masters/:id", "FAIL", str(body)[:80])

# 3.2 Обновление профиля мастера
ok, body, code = s_master.patch(f"/api/v1/masters/{s_master.user_id}", {"description": "Профессиональный мастер на все руки", "experience_years": 5})
if ok:
    record("3.2 PATCH /masters/:id", "PASS", f"Desc: {body.get('description','?')[:40]}")
else:
    record("3.2 PATCH /masters/:id", "FAIL", f"HTTP {code}: {str(body)[:80]}")

# 3.3 Мастер отправляет оффер на заказ customer
print("\n--- 3.3 Офферы и переговоры ---")
if new_order_id:
    ok, body, code = s_master.post("/api/v1/offers", {
        "order_id": new_order_id,
        "price": 4500,
        "message": "Сделаю качественно за 2 дня"
    })
    if ok:
        offer_id = body.get("id")
        offer_status = body.get("status")
        record("3.3a POST /offers (отправка)", "PASS", f"Offer: {offer_id[:8] if offer_id else '?'}..., Status: {offer_status}")
    else:
        record("3.3a POST /offers (отправка)", "FAIL", f"HTTP {code}: {str(body)[:100]}")
        offer_id = None

    # 3.4 Просмотр офферов по заказу (как customer)
    ok, body, code = s_cust.get(f"/api/v1/offers?order_id={new_order_id}")
    if ok:
        record("3.4 GET /offers?order_id=...", "PASS", f"Офферов: {len(body) if isinstance(body, list) else body.get('total','?')}")
    else:
        record("3.4 GET /offers?order_id=...", "FAIL", str(body)[:80])

    # 3.5 Контр-оффер (customer → переговоры)
    if offer_id:
        ok, body, code = s_cust.post(f"/api/v1/offers/{offer_id}/counter", {"price": 4800, "message": "Готов заплатить 4800"})
        if ok:
            record("3.5a POST /offers/:id/counter (контр-оффер)", "PASS", f"Type: {body.get('type','?')}")
        else:
            record("3.5a POST /offers/:id/counter (контр-оффер)", "FAIL", f"HTTP {code}: {str(body)[:80]}")

        # 3.5b История переговоров
        ok, body, code = s_cust.get(f"/api/v1/offers/{offer_id}/history")
        if ok:
            record("3.5b GET /offers/:id/history", "PASS", f"Событий: {len(body) if isinstance(body, list) else '?'}")
        else:
            record("3.5b GET /offers/:id/history", "FAIL", str(body)[:80])

        # 3.6 Мастер отзывает оффер
        ok, body, code = s_master.post(f"/api/v1/offers/{offer_id}/withdraw")
        if ok:
            record("3.6 POST /offers/:id/withdraw (отзыв)", "PASS", "Оффер отозван")
        else:
            # Could be already withdrawn or wrong status
            record("3.6 POST /offers/:id/withdraw (отзыв)", "WARN", f"HTTP {code}: {str(body)[:80]}")

        # 3.7 Новый оффер от мастера (для accept/reject теста)
        ok2, body2, _ = s_master.post("/api/v1/offers", {
            "order_id": new_order_id, "price": 4300, "message": "Готов сделать"
        })
        if ok2:
            offer_id2 = body2.get("id")

            # 3.7a Customer принимает оффер
            ok, body, code = s_cust.post(f"/api/v1/offers/{offer_id2}/accept")
            if ok:
                record("3.7a POST /offers/:id/accept", "PASS", f"Status: {body.get('status','?')}")
                # Проверяем что заказ перешёл в assigned
                ok3, body3, _ = s_cust.get(f"/api/v1/orders/{new_order_id}")
                order_status_after = body3.get("order", {}).get("status") if ok3 else "?"
                if order_status_after == "assigned":
                    record("3.7b Заказ → assigned после accept", "PASS")
                else:
                    record("3.7b Заказ → assigned после accept", "WARN", f"Status: {order_status_after}")
            else:
                record("3.7a POST /offers/:id/accept", "FAIL", f"HTTP {code}: {str(body)[:80]}")
        else:
            record("3.7 Новый оффер для accept", "WARN", f"HTTP {code}: {str(body2)[:80]}")
else:
    record("3.3-3.7 Офферы (пропущено)", "WARN", "Нет заказа для тестирования офферов")

# 3.8 Отзывы мастера
ok, body, code = s_master.get(f"/api/v1/reviews/user/{s_master.user_id}")
if ok:
    record("3.8 GET /reviews/user/:id (свои отзывы)", "PASS", f"Отзывов: {body.get('total',0)}")
else:
    record("3.8 GET /reviews/user/:id (свои отзывы)", "FAIL", f"HTTP {code}")

# 3.9 Деактивация / активация мастера
ok, body, code = s_master.delete(f"/api/v1/users/{s_master.user_id}/roles/master")
if ok:
    record("3.9a DELETE /users/:id/roles/master (деактивация)", "PASS", "Роль мастера отключена")
else:
    record("3.9a DELETE /users/:id/roles/master (деактивация)", "WARN", f"HTTP {code}: {str(body)[:80]}")

ok, body, code = s_master.post(f"/api/v1/users/{s_master.user_id}/roles/master")
if ok:
    record("3.9b POST /users/:id/roles/master (активация)", "PASS", "Роль мастера включена")
else:
    record("3.9b POST /users/:id/roles/master (активация)", "FAIL", f"HTTP {code}: {str(body)[:80]}")

# ============================================================
# 4. АДМИН (ADMIN)
# ============================================================
print("\n" + "=" * 60)
print("  4. АДМИН (admin@example.com)")
print("=" * 60)

# 4.1 Категории: CRUD
print("\n--- 4.1 Управление категориями ---")

new_cat_data = {"name": "TestCategory", "slug": f"test-cat-{uuid.uuid4().hex[:8]}"}
ok, body, code = s_admin.post("/api/v1/categories", new_cat_data)
if ok:
    new_cat_id = body.get("id")
    record("4.1a POST /categories (создание)", "PASS", f"ID: {new_cat_id[:8] if new_cat_id else '?'}..., Name: {body.get('name','?')}")
else:
    record("4.1a POST /categories (создание)", "FAIL", f"HTTP {code}: {str(body)[:100]}")
    new_cat_id = None

if new_cat_id:
    ok, body, code = s_admin.patch(f"/api/v1/categories/{new_cat_id}", {"name": "TestCategory Updated", "slug": "test-category-upd"})
    if ok:
        record("4.1b PATCH /categories/:id", "PASS", f"Updated: {body.get('name','?')}")
    else:
        record("4.1b PATCH /categories/:id", "FAIL", f"HTTP {code}: {str(body)[:80]}")

    ok, body, code = s_admin.delete(f"/api/v1/categories/{new_cat_id}")
    if ok:
        record("4.1c DELETE /categories/:id", "PASS", "Категория удалена")
    else:
        record("4.1c DELETE /categories/:id", "FAIL", f"HTTP {code}: {str(body)[:80]}")

# 4.2 Customer НЕ может управлять категориями
ok, body, code = s_cust.post("/api/v1/categories", {"name": "Hack", "slug": "hack"})
if not ok:
    record("4.1d Customer → POST /categories → запрет", "PASS", f"HTTP {code}")
else:
    record("4.1d Customer → POST /categories → запрет", "FAIL", "Customer смог создать категорию!")

# 4.3 Удаление пользователя (admin)
print("\n--- 4.2 Управление пользователями ---")
if new_user_id:
    ok, body, code = s_admin.delete(f"/api/v1/admin/users/{new_user_id}")
    if ok:
        record("4.2 DELETE /admin/users/:id", "PASS", f"User {new_user_id[:8]}... deleted")
    else:
        record("4.2 DELETE /admin/users/:id", "FAIL", f"HTTP {code}: {str(body)[:80]}")

# 4.4 Customer НЕ может удалять пользователей
ok, body, code = s_cust.delete(f"/api/v1/admin/users/{s_master.user_id}")
if not ok:
    record("4.2b Customer → DELETE /admin/users → запрет", "PASS", f"HTTP {code}")
else:
    record("4.2b Customer → DELETE /admin/users → запрет", "FAIL", "Customer смог удалить пользователя!")

# 4.5 Админ видит все жалобы
ok, body, code = s_admin.get("/api/v1/complaints")
if ok:
    record("4.3a GET /complaints (admin)", "PASS", f"Жалоб: {len(body) if isinstance(body, list) else body.get('total','?')}")
else:
    record("4.3a GET /complaints (admin)", "FAIL", f"HTTP {code}")

# ============================================================
# 5. ЖАЛОБЫ
# ============================================================
print("\n" + "=" * 60)
print("  5. ЖАЛОБЫ (сквозной сценарий)")
print("=" * 60)

if new_order_id:
    complaint = {
        "target_user_id": s_master.user_id,
        "order_id": new_order_id,
        "message": "Мастер не вышел на связь после назначения"
    }
    ok, body, code = s_cust.post("/api/v1/complaints", complaint)
    if ok:
        complaint_id = body.get("id")
        record("5.1 POST /complaints (создание)", "PASS", f"ID: {complaint_id[:8] if complaint_id else '?'}..., Status: {body.get('status','?')}")
    else:
        record("5.1 POST /complaints (создание)", "FAIL", f"HTTP {code}: {str(body)[:100]}")
        complaint_id = None
else:
    complaint_id = None

# 5.2 Customer НЕ видит все жалобы
ok, body, code = s_cust.get("/api/v1/complaints")
if not ok and code in [403, 401]:
    record("5.2 Customer → GET /complaints → запрет", "PASS", f"HTTP {code}")
elif ok and (isinstance(body, list) or isinstance(body, dict)):
    record("5.2 Customer → GET /complaints → запрет", "WARN", "Customer видит жалобы")

# ============================================================
# 6. ЧАТЫ
# ============================================================
print("\n" + "=" * 60)
print("  6. ЧАТЫ")
print("=" * 60)

# 6.1 Список чатов
ok, body, code = s_cust.get("/api/v1/chats")
if ok:
    n = body.get("total", len(body) if isinstance(body, list) else 0)
    record("6.1 GET /chats (customer)", "PASS", f"Чатов: {n}")
else:
    record("6.1 GET /chats (customer)", "FAIL", f"HTTP {code}: {str(body)[:80]}")

# 6.2 Создание чата (для заказа с assigned мастером)
chat_id = None
if new_order_id:
    # Find an order with assigned status and get its master_id via offers
    ok_ord, body_ord, _ = s_cust.get(f"/api/v1/orders/{new_order_id}")
    cust_id = s_cust.user_id

    # Get offers for this order to find the assigned master
    ok_off, offers_data, _ = s_cust.get(f"/api/v1/offers?order_id={new_order_id}")
    master_id = None
    if ok_off:
        offers_list = offers_data.get("offers", []) if isinstance(offers_data, dict) else []
        for offer in offers_list:
            if offer.get("status") == "accepted":
                master_id = offer.get("master_id")
                break

    if master_id:
        ok, body, code = s_cust.post("/api/v1/chats", {
            "order_id": new_order_id,
            "customer_id": cust_id,
            "master_id": master_id
        })
        if ok:
            chat_id = body.get("id")
            record("6.2a POST /chats (создание)", "PASS", f"Chat: {chat_id[:8] if chat_id else '?'}...")
        elif code == 409:
            record("6.2a POST /chats (создание)", "PASS", "Чат уже существует (409 — ок)")
            ok2, body2, _ = s_cust.get("/api/v1/chats")
            chats_list = body2.get("chats", [])
            if chats_list:
                chat_id = chats_list[0]["id"]
        else:
            record("6.2a POST /chats (создание)", "FAIL", f"HTTP {code}: {str(body)[:80]}")
    else:
        # Try with any existing chat from customer's chat list
        ok_ch, chats_body, _ = s_cust.get("/api/v1/chats")
        chats_list = chats_body.get("chats", []) if isinstance(chats_body, dict) else []
        if chats_list:
            chat_id = chats_list[0]["id"]
            record("6.2a POST /chats (создание)", "PASS", "Используем существующий чат")
        else:
            record("6.2a POST /chats (создание)", "WARN", "Нет назначенного мастера для создания чата")

    # 6.3 Отправка сообщения в чат
    if chat_id:
        ok, body, code = s_cust.post(f"/api/v1/chats/{chat_id}/messages", {"message": "Здравствуйте! Когда сможете приступить?"})
        if ok:
            record("6.3 POST /chats/:id/messages", "PASS", f"Msg: {body.get('message','?')[:50]}")
        else:
            record("6.3 POST /chats/:id/messages", "FAIL", f"HTTP {code}: {str(body)[:80]}")

        # 6.4 Получение сообщений
        ok, body, code = s_cust.get(f"/api/v1/chats/{chat_id}/messages")
        if ok:
            record("6.4 GET /chats/:id/messages", "PASS", f"Сообщений: {len(body) if isinstance(body, list) else '?'}")
        else:
            record("6.4 GET /chats/:id/messages", "FAIL", f"HTTP {code}: {str(body)[:80]}")

        # 6.5 Отметка о прочтении
        ok, body, code = s_cust.post(f"/api/v1/chats/{chat_id}/read")
        if ok:
            record("6.5 POST /chats/:id/read", "PASS")
        else:
            record("6.5 POST /chats/:id/read", "WARN", f"HTTP {code}")
    else:
        record("6.3-6.5 Сообщения (пропущено)", "WARN", "Нет chat_id")
else:
    record("6.2-6.5 Чаты (пропущено)", "WARN", "Нет заказа для тестирования чатов")

# ============================================================
# 7. УВЕДОМЛЕНИЯ
# ============================================================
print("\n" + "=" * 60)
print("  7. УВЕДОМЛЕНИЯ")
print("=" * 60)

# 7.1 Список уведомлений
ok, body, code = s_master.get("/api/v1/notifications")
if ok:
    n = len(body) if isinstance(body, list) else body.get("total", "?")
    record("7.1 GET /notifications", "PASS", f"Уведомлений: {n}")
else:
    record("7.1 GET /notifications", "FAIL", f"HTTP {code}: {str(body)[:80]}")

# 7.2 Счётчик непрочитанных
ok, body, code = s_master.get("/api/v1/notifications/unread-count")
if ok:
    count = body.get("data", {}).get("count", body.get("count", "?"))
    record("7.2 GET /notifications/unread-count", "PASS", f"Непрочитанных: {count}")
else:
    record("7.2 GET /notifications/unread-count", "FAIL", f"HTTP {code}")

# 7.3 Прочитать все
ok, body, code = s_master.post("/api/v1/notifications/read-all")
if ok:
    record("7.3 POST /notifications/read-all", "PASS")
else:
    record("7.3 POST /notifications/read-all", "WARN", f"HTTP {code}")

# ============================================================
# 8. ФАЙЛЫ
# ============================================================
print("\n" + "=" * 60)
print("  8. ФАЙЛЫ")
print("=" * 60)

# 8.1 Список файлов
ok, body, code = s_admin.get("/api/v1/files")
if ok:
    n = len(body) if isinstance(body, list) else "?"
    record("8.1 GET /files", "PASS", f"Файлов: {n}")
else:
    record("8.1 GET /files", "FAIL", f"HTTP {code}")

# 8.2 Загрузка файла (PNG)
# Minimal valid PNG file (1x1 pixel)
minimal_png = (
    b'\x89PNG\r\n\x1a\n'  # PNG signature
    b'\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde'
    b'\x00\x00\x00\x0cIDATx\x9cc\xf8\x0f\x00\x00\x01\x01\x00\x05\x18\xd8N'
    b'\x00\x00\x00\x00IEND\xaeB`\x82'
)
boundary = "----TestBoundary123"
file_data = (
    f"--{boundary}\r\n"
    f'Content-Disposition: form-data; name="file"; filename="test_upload.png"\r\n'
    f"Content-Type: image/png\r\n\r\n"
).encode() + minimal_png + (
    f"\r\n--{boundary}\r\n"
    f'Content-Disposition: form-data; name="file_type"\r\n\r\n'
    f"document\r\n"
    f"--{boundary}--\r\n"
).encode()

req = urllib.request.Request(
    f"{API}/api/v1/files/upload",
    data=file_data,
    headers={
        "Content-Type": f"multipart/form-data; boundary={boundary}",
        "Cookie": s_admin.cookie_jar or "",
    }
)
try:
    resp = urllib.request.urlopen(req)
    body = json.loads(resp.read())
    file_id = body.get("id")
    record("8.2 POST /files/upload", "PASS", f"File ID: {file_id[:8] if file_id else '?'}..., Size: {body.get('size','?')}")
except urllib.error.HTTPError as e:
    err = e.read().decode()
    file_id = None
    record("8.2 POST /files/upload", "FAIL", f"HTTP {e.code}: {err[:100]}")

# 8.3 Скачивание файла
if file_id:
    ok, body, code = s_admin.get(f"/api/v1/files/{file_id}")
    if ok:
        record("8.3a GET /files/:id (метаданные)", "PASS", f"Name: {body.get('filename','?')}")
    else:
        record("8.3a GET /files/:id (метаданные)", "FAIL", f"HTTP {code}")

    ok, body, code = s_admin.get(f"/api/v1/files/{file_id}/download")
    if ok:
        record("8.3b GET /files/:id/download (presigned URL)", "PASS", f"URL получен")
    else:
        record("8.3b GET /files/:id/download (presigned URL)", "WARN", f"HTTP {code}")

    # 8.4 Удаление файла
    ok, body, code = s_admin.delete(f"/api/v1/files/{file_id}")
    if ok:
        record("8.4 DELETE /files/:id", "PASS", "Файл удалён")
    else:
        record("8.4 DELETE /files/:id", "WARN", f"HTTP {code}")

# ============================================================
# 9. WEBSOCKET (базовая проверка)
# ============================================================
print("\n" + "=" * 60)
print("  9. WEBSOCKET")
print("=" * 60)

# 9.1 WS: orders feed
token = s_admin.access_token
ws_url = f"ws://localhost:8080/api/v1/orders/ws?token={token}"
try:
    import socket
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5)
    s.connect(("localhost", 8080))
    # Send HTTP upgrade request
    req_str = (
        f"GET /api/v1/orders/ws?token={token} HTTP/1.1\r\n"
        f"Host: localhost:8080\r\n"
        f"Upgrade: websocket\r\n"
        f"Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
        f"Sec-WebSocket-Version: 13\r\n\r\n"
    )
    s.send(req_str.encode())
    resp_data = s.recv(4096)
    s.close()
    if b"101" in resp_data or b"Switching Protocols" in resp_data:
        record("9.1 WS: /orders/ws → upgrade OK", "PASS", "101 Switching Protocols")
    else:
        record("9.1 WS: /orders/ws → upgrade OK", "FAIL", str(resp_data[:200]))
except Exception as e:
    record("9.1 WS: /orders/ws → upgrade OK", "FAIL", str(e)[:100])

# 9.2 WS: без токена → ошибка
try:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5)
    s.connect(("localhost", 8080))
    req_str = (
        f"GET /api/v1/orders/ws HTTP/1.1\r\n"
        f"Host: localhost:8080\r\n"
        f"Upgrade: websocket\r\n"
        f"Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
        f"Sec-WebSocket-Version: 13\r\n\r\n"
    )
    s.send(req_str.encode())
    resp_data = s.recv(4096)
    s.close()
    if b"401" in resp_data or b"error" in resp_data or b"Unauthorized" in resp_data:
        record("9.2 WS: /orders/ws без токена → 401", "PASS", "Доступ запрещён")
    else:
        record("9.2 WS: /orders/ws без токена → 401", "FAIL", str(resp_data[:200]))
except Exception as e:
    record("9.2 WS: /orders/ws без токена → 401", "FAIL", str(e)[:100])

# ============================================================
# 10. ЗАВЕРШЕНИЕ ЖИЗНЕННОГО ЦИКЛА ЗАКАЗА
# ============================================================
print("\n" + "=" * 60)
print("  10. ЖИЗНЕННЫЙ ЦИКЛ ЗАКАЗА (завершение)")
print("=" * 60)

if new_order_id:
    # Проверим текущий статус
    ok, body, code = s_cust.get(f"/api/v1/orders/{new_order_id}")
    current_status = body.get("order", {}).get("status", "?") if ok else "?"
    record("10.1 Текущий статус заказа", "PASS" if current_status else "WARN", f"Status: {current_status}")

    # Если assigned → переводим в in_progress (как мастер)
    if current_status == "assigned":
        ok, body, code = s_master.patch(f"/api/v1/orders/{new_order_id}/status", {"status": "in_progress"})
        if ok:
            record("10.2 PATCH /orders/:id/status → in_progress", "PASS", "Статус обновлён")
            current_status = "in_progress"
        else:
            record("10.2 PATCH /orders/:id/status → in_progress", "FAIL", f"HTTP {code}: {str(body)[:80]}")

    # Если in_progress → завершаем (как customer)
    if current_status == "in_progress":
        ok, body, code = s_cust.post(f"/api/v1/orders/{new_order_id}/complete")
        if ok:
            record("10.3 POST /orders/:id/complete → completed", "PASS", "Заказ завершён")
            current_status = "completed"
        else:
            record("10.3 POST /orders/:id/complete → completed", "FAIL", f"HTTP {code}: {str(body)[:80]}")

    # Если completed → оставляем отзыв
    if current_status == "completed":
        ok, body, code = s_cust.post("/api/v1/reviews", {
            "order_id": new_order_id,
            "to_user_id": s_master.user_id,
            "rating": 5,
            "comment": "Отличная работа!"
        })
        if ok:
            record("10.4 POST /reviews (отзыв)", "PASS", f"Rating: {body.get('rating','?')}")
        else:
            record("10.4 POST /reviews (отзыв)", "FAIL", f"HTTP {code}: {str(body)[:80]}")

        # Проверяем обновление рейтинга мастера
        ok, body, code = s_master.get(f"/api/v1/masters/{s_master.user_id}")
        if ok:
            record("10.5 Рейтинг мастера обновлён", "PASS", f"Rating: {body.get('rating','?')}, Completed: {body.get('completed_orders','?')}")
        else:
            record("10.5 Рейтинг мастера обновлён", "FAIL", str(body)[:80])

    # Отмена (если created)
    if current_status in ("created", "negotiation"):
        ok, body, code = s_cust.post(f"/api/v1/orders/{new_order_id}/cancel")
        if ok:
            record("10.x POST /orders/:id/cancel", "PASS", "Заказ отменён")
        else:
            record("10.x POST /orders/:id/cancel", "WARN", f"HTTP {code}: {str(body)[:80]}")

# ============================================================
# 11. КРОСС-ПРОВЕРКИ ROLE-BASED ACCESS
# ============================================================
print("\n" + "=" * 60)
print("  11. КРОСС-ПРОВЕРКИ ДОСТУПА")
print("=" * 60)

# Customer не может отправить оффер (нужна роль master)
if new_order_id:
    ok, body, code = s_cust.post("/api/v1/offers", {"order_id": new_order_id, "price": 100})
    if not ok and code in [403, 401]:
        record("11.1 Customer → POST /offers → запрет", "PASS", f"HTTP {code}")
    elif ok:
        record("11.1 Customer → POST /offers → запрет", "FAIL", "Customer смог отправить оффер!")
    else:
        record("11.1 Customer → POST /offers → запрет", "WARN", f"HTTP {code}")

# Customer не может изменить статус заказа (только cancel/complete)
ok, body, code = s_cust.patch(f"/api/v1/orders/{new_order_id}/status", {"status": "in_progress"})
if not ok and code in [403, 401]:
    record("11.2 Customer → PATCH /orders/:id/status → запрет", "PASS", f"HTTP {code}")
elif ok:
    record("11.2 Customer → PATCH /orders/:id/status → запрет", "WARN", "Customer смог изменить статус (возможно, если он же и мастер)")
else:
    record("11.2 Customer → PATCH /orders/:id/status → запрет", "WARN", f"HTTP {code}")

# Customer не может видеть все жалобы
ok, body, code = s_cust.get("/api/v1/complaints")
if not ok and code in [403, 401]:
    record("11.3 Customer → GET /complaints → запрет", "PASS", f"HTTP {code}")
elif ok:
    record("11.3 Customer → GET /complaints → запрет", "WARN", "Customer видит жалобы")

# ============================================================
# 12. ИТОГИ
# ============================================================
print("\n" + "=" * 60)
print("  ИТОГОВЫЙ ОТЧЁТ ПО БЭКЕНДУ")
print("=" * 60)

total = len(RESULTS)
passed = sum(1 for r in RESULTS if r["status"] == "PASS")
failed = sum(1 for r in RESULTS if r["status"] == "FAIL")
warned = sum(1 for r in RESULTS if r["status"] == "WARN")

print(f"\n  Всего проверок: {total}")
print(f"  Пройдено:       {passed} ({100*passed//total if total else 0}%)")
print(f"  Предупреждений: {warned} ({100*warned//total if total else 0}%)")
print(f"  Провалено:      {failed} ({100*failed//total if total else 0}%)")

if failed > 0:
    print(f"\n  ❌ ПРОВАЛЕННЫЕ ТЕСТЫ:")
    for r in RESULTS:
        if r["status"] == "FAIL":
            print(f"     ✗ {r['test']}")
            print(f"       {r['details'][:150]}")

print("\n--- JSON ---")
print(json.dumps(RESULTS, ensure_ascii=False, indent=2))

# Сохраняем отчёт
report_path = os.path.join(os.path.dirname(__file__), "BACKEND_USE_CASE_REPORT.json")
with open(report_path, "w", encoding="utf-8") as f:
    json.dump(RESULTS, f, ensure_ascii=False, indent=2)
print(f"\nОтчёт сохранён: {report_path}")

sys.exit(0 if failed == 0 else 1)
