#!/bin/bash
P=0; F=0
ok() { P=$((P+1)); echo "   ✅ $1"; }
bad() { F=$((F+1)); echo "   ❌ $1"; }
B="http://localhost:8080"
A="Content-Type: application/json"

echo "╔══════════════════════════════════════════════╗"
echo "║   FINAL TEST — ALL SCENARIOS                ║"
echo "╚══════════════════════════════════════════════╝"

# ── SETUP ──
CUST=$(curl -s -X POST $B/api/v1/auth/register -H "$A" -d '{"email":"newcust@test.com","password":"ValidPass1","first_name":"Petr","last_name":"Pokupatel","phone":"+79001000001"}')
CUST_ID=$(echo "$CUST" | grep -o '"user_id":"[^"]*"' | cut -d'"' -f4)
curl -s -c /tmp/cc -X POST $B/api/v1/auth/login -H "$A" -d '{"email":"newcust@test.com","password":"ValidPass1"}' > /dev/null

MAST=$(curl -s -X POST $B/api/v1/auth/register -H "$A" -d '{"email":"newmast@test.com","password":"ValidPass1","first_name":"Sergey","last_name":"Master","phone":"+79002000002"}')
MAST_ID=$(echo "$MAST" | grep -o '"user_id":"[^"]*"' | cut -d'"' -f4)
curl -s -c /tmp/mc -X POST $B/api/v1/auth/login -H "$A" -d '{"email":"newmast@test.com","password":"ValidPass1"}' > /dev/null

curl -s -c /tmp/ac -X POST $B/api/v1/auth/login -H "$A" -d '{"email":"admin@example.com","password":"admin123"}' > /dev/null

echo ""
echo "── 1. HEALTH ──"
curl -s $B/health | grep -q '"ok"' && ok "Health" || bad "Health"
DC=$(docker ps -q 2>/dev/null | wc -l)
[ "$DC" -ge 12 ] && ok "Docker: $DC" || bad "Docker: $DC"

echo ""
echo "── 2. AUTH ──"
echo "$CUST" | grep -q "access_token" && ok "Register" || bad "Register"
echo "$CUST" | grep -q '"admin"' && bad "Admin leak!" || ok "No admin role"
curl -s -X POST $B/api/v1/auth/refresh -b /tmp/cc | grep -q "access_token" && ok "Refresh" || bad "Refresh"
curl -s -b /tmp/cc -c /tmp/cc2 -X DELETE $B/api/v1/auth/logout > /dev/null
[ "$(curl -s -o /dev/null -w '%{http_code}' -b /tmp/cc2 $B/api/v1/orders)" = "401" ] && ok "Logout" || bad "Logout"
R1=$(curl -s -o /dev/null -w "%{http_code}" -X POST $B/api/v1/auth/register -H "$A" -d '{"email":"pw1@x.com","password":"short","first_name":"A","last_name":"B","phone":"+79000000001"}')
[ "$R1" = "422" ] && ok "Password min=8: $R1" || bad "Password min=8: $R1"
R2=$(curl -s -o /dev/null -w "%{http_code}" -X POST $B/api/v1/auth/register -H "$A" -d '{"email":"pw2@x.com","password":"nouppercase1","first_name":"A","last_name":"B","phone":"+79000000002"}')
[ "$R2" = "400" ] && ok "No uppercase: $R2" || bad "No uppercase: $R2"
R3=$(curl -s -o /dev/null -w "%{http_code}" -X POST $B/api/v1/auth/register -H "$A" -d '{"email":"pw3@x.com","password":"NoDigitsHere","first_name":"A","last_name":"B","phone":"+79000000003"}')
[ "$R3" = "400" ] && ok "No digit: $R3" || bad "No digit: $R3"

echo ""
echo "── 3. CATEGORIES ──"
CATS=$(curl -s $B/api/v1/categories | grep -o '"id"' | wc -l)
[ "$CATS" -ge 10 ] && ok "Categories: $CATS" || bad "Categories: $CATS"

echo ""
echo "── 4. ORDERS ──"
O1=$(curl -s -b /tmp/cc -X POST $B/api/v1/orders -H "$A" -d '{"title":"Remont vannoy","description":"Zamena plitki","category_id":"d0000000-0000-0000-0000-000000000010","price":50000}')
O1ID=$(echo "$O1" | grep -o '"id":"[a-f0-9-]*"' | head -1 | cut -d'"' -f4)
[ -n "$O1ID" ] && ok "Create order" || bad "Create"
curl -s -b /tmp/cc $B/api/v1/orders | grep -q "orders" && ok "List orders" || bad "List"
curl -s -b /tmp/cc $B/api/v1/orders/$O1ID | grep -q "$O1ID" && ok "Get order" || bad "Get"

echo ""
echo "── 5. OFFERS ──"
# Give master role to user (via user-service)
curl -s -X POST $B/api/v1/users/$MAST_ID/roles/master -H "X-User-Id: $MAST_ID" -H "Content-Type: application/json" > /dev/null 2>&1

