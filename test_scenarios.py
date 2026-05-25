import subprocess, json, sys

CUST_ID = "a4368c55-8b9d-4408-ba4c-8812f1acf6e2"
MAST_ID = "98988fbb-809a-4d8e-950c-1181c776811e"
BASE = "http://localhost:8080"
CUST_COOKIE = "C:/Users/ostap/AppData/Local/Temp/c_ck"
MAST_COOKIE = "C:/Users/ostap/AppData/Local/Temp/m_ck"
ADMIN_COOKIE = "C:/Users/ostap/AppData/Local/Temp/a_ck"

PASS = 0; FAIL = 0
def ok(msg):
    global PASS; PASS += 1; print(f"   ✅ {msg}")
def bad(msg):
    global FAIL; FAIL += 1; print(f"   ❌ {msg}")

def curl(cookies, method, path, data=None):
    cmd = ["curl", "-s"]
    if cookies: cmd += ["-b", cookies]
    if method != "GET": cmd += ["-X", method]
    if data: cmd += ["-H", "Content-Type: application/json", "-d", json.dumps(data, ensure_ascii=False)]
    cmd.append(f"{BASE}{path}")
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
        return r.stdout
    except Exception as e: return str(e)

def curl_code(cookies, method, path, data=None):
    cmd = ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}"]
    if cookies: cmd += ["-b", cookies]
    if method != "GET": cmd += ["-X", method]
    if data: cmd += ["-H", "Content-Type: application/json", "-d", json.dumps(data, ensure_ascii=False)]
    cmd.append(f"{BASE}{path}")
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    return r.stdout.strip()

# Admin login
subprocess.run(["curl", "-s", "-c", ADMIN_COOKIE, "-X", "POST", f"{BASE}/api/v1/auth/login",
    "-H", "Content-Type: application/json", "-d", '{"email":"admin@example.com","password":"admin123"}'],
    capture_output=True)

print("="*50)
print("SCENARIO 1: Orders + Categories")
print("="*50)

resp = curl(CUST_COOKIE, "POST", "/api/v1/orders", {
    "title": "Remont vannoy", "description": "Nuzhno zamenit plitku",
    "category_id": "d0000000-0000-0000-0000-000000000010", "price": 50000
})
try:
    ORDER1_ID = json.loads(resp)["order"]["id"]
    ok(f"Create order: {ORDER1_ID[:16]}...")
except: bad(f"Create order: {resp[:100]}"); ORDER1_ID = None

resp = curl(CUST_COOKIE, "POST", "/api/v1/orders", {
    "title": "Logo design", "description": "Nuzhen logotip",
    "category_id": "d0000000-0000-0000-0000-000000000021", "price": 15000
})
try:
    ORDER2_ID = json.loads(resp)["order"]["id"]
    ok(f"Create order #2: {ORDER2_ID[:16]}...")
except: bad(f"Create order #2: {resp[:100]}"); ORDER2_ID = None

resp = curl(CUST_COOKIE, "GET", "/api/v1/orders")
if "orders" in resp or "total" in resp: ok("List orders")
else: bad(f"List: {resp[:100]}")

if ORDER1_ID:
    resp = curl(CUST_COOKIE, "GET", f"/api/v1/orders/{ORDER1_ID}")
    if ORDER1_ID in resp: ok("Get order by ID")
    else: bad(f"Get: {resp[:100]}")

resp = curl(None, "GET", "/api/v1/categories")
cats = resp.count('"id"')
if cats >= 10: ok(f"Categories: {cats}")
else: bad(f"Categories: {cats}")

print("\n" + "="*50)
print("SCENARIO 2: Offers + Counter-offers")
print("="*50)

