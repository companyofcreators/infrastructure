#!/bin/bash
P=0; F=0
ok() { P=$((P+1)); echo "   OK $1"; }
bad() { F=$((F+1)); echo "   FAIL $1"; }

BASE="http://localhost:8080"
CUST_ID=b0000000-0000-0000-0000-000000000002
MAST_ID=c0000000-0000-0000-0000-000000000003

echo "=== Login ==="
curl -s -c /tmp/cck -X POST $BASE/api/v1/auth/login -H "Content-Type: application/json" -d '{"email":"customer@example.com","password":"password123"}' > /dev/null
echo "customer OK"
curl -s -c /tmp/mck -X POST $BASE/api/v1/auth/login -H "Content-Type: application/json" -d '{"email":"master@example.com","password":"password123"}' > /dev/null
echo "master OK"

echo ""
echo "=== 1. ORDER ==="
ORDER=$(curl -s -b /tmp/cck -X POST $BASE/api/v1/orders -H "Content-Type: application/json" -d '{"title":"Remont vannoy","description":"Zamena plitki 5m2","category_id":"d0000000-0000-0000-0000-000000000010","price":50000}')
OID=$(echo "$ORDER" | python -c "import sys,json; print(json.load(sys.stdin)['order']['id'])" 2>/dev/null || echo "$ORDER" | grep -o '"id":"[a-f0-9-]*"' | head -1 | cut -d'"' -f4)
[ -n "$OID" ] && ok "Create order: $OID" || bad "Create: $(echo $ORDER | head -c 80)"
curl -s -b /tmp/cck $BASE/api/v1/orders | grep -q "orders" && ok "List orders" || bad "List"
curl -s -b /tmp/cck $BASE/api/v1/orders/$OID | grep -q "$OID" && ok "Get by ID" || bad "Get"

echo ""
echo "=== 2. OFFER ==="
OFFER=$(curl -s -b /tmp/mck -X POST $BASE/api/v1/offers -H "Content-Type: application/json" -d "{\"order_id\":\"$OID\",\"price\":45000,\"message\":\"Sdelayu za 2 nedeli\"}")
OFID=$(echo "$OFFER" | grep -o '"id":"[a-f0-9-]*"' | head -1 | cut -d'"' -f4)
[ -n "$OFID" ] && ok "Offer created: 45000" || bad "Offer: $(echo $OFFER | head -c 80)"

echo ""
echo "=== 3. COUNTER-OFFERS ==="
curl -s -b /tmp/cck -X POST $BASE/api/v1/offers/$OFID/counter -H "Content-Type: application/json" -d '{"price":38000,"message":"Dorogovato. 38000?"}' | grep -q "counter" && ok "Buyer: 38000" || bad "Counter 1"
curl -s -b /tmp/mck -X POST $BASE/api/v1/offers/$OFID/counter -H "Content-Type: application/json" -d '{"price":42000,"message":"42000 s materialami"}' | grep -q "counter" && ok "Master: 42000" || bad "Counter 2"
curl -s -b /tmp/cck -X POST $BASE/api/v1/offers/$OFID/counter -H "Content-Type: application/json" -d '{"price":42000,"message":"Dogovorilis!"}' | grep -q "counter" && ok "Final: agreed 42000" || bad "Counter 3"

echo ""
echo "=== 4. ACCEPT ==="
curl -s -b /tmp/cck -X POST $BASE/api/v1/offers/$OFID/accept | grep -qE "accepted|success" && ok "Accept offer" || bad "Accept"

echo ""
echo "=== 5. WITHDRAW ==="
O2=$(curl -s -b /tmp/cck -X POST $BASE/api/v1/orders -H "Content-Type: application/json" -d '{"title":"CRM setup","description":"AmoCRM","category_id":"d0000000-0000-0000-0000-000000000013","price":8000}')
O2ID=$(echo "$O2" | grep -o '"id":"[a-f0-9-]*"' | head -1 | cut -d'"' -f4)
OF2=$(curl -s -b /tmp/mck -X POST $BASE/api/v1/offers -H "Content-Type: application/json" -d "{\"order_id\":\"$O2ID\",\"price\":7000,\"message\":\"Za 2 dnya\"}")
OF2ID=$(echo "$OF2" | grep -o '"id":"[a-f0-9-]*"' | head -1 | cut -d'"' -f4)
curl -s -b /tmp/mck -X POST $BASE/api/v1/offers/$OF2ID/withdraw -H "Content-Type: application/json" -d '{"reason":"Ne uspevayu"}' | grep -q "withdrawn" && ok "Withdraw" || bad "Withdraw: $(curl -s -b /tmp/mck -X POST $BASE/api/v1/offers/$OF2ID/withdraw -H "Content-Type: application/json" -d '{"reason":"Ne uspevayu"}' | head -c 80)"