OF1=$(curl -s -b /tmp/mc -X POST $B/api/v1/offers -H "$A" -d "{\"order_id\":\"$O1ID\",\"price\":45000,\"message\":\"Sdelayu za 2 nedeli\"}")
OF1ID=$(echo "$OF1" | grep -o '"id":"[a-f0-9-]*"' | head -1 | cut -d'"' -f4)
[ -n "$OF1ID" ] && ok "Create offer" || bad "Offer: $(echo $OF1 | head -c 60)"
OFD=$(curl -s -b /tmp/mc -X POST $B/api/v1/offers -H "$A" -d "{\"order_id\":\"$O1ID\",\"price\":40000,\"message\":\"Dup\"}")
echo "$OFD" | grep -qi "error\|conflict\|уже" && ok "Dup blocked" || bad "Dup"

# Counter (customer only)
curl -s -b /tmp/cc -X POST $B/api/v1/offers/$OF1ID/counter -H "$A" -d '{"price":38000,"message":"Dorogovato"}' | grep -q "counter" && ok "Counter" || bad "Counter"
curl -s -b /tmp/cc -X POST $B/api/v1/offers/$OF1ID/counter -H "$A" -d '{"price":42000,"message":"Ok"}' | grep -q "counter" && ok "Agreed" || bad "Agreed"

HIST=$(curl -s -b /tmp/cc $B/api/v1/offers/$OF1ID/history)
[ $(echo "$HIST" | grep -o '"type"' | wc -l) -ge 2 ] && ok "History" || bad "History"

# Accept
curl -s -b /tmp/cc -X POST $B/api/v1/offers/$OF1ID/accept | grep -qE "accepted|success" && ok "Accept" || bad "Accept"
ST=$(curl -s -b /tmp/cc $B/api/v1/orders/$O1ID | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)
[ "$ST" = "assigned" ] && ok "Status: $ST" || bad "Status: $ST"

echo ""
echo "── 6. WITHDRAW + REJECT ──"
O2=$(curl -s -b /tmp/cc -X POST $B/api/v1/orders -H "$A" -d '{"title":"CRM","description":"AmoCRM","category_id":"d0000000-0000-0000-0000-000000000013","price":8000}')
O2ID=$(echo "$O2" | grep -o '"id":"[a-f0-9-]*"' | head -1 | cut -d'"' -f4)
OF2=$(curl -s -b /tmp/mc -X POST $B/api/v1/offers -H "$A" -d "{\"order_id\":\"$O2ID\",\"price\":7000,\"message\":\"Za 2 dnya\"}")
OF2ID=$(echo "$OF2" | grep -o '"id":"[a-f0-9-]*"' | head -1 | cut -d'"' -f4)
curl -s -b /tmp/mc -X POST $B/api/v1/offers/$OF2ID/withdraw -H "$A" -d '{"reason":"Ne uspevayu"}' | grep -q "withdrawn" && ok "Withdraw" || bad "Withdraw"

O3=$(curl -s -b /tmp/cc -X POST $B/api/v1/orders -H "$A" -d '{"title":"SEO","description":"10 statey","category_id":"d0000000-0000-0000-0000-000000000031","price":5000}')
O3ID=$(echo "$O3" | grep -o '"id":"[a-f0-9-]*"' | head -1 | cut -d'"' -f4)
OF3=$(curl -s -b /tmp/mc -X POST $B/api/v1/offers -H "$A" -d "{\"order_id\":\"$O3ID\",\"price\":4500,\"message\":\"5 dney\"}")
OF3ID=$(echo "$OF3" | grep -o '"id":"[a-f0-9-]*"' | head -1 | cut -d'"' -f4)
curl -s -b /tmp/cc -X POST $B/api/v1/offers/$OF3ID/reject -H "$A" -d '{"reason":"Nashel deshevle"}' | grep -q "rejected" && ok "Reject" || bad "Reject"

echo ""
echo "── 7. WORKFLOW (in_progress → complete) ──"
curl -s -b /tmp/mc -X PATCH $B/api/v1/orders/$O1ID/status -H "$A" -d '{"status":"in_progress"}' | grep -q "in_progress" && ok "in_progress" || bad "in_progress"
curl -s -b /tmp/cc -X POST $B/api/v1/orders/$O1ID/complete | grep -q "completed" && ok "Complete" || bad "Complete"
curl -s -b /tmp/cc $B/api/v1/orders/$O1ID/history | grep -q "history" && ok "History" || bad "History"

echo ""
echo "── 8. REVIEWS ──"
curl -s -b /tmp/cc -X POST $B/api/v1/reviews -H "$A" -d "{\"order_id\":\"$O1ID\",\"to_user_id\":\"$MAST_ID\",\"rating\":5,\"comment\":\"Great!\"}" | grep -q '"id"' && ok "Review 5*" || bad "Review"
RVD=$(curl -s -b /tmp/cc -X POST $B/api/v1/reviews -H "$A" -d "{\"order_id\":\"$O1ID\",\"to_user_id\":\"$MAST_ID\",\"rating\":3,\"comment\":\"Dup\"}")
echo "$RVD" | grep -qi "error\|conflict\|уже\|нельзя" && ok "Dup blocked" || bad "Dup review"