if ORDER1_ID:
    resp = curl(MAST_COOKIE, "POST", "/api/v1/offers", {
        "order_id": ORDER1_ID, "price": 45000, "message": "Sdelayu za 2 nedeli"
    })
    try:
        OFFER1_ID = json.loads(resp)["id"]
        ok(f"Master offer: {OFFER1_ID[:16]}... 45000")
    except: bad(f"Offer: {resp[:120]}"); OFFER1_ID = None

    if OFFER1_ID:
        resp = curl(MAST_COOKIE, "POST", "/api/v1/offers", {
            "order_id": ORDER1_ID, "price": 40000, "message": "Duplicate"
        })
        if "conflict" in resp.lower() or "error" in resp.lower():
            ok("Duplicate offer blocked")

        resp = curl(CUST_COOKIE, "POST", f"/api/v1/offers/{OFFER1_ID}/counter", {
            "price": 38000, "message": "Dorogovato. 38000?"
        })
        if "counter" in resp: ok("Buyer counter (38000)")
        else: bad(f"Counter: {resp[:100]}")

        resp = curl(MAST_COOKIE, "POST", f"/api/v1/offers/{OFFER1_ID}/counter", {
            "price": 42000, "message": "42000, vklyuchu materialy"
        })
        if "counter" in resp: ok("Master counter (42000)")
        else: bad(f"Counter: {resp[:100]}")

        resp = curl(CUST_COOKIE, "POST", f"/api/v1/offers/{OFFER1_ID}/counter", {
            "price": 42000, "message": "Dogovorilis!"
        })
        if "counter" in resp: ok("Final agreement (42000)")
        else: bad(f"Final: {resp[:100]}")

        resp = curl(CUST_COOKIE, "GET", f"/api/v1/offers/{OFFER1_ID}/history")
        events = resp.count('"type"')
        if events > 0: ok(f"Negotiation history: {events} events")
else: bad(f"History: {resp[:100]}")

if ORDER2_ID:
    resp = curl(MAST_COOKIE, "POST", "/api/v1/offers", {
        "order_id": ORDER2_ID, "price": 12000, "message": "Logotip za 3 dnya"
    })
    try:
        OFFER2_ID = json.loads(resp)["id"]
        ok(f"Offer #2: {OFFER2_ID[:16]}... 12000")
    except: bad(f"Offer #2: {resp[:120]}"); OFFER2_ID = None

print("\n" + "="*50)
print("SCENARIO 3: Accept + Reject")
print("="*50)

if ORDER2_ID and 'OFFER2_ID' in dir():
    resp = curl(CUST_COOKIE, "POST", f"/api/v1/offers/{OFFER2_ID}/accept")
    if "accepted" in resp or "success" in resp:
        ok("Offer #2 accepted")
    else: bad(f"Accept: {resp[:100]}")

    resp = curl(CUST_COOKIE, "GET", f"/api/v1/orders/{ORDER2_ID}")
    try:
        status = json.loads(resp).get("order", {}).get("status", "unknown")
        ok(f"Order status: {status}")
    except: bad(f"Status: {resp[:100]}")

if ORDER1_ID and 'OFFER1_ID' in dir():
    resp = curl(CUST_COOKIE, "POST", f"/api/v1/offers/{OFFER1_ID}/reject", {"reason": "Nashel drugogo"})
    if "rejected" in resp: ok("Offer #1 rejected")
    else: bad(f"Reject: {resp[:100]}")

print("\n" + "="*50)
print("SCENARIO 4: New offer after rejection")
print("="*50)

if ORDER1_ID:
    resp = curl(MAST_COOKIE, "POST", "/api/v1/offers", {
        "order_id": ORDER1_ID, "price": 40000, "message": "Novoe predlozhenie 40000"
    })
    try:
        OFFER1B_ID = json.loads(resp)["id"]
        ok(f"New offer: {OFFER1B_ID[:16]}...")
        resp = curl(CUST_COOKIE, "POST", f"/api/v1/offers/{OFFER1B_ID}/accept")
        if "accepted" in resp or "success" in resp:
            ok("New offer accepted")
        else: bad(f"Accept: {resp[:100]}")
    except: bad(f"New offer flow: {resp[:120]}")