echo ""
echo "=== 6. CHAT ==="
CHAT=$(curl -s -b /tmp/cck -X POST $BASE/api/v1/chats -H "Content-Type: application/json" -d "{\"order_id\":\"$OID\",\"customer_id\":\"$CUST_ID\",\"master_id\":\"$MAST_ID\"}")
CHID=$(echo "$CHAT" | grep -o '"id":"[a-f0-9-]*"' | head -1 | cut -d'"' -f4)
[ -n "$CHID" ] && ok "Chat created" || bad "Chat: $(echo $CHAT | head -c 80)"
curl -s -b /tmp/cck -X POST $BASE/api/v1/chat/$CHID/messages -H "Content-Type: application/json" -d '{"message":"Hello! When?"}' | grep -q '"id"' && ok "Msg customer" || bad "Msg 1"
curl -s -b /tmp/mck -X POST $BASE/api/v1/chat/$CHID/messages -H "Content-Type: application/json" -d '{"message":"From Monday!"}' | grep -q '"id"' && ok "Msg master" || bad "Msg 2"

MSGS=$(curl -s -b /tmp/cck $BASE/api/v1/chat/$CHID/messages | grep -o '"id"' | wc -l)
[ "$MSGS" -ge 2 ] && ok "Messages: $MSGS" || bad "Msgs: $MSGS"

echo ""
echo "=== 7. COMPLETE + REVIEW ==="
curl -s -b /tmp/mck -X POST $BASE/api/v1/orders/$OID/complete | grep -q "completed" && ok "Complete" || bad "Complete"
curl -s -b /tmp/cck -X POST $BASE/api/v1/reviews -H "Content-Type: application/json" -d "{\"order_id\":\"$OID\",\"to_user_id\":\"$MAST_ID\",\"rating\":5,\"comment\":\"Great!\"}" | grep -q '"id"' && ok "Review 5*" || bad "Review"

echo ""
echo "=== 8. HISTORY ==="
curl -s -b /tmp/cck $BASE/api/v1/orders/$OID/history | grep -q "history" && ok "History" || bad "History"

echo ""
echo "=== 9. SECURITY ==="
S1=$(curl -s -o /dev/null -w "%{http_code}" -X POST $BASE/api/v1/auth/register -H "Content-Type: application/json" -d '{"email":"z1@z.com","password":"short","first_name":"A","last_name":"B","phone":"+79000000001"}')
[ "$S1" = "422" ] && ok "Min=8: $S1" || bad "Min=8: $S1"
S2=$(curl -s -o /dev/null -w "%{http_code}" -X POST $BASE/api/v1/auth/register -H "Content-Type: application/json" -d '{"email":"z2@z.com","password":"nouppercase1","first_name":"A","last_name":"B","phone":"+79000000002"}')
[ "$S2" = "400" ] && ok "No upper: $S2" || bad "No upper: $S2"
S3=$(curl -s -o /dev/null -w "%{http_code}" -X POST $BASE/api/v1/auth/register -H "Content-Type: application/json" -d '{"email":"z3@z.com","password":"NoDigitsHere","first_name":"A","last_name":"B","phone":"+79000000003"}')
[ "$S3" = "400" ] && ok "No digit: $S3" || bad "No digit: $S3"
S4=$(curl -s -X POST $BASE/api/v1/auth/register -H "Content-Type: application/json" -d '{"email":"z4@z.com","password":"ValidPass1","first_name":"A","last_name":"B","phone":"+79000000004"}')
echo "$S4" | grep -q '"admin"' && bad "Admin leaked" || ok "Admin blocked"

echo ""
echo "========================"
echo "PASS=$P FAIL=$F"
[ "$F" -eq 0 ] && echo "ALL SCENARIOS PASSED"
echo "========================"