echo ""
echo "── 9. CHAT ──"
CH=$(curl -s -b /tmp/cc -X POST $B/api/v1/chats -H "$A" -d "{\"order_id\":\"$O1ID\",\"customer_id\":\"$CUST_ID\",\"master_id\":\"$MAST_ID\"}")
CHID=$(echo "$CH" | grep -o '"id":"[a-f0-9-]*"' | head -1 | cut -d'"' -f4)
[ -n "$CHID" ] && ok "Chat created" || bad "Chat"
curl -s -b /tmp/cc -X POST $B/api/v1/chat/$CHID/messages -H "$A" -d '{"message":"Hello!"}' | grep -q '"id"' && ok "Msg 1" || bad "Msg 1"
curl -s -b /tmp/mc -X POST $B/api/v1/chat/$CHID/messages -H "$A" -d '{"message":"Hi!"}' | grep -q '"id"' && ok "Msg 2" || bad "Msg 2"
MSG=$(curl -s -b /tmp/cc $B/api/v1/chat/$CHID/messages | grep -o '"id"' | wc -l)
[ "$MSG" -ge 2 ] && ok "Msgs: $MSG" || bad "Msgs: $MSG"
curl -s -b /tmp/cc $B/api/v1/chats | grep -q "chats" && ok "Chat list" || bad "Chat list"

echo ""
echo "── 10. COMPLAINT + ADMIN ──"
CM=$(curl -s -b /tmp/cc -X POST $B/api/v1/complaints -H "$A" -d "{\"order_id\":\"$O3ID\",\"target_user_id\":\"$MAST_ID\",\"subject\":\"Sroki\",\"message\":\"Prosrochil\"}")
echo "$CM" | grep -q '"id"' && ok "Complaint" || bad "Complaint"
CID=$(curl -s -b /tmp/ac $B/api/v1/complaints | grep -o '"id":"[a-f0-9-]*"' | head -1 | cut -d'"' -f4)
curl -s -b /tmp/ac -X PATCH "$B/api/v1/admin/complaints/$CID" -H "$A" -d '{"status":"in_review"}' | grep -q "complaint" && ok "Complaint→in_review" || bad "Resolve"

echo ""
echo "── 11. BAN SYSTEM ──"
curl -s -b /tmp/ac -X POST $B/api/v1/admin/users/$MAST_ID/ban -H "$A" -d '{"reason":"Test"}' | grep -q "zablokirovan" && ok "Ban" || bad "Ban"
BANNED=$(curl -s -X POST $B/api/v1/auth/login -H "$A" -d '{"email":"newmast@test.com","password":"ValidPass1"}')
echo "$BANNED" | grep -q "zablokirovan" && ok "Banned login blocked" || bad "Ban login"
curl -s -b /tmp/ac -X POST $B/api/v1/admin/users/$MAST_ID/unban -H "$A" | grep -q "razblokirovan" && ok "Unban" || bad "Unban"
curl -s -X POST $B/api/v1/auth/login -H "$A" -d '{"email":"newmast@test.com","password":"ValidPass1"}' | grep -q "access_token" && ok "Login after unban" || bad "Unban login"

echo ""
echo "── 12. NOTIFICATIONS ──"
curl -s -b /tmp/cc $B/api/v1/notifications | grep -q '"success"' && ok "Notif" || bad "Notif"

echo ""
echo "── 13. SECURITY ──"
H1=$(curl -s -o /dev/null -w "%{http_code}" -H "X-User-Id: $CUST_ID" http://localhost:8086/internal/orders)
[ "$H1" = "401" ] && ok "HMAC: $H1" || bad "HMAC: $H1"
curl -s -X POST $B/api/v1/auth/register -H "$A" -d '{"email":"sec@x.com","password":"ValidPass1","first_name":"A","last_name":"B","phone":"+79000000004"}' | grep -q '"admin"' && bad "Admin leak" || ok "Admin blocked"
curl -s -o /dev/null -w "%{http_code}" $B/docs/scalar.html | grep -q "200" && ok "Docs: 200" || bad "Docs"
curl -s -o /dev/null -w "%{http_code}" $B/docs/scalar.js | grep -q "200" && ok "Scalar JS: 200" || bad "Scalar JS"

echo ""
echo "╔══════════════════════════════════════════════╗"
printf "║   PASS: %-37s║\n" "$P"
printf "║   FAIL: %-37s║\n" "$F"
[ "$F" -eq 0 ] && echo "║   ✅ ALL TESTS PASSED                        ║" || echo "║   ⚠️  FAILURES                               ║"
echo "╚══════════════════════════════════════════════╝"