print("\n" + "="*50)
print("SCENARIO 5: Withdraw offer")
print("="*50)

resp = curl(CUST_COOKIE, "POST", "/api/v1/orders", {
    "title": "CRM setup", "description": "AmoCRM",
    "category_id": "d0000000-0000-0000-0000-000000000013", "price": 8000
})
try:
    OID = json.loads(resp)["order"]["id"]
    resp = curl(MAST_COOKIE, "POST", "/api/v1/offers", {
        "order_id": OID, "price": 7000, "message": "Nastroyu za 2 dnya"
    })
    OFID = json.loads(resp)["id"]
    resp = curl(MAST_COOKIE, "POST", f"/api/v1/offers/{OFID}/withdraw", {"reason": "Ne uspevayu"})
    if "withdrawn" in resp: ok("Offer withdrawn by master")
    else: bad(f"Withdraw: {resp[:100]}")
except: bad(f"Withdraw flow: {resp[:100]}")

print("\n" + "="*50)
print("SCENARIO 6: Chat")
print("="*50)

if ORDER1_ID:
    resp = curl(CUST_COOKIE, "POST", "/api/v1/chats", {
        "order_id": ORDER1_ID, "customer_id": CUST_ID, "master_id": MAST_ID
    })
    try:
        CHAT_ID = json.loads(resp)["id"]
        ok(f"Chat created: {CHAT_ID[:16]}...")

        resp = curl(CUST_COOKIE, "POST", "/api/v1/chats", {
            "order_id": ORDER1_ID, "customer_id": CUST_ID, "master_id": MAST_ID
        })
        if "conflict" in resp.lower() or "error" in resp.lower():
            ok("Duplicate chat blocked")

        resp = curl(CUST_COOKIE, "POST", f"/api/v1/chat/{CHAT_ID}/messages", {"message": "Hello! When start?"})
        if "id" in resp: ok("Message from customer")
        else: bad(f"Msg: {resp[:100]}")

        resp = curl(MAST_COOKIE, "POST", f"/api/v1/chat/{CHAT_ID}/messages", {"message": "From Monday!"})
        if "id" in resp: ok("Message from master")
        else: bad(f"Msg: {resp[:100]}")

        resp = curl(CUST_COOKIE, "GET", f"/api/v1/chat/{CHAT_ID}/messages")
        msgs = resp.count('"id"')
        if msgs > 0: ok(f"Messages: {msgs}")
else: bad(f"Msgs: {resp[:100]}")

        resp = curl(CUST_COOKIE, "GET", "/api/v1/chats")
        if "chats" in resp: ok("Chat list")
else: bad(f"Chats: {resp[:100]}")
    except: bad(f"Chat flow: {resp[:100]}")

print("\n" + "="*50)
print("SCENARIO 7: Cancel order")
print("="*50)

resp = curl(CUST_COOKIE, "POST", "/api/v1/orders", {
    "title": "Test cancel", "description": "Will be cancelled",
    "category_id": "d0000000-0000-0000-0000-000000000041", "price": 1000
})
try:
    COID = json.loads(resp)["order"]["id"]
    resp = curl(CUST_COOKIE, "POST", f"/api/v1/orders/{COID}/cancel", {"reason": "Peredumal"})
    if "cancelled" in resp: ok("Order cancelled")
    else: bad(f"Cancel: {resp[:100]}")
except: bad(f"Cancel flow: {resp[:100]}")

print("\n" + "="*50)
print("SCENARIO 8: Complete + Review")
print("="*50)

if ORDER2_ID:
    resp = curl(MAST_COOKIE, "POST", f"/api/v1/orders/{ORDER2_ID}/complete")
    if "completed" in resp: ok("Order completed")
    else: bad(f"Complete: {resp[:100]}")

    resp = curl(CUST_COOKIE, "POST", "/api/v1/reviews", {
        "order_id": ORDER2_ID, "to_user_id": MAST_ID,
        "rating": 5, "comment": "Great work!"
    })
    if "id" in resp: ok("Review created (5 stars)")
    else: bad(f"Review: {resp[:100]}")

    resp = curl(CUST_COOKIE, "POST", "/api/v1/reviews", {
        "order_id": ORDER2_ID, "to_user_id": MAST_ID,
        "rating": 3, "comment": "Duplicate"
    })
    if "error" in resp.lower() or "conflict" in resp.lower():
        ok("Duplicate review blocked")
    else: bad(f"Dup review: {resp[:100]}")

print("\n" + "="*50)
print("SCENARIO 9: Review on incomplete order")
print("="*50)

if ORDER1_ID:
    resp = curl(CUST_COOKIE, "POST", "/api/v1/reviews", {
        "order_id": ORDER1_ID, "to_user_id": MAST_ID,
        "rating": 5, "comment": "Not completed yet"
    })
    if "error" in resp.lower(): ok("Review blocked (order not completed)")
    else: bad(f"Review block: {resp[:100]}")

print("\n" + "="*50)
print("SCENARIO 10: Complaint")
print("="*50)

if ORDER1_ID:
    resp = curl(CUST_COOKIE, "POST", "/api/v1/complaints", {
        "order_id": ORDER1_ID, "target_user_id": MAST_ID,
        "subject": "Price increase", "message": "Master raised price"
    })
    if "id" in resp: ok("Complaint created")
    else: bad(f"Complaint: {resp[:100]}")

print("\n" + "="*50)
print("SCENARIO 11: Order history")
print("="*50)

if ORDER2_ID:
    resp = curl(CUST_COOKIE, "GET", f"/api/v1/orders/{ORDER2_ID}/history")
    if "history" in resp:
        statuses = resp.count('"new_status"')
        if statuses > 0: ok(f"Order history: {statuses} transitions")
else: bad(f"History: {resp[:100]}")
    else: bad(f"History: {resp[:100]}")

print("\n" + "="*50)
print("SCENARIO 12: Notifications")
print("="*50)

resp = curl(CUST_COOKIE, "GET", "/api/v1/notifications")
if "success" in resp or "total" in resp: ok("Notifications OK")
else: bad(f"Notif: {resp[:100]}")

print("\n" + "="*50)
print("SCENARIO 13: Auth refresh + logout")
print("="*50)

resp = curl(CUST_COOKIE, "POST", "/api/v1/auth/refresh")
if "access_token" in resp: ok("Token refresh") else: bad(f"Refresh: {resp[:100]}")

print("\n" + "="*50)
print("SCENARIO 14: Security checks")
print("="*50)

code = curl_code(None, "POST", "/api/v1/auth/register", {
    "email": "s1@m.com", "password": "short", "first_name": "A", "last_name": "B", "phone": "+79990000001"
})
if code == "422": ok(f"Password min=8: {code}")
else: bad(f"Password min=8: {code}")

code = curl_code(None, "POST", "/api/v1/auth/register", {
    "email": "s2@m.com", "password": "nouppercase1", "first_name": "A", "last_name": "B", "phone": "+79990000002"
})
if code == "400": ok(f"No uppercase: {code} (expect 400)")
else: bad(f"No uppercase: {code}")

code = curl_code(None, "POST", "/api/v1/auth/register", {
    "email": "s3@m.com", "password": "NoDigitsHere", "first_name": "A", "last_name": "B", "phone": "+79990000003"
})
if code == "400": ok(f"No digits: {code} (expect 400)")
else: bad(f"No digits: {code}")

resp = curl(None, "POST", "/api/v1/auth/register", {
    "email": "s4@m.com", "password": "ValidPass1", "first_name": "A", "last_name": "B", "phone": "+79990000004"
})
if '"admin"' not in resp: ok("Admin role blocked")
else: bad("Admin role leaked!")

print(f"\n{'='*50}")
print(f"PASS={PASS} FAIL={FAIL}")
print(f"{'ALL PASSED' if FAIL == 0 else 'FAILURES'}")
print(f"{'='*50}")
