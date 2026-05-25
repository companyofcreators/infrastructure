#!/bin/bash
P=0; F=0
ok() { P=$((P+1)); echo "   ✅ $1"; }
bad() { F=$((F+1)); echo "   ❌ $1"; }
B="http://localhost:8080"
A="Content-Type: application/json"
CUST_ID=b0000000-0000-0000-0000-000000000002
MAST_ID=c0000000-0000-0000-0000-000000000003

echo "╔══════════════════════════════════════════════════════╗"
echo "║   FINAL COMPREHENSIVE TEST — ALL SCENARIOS          ║"
echo "╚══════════════════════════════════════════════════════╝"

# ═══ SETUP ═══
curl -s -c /tmp/cc -X POST $B/api/v1/auth/login -H "$A" -d '{"email":"customer@example.com","password":"password123"}' > /dev/null
curl -s -c /tmp/mc -X POST $B/api/v1/auth/login -H "$A" -d '{"email":"master@example.com","password":"password123"}' > /dev/null
curl -s -c /tmp/ac -X POST $B/api/v1/auth/login -H "$A" -d '{"email":"admin@example.com","password":"admin123"}' > /dev/null

# ═══════════════════════════════════════
echo ""
echo "──────────────────────────────────────────────"
echo "  1. HEALTH + INFRASTRUCTURE"
echo "──────────────────────────────────────────────"
curl -s $B/health | grep -q '"ok"' && ok "Health check (Redis)" || bad "Health"
DC=$(docker ps -q 2>/dev/null | wc -l)
[ "$DC" -ge 12 ] && ok "Docker: $DC containers" || bad "Docker: $DC"
PROCS=$(tasklist 2>/dev/null | grep -c "svc.exe\|mail-svc.exe")
[ "$PROCS" -ge 9 ] && ok "Processes: $PROCS" || bad "Processes: $PROCS"

# ═══════════════════════════════════════
echo ""
echo "──────────────────────────────────────────────"
echo "  2. AUTHENTICATION (8 tests)"
echo "──────────────────────────────────────────────"

# 2.1 Register new user
R=$(curl -s -X POST $B/api/v1/auth/register -H "$A" -d '{"email":"final1@test.com","password":"ValidPass1","first_name":"Ivan","last_name":"Ivanov","phone":"+79001000001"}')
echo "$R" | grep -q "access_token" && ok "Register" || bad "Register"
RID=$(echo "$R" | grep -o '"user_id":"[^"]*"' | cut -d'"' -f4)

# 2.2 No admin role on self-register
echo "$R" | grep -q '"admin"' && bad "Admin role leaked!" || ok "No admin self-assign"

# 2.3 Login
curl -s -c /tmp/fc -X POST $B/api/v1/auth/login -H "$A" -d '{"email":"final1@test.com","password":"ValidPass1"}' | grep -q "access_token" && ok "Login" || bad "Login"

# 2.4 Refresh token
curl -s -b /tmp/fc -X POST $B/api/v1/auth/refresh | grep -q "access_token" && ok "Token refresh" || bad "Refresh"

# 2.5 Logout
curl -s -b /tmp/fc -c /tmp/fc2 -X DELETE $B/api/v1/auth/logout > /dev/null
LO=$(curl -s -o /dev/null -w "%{http_code}" -b /tmp/fc2 $B/api/v1/orders)
[ "$LO" = "401" ] && ok "Logout (401 after)" || bad "Logout: HTTP $LO"

# 2.6 Password: min=8
S1=$(curl -s -o /dev/null -w "%{http_code}" -X POST $B/api/v1/auth/register -H "$A" -d '{"email":"pw1@test.com","password":"short","first_name":"A","last_name":"B","phone":"+79001000011"}')
[ "$S1" = "422" ] && ok "Password min=8: 422" || bad "Password min=8: $S1"

# 2.7 Password: no uppercase
S2=$(curl -s -o /dev/null -w "%{http_code}" -X POST $B/api/v1/auth/register -H "$A" -d '{"email":"pw2@test.com","password":"nouppercase1","first_name":"A","last_name":"B","phone":"+79001000012"}')
[ "$S2" = "400" ] && ok "No uppercase: 400" || bad "No uppercase: $S2"

# 2.8 Password: no digit
S3=$(curl -s -o /dev/null -w "%{http_code}" -X POST $B/api/v1/auth/register -H "$A" -d '{"email":"pw3@test.com","password":"NoDigitsHere","first_name":"A","last_name":"B","phone":"+79001000013"}')
[ "$S3" = "400" ] && ok "No digits: 400" || bad "No digits: $S3"

# ═══════════════════════════════════════
echo ""
echo "──────────────────────────────────────────────"
echo "  3. CATEGORIES (public)"
echo "──────────────────────────────────────────────"
CATS=$(curl -s $B/api/v1/categories | grep -o '"id":"[^"]*"' | wc -l)
[ "$CATS" -eq 13 ] && ok "Categories: $CATS" || bad "Categories: $CATS"

# ═══════════════════════════════════════
echo ""
echo "──────────────────────────────────────────────"
echo "  4. ORDER LIFECYCLE"
echo "──────────────────────────────────────────────"

# 4.1 Create order
O1=$(curl -s -b /tmp/cc -X POST $B/api/v1/orders -H "$A" -d '{"title":"Remont vannoy","description":"Zamena plitki 5m2 + ustanovka vanny. Adres: Lenina 15.","category_id":"d0000000-0000-0000-0000-000000000010","price":50000}')
O1ID=$(echo "$O1" | grep -o '"id":"[a-f0-9-]*"' | head -1 | cut -d'"' -f4)
[ -n "$O1ID" ] && ok "Create order" || bad "Create"

# 4.2 List orders
curl -s -b /tmp/cc $B/api/v1/orders | grep -q "orders" && ok "List orders" || bad "List"

# 4.3 Get order
curl -s -b /tmp/cc $B/api/v1/orders/$O1ID | grep -q "$O1ID" && ok "Get order by ID" || bad "Get"

# ═══════════════════════════════════════
echo ""
echo "──────────────────────────────────────────────"
echo "  5. OFFER LIFECYCLE"
echo "──────────────────────────────────────────────"

# 5.1 Create offer
OF1=$(curl -s -b /tmp/mc -X POST $B/api/v1/offers -H "$A" -d "{\"order_id\":\"$O1ID\",\"price\":45000,\"message\":\"Sdelayu remont za 2 nedeli. Opyt 5 let, portfolio est.\"}")
OF1ID=$(echo "$OF1" | grep -o '"id":"[a-f0-9-]*"' | head -1 | cut -d'"' -f4)
[ -n "$OF1ID" ] && ok "Create offer" || bad "Offer: $(echo $OF1 | head -c 80)"

# 5.2 Duplicate offer blocked
OFD=$(curl -s -b /tmp/mc -X POST $B/api/v1/offers -H "$A" -d "{\"order_id\":\"$O1ID\",\"price\":40000,\"message\":\"Dup\"}")
echo "$OFD" | grep -qi "error\|conflict\|уже" && ok "Duplicate blocked" || bad "Dup offer"

# 5.3 Customer counter-offer (38000)
curl -s -b /tmp/cc -X POST $B/api/v1/offers/$OF1ID/counter -H "$A" -d '{"price":38000,"message":"Dorogovato. Mozhet 38000?"}' | grep -q "counter" && ok "Counter: 38000" || bad "Counter 1"

# 5.4 Final agreement (42000)
curl -s -b /tmp/cc -X POST $B/api/v1/offers/$OF1ID/counter -H "$A" -d '{"price":42000,"message":"Ok, 42000. Vklyuchite materialy."}' | grep -q "counter" && ok "Counter: 42000" || bad "Counter 2"

# 5.5 Negotiation history
HIST=$(curl -s -b /tmp/cc $B/api/v1/offers/$OF1ID/history)
EVT=$(echo "$HIST" | grep -o '"type"' | wc -l)
[ "$EVT" -ge 2 ] && ok "History: $EVT events" || bad "History"

# 5.6 Accept offer
curl -s -b /tmp/cc -X POST $B/api/v1/offers/$OF1ID/accept | grep -qE "accepted|success" && ok "Accept offer" || bad "Accept"

# 5.7 Status after accept
ST=$(curl -s -b /tmp/cc $B/api/v1/orders/$O1ID | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)
[ "$ST" = "assigned" ] && ok "Status: assigned" || bad "Status: $ST"

# ═══════════════════════════════════════
echo ""
echo "──────────────────────────────────────────────"
echo "  6. WITHDRAW + REJECT"
echo "──────────────────────────────────────────────"

# 6.1 New order + offer + withdraw
O2=$(curl -s -b /tmp/cc -X POST $B/api/v1/orders -H "$A" -d '{"title":"CRM setup","description":"AmoCRM","category_id":"d0000000-0000-0000-0000-000000000013","price":8000}')
O2ID=$(echo "$O2" | grep -o '"id":"[a-f0-9-]*"' | head -1 | cut -d'"' -f4)
OF2=$(curl -s -b /tmp/mc -X POST $B/api/v1/offers -H "$A" -d "{\"order_id\":\"$O2ID\",\"price\":7000,\"message\":\"Za 2 dnya\"}")
OF2ID=$(echo "$OF2" | grep -o '"id":"[a-f0-9-]*"' | head -1 | cut -d'"' -f4)
curl -s -b /tmp/mc -X POST $B/api/v1/offers/$OF2ID/withdraw -H "$A" -d '{"reason":"Ne uspevayu"}' | grep -q "withdrawn" && ok "Withdraw" || bad "Withdraw"

# 6.2 New order + offer + reject
O3=$(curl -s -b /tmp/cc -X POST $B/api/v1/orders -H "$A" -d '{"title":"SEO articles","description":"10 statey","category_id":"d0000000-0000-0000-0000-000000000031","price":5000}')
O3ID=$(echo "$O3" | grep -o '"id":"[a-f0-9-]*"' | head -1 | cut -d'"' -f4)
OF3=$(curl -s -b /tmp/mc -X POST $B/api/v1/offers -H "$A" -d "{\"order_id\":\"$O3ID\",\"price\":4500,\"message\":\"5 dney\"}")
OF3ID=$(echo "$OF3" | grep -o '"id":"[a-f0-9-]*"' | head -1 | cut -d'"' -f4)
curl -s -b /tmp/cc -X POST $B/api/v1/offers/$OF3ID/reject -H "$A" -d '{"reason":"Nashel deshevle"}' | grep -q "rejected" && ok "Reject" || bad "Reject"

# ═══════════════════════════════════════
echo ""
echo "──────────────────────────────────────────────"
echo "  7. ORDER WORKFLOW"
echo "──────────────────────────────────────────────"

# 7.1 Master sets in_progress
curl -s -b /tmp/mc -X PATCH $B/api/v1/orders/$O1ID/status -H "$A" -d '{"status":"in_progress"}' | grep -q "in_progress" && ok "in_progress" || bad "in_progress"

# 7.2 Customer completes
curl -s -b /tmp/cc -X POST $B/api/v1/orders/$O1ID/complete | grep -q "completed" && ok "Complete" || bad "Complete"

# 7.3 Order history
curl -s -b /tmp/cc $B/api/v1/orders/$O1ID/history | grep -q "history" && ok "Order history" || bad "History"

# ═══════════════════════════════════════
echo ""
echo "──────────────────────────────────────────────"
echo "  8. REVIEWS"
echo "──────────────────────────────────────────────"

# 8.1 Create review
RV=$(curl -s -b /tmp/cc -X POST $B/api/v1/reviews -H "$A" -d "{\"order_id\":\"$O1ID\",\"to_user_id\":\"$MAST_ID\",\"rating\":5,\"comment\":\"Otlichny master! Remont sdelan kachestvenno i v srok.\"}")
echo "$RV" | grep -q '"id"' && ok "Review (5 stars)" || bad "Review"

# 8.2 Duplicate blocked
RVD=$(curl -s -b /tmp/cc -X POST $B/api/v1/reviews -H "$A" -d "{\"order_id\":\"$O1ID\",\"to_user_id\":\"$MAST_ID\",\"rating\":3,\"comment\":\"Dup\"}")
echo "$RVD" | grep -qi "error\|conflict\|cannot\|уже\|нельзя" && ok "Dup review blocked" || bad "Dup review"

# 8.3 Review on incomplete blocked
RV3=$(curl -s -b /tmp/cc -X POST $B/api/v1/reviews -H "$A" -d "{\"order_id\":\"$O2ID\",\"to_user_id\":\"$MAST_ID\",\"rating\":5,\"comment\":\"Not completed\"}")
echo "$RV3" | grep -qi "error\|conflict\|cannot\|заверш\|нельзя" && ok "Incomplete blocked" || bad "Incomplete review"

# ═══════════════════════════════════════
echo ""
echo "──────────────────────────────────────────────"
echo "  9. CHAT"
echo "──────────────────────────────────────────────"

# 9.1 Create chat
CH=$(curl -s -b /tmp/cc -X POST $B/api/v1/chats -H "$A" -d "{\"order_id\":\"$O1ID\",\"customer_id\":\"$CUST_ID\",\"master_id\":\"$MAST_ID\"}")
CHID=$(echo "$CH" | grep -o '"id":"[a-f0-9-]*"' | head -1 | cut -d'"' -f4)
[ -n "$CHID" ] && ok "Create chat" || bad "Chat"

# 9.2 Duplicate blocked
CHD=$(curl -s -b /tmp/cc -X POST $B/api/v1/chats -H "$A" -d "{\"order_id\":\"$O1ID\",\"customer_id\":\"$CUST_ID\",\"master_id\":\"$MAST_ID\"}")
echo "$CHD" | grep -qi "error\|conflict\|уже" && ok "Dup chat blocked" || bad "Dup chat"

# 9.3 Messages (customer + master)
curl -s -b /tmp/cc -X POST $B/api/v1/chat/$CHID/messages -H "$A" -d '{"message":"Zdravstvuyte! Kogda mozhno nachat?"}' | grep -q '"id"' && ok "Msg: customer" || bad "Msg#1"
curl -s -b /tmp/mc -X POST $B/api/v1/chat/$CHID/messages -H "$A" -d '{"message":"S ponedelnika! Materialy zakazal."}' | grep -q '"id"' && ok "Msg: master" || bad "Msg#2"

# 9.4 Message list
MCNT=$(curl -s -b /tmp/cc $B/api/v1/chat/$CHID/messages | grep -o '"id"' | wc -l)
[ "$MCNT" -ge 2 ] && ok "Messages: $MCNT" || bad "Msgs: $MCNT"

# 9.5 Chat list
curl -s -b /tmp/cc $B/api/v1/chats | grep -q "chats" && ok "Chat list" || bad "Chats"

# ═══════════════════════════════════════
echo ""
echo "──────────────────────────────────────────────"
echo "  10. COMPLAINT + ADMIN"
echo "──────────────────────────────────────────────"

# 10.1 Create complaint
CM=$(curl -s -b /tmp/cc -X POST $B/api/v1/complaints -H "$A" -d "{\"order_id\":\"$O3ID\",\"target_user_id\":\"$MAST_ID\",\"subject\":\"Narushenie srokov\",\"message\":\"Master prosrochil vipolnenie zakaza.\"}")
echo "$CM" | grep -q '"id"' && ok "Create complaint" || bad "Complaint"

# 10.2 Admin resolves complaint
CID=$(curl -s -b /tmp/ac http://localhost:8080/api/v1/complaints | grep -o '"id":"[a-f0-9-]*"' | head -1 | cut -d'"' -f4)
[ -n "$CID" ] && curl -s -b /tmp/ac -X PUT "$B/api/v1/admin/complaints/$CID" -H "$A" -d '{"status":"resolved","resolution":"Confirmed."}' | grep -q "complaint\|resolved\|success" && ok "Resolve complaint" || bad "Resolve"

# ═══════════════════════════════════════
echo ""
echo "──────────────────────────────────────────────"
echo "  11. BAN SYSTEM"
echo "──────────────────────────────────────────────"

# 11.1 Admin bans master
curl -s -b /tmp/ac -X POST $B/api/v1/admin/users/$MAST_ID/ban -H "$A" -d '{"reason":"Mnogo zhalob ot klientov"}' | grep -q "zablokirovan" && ok "Ban user" || bad "Ban"

# 11.2 Banned user blocked
BANNED=$(curl -s -X POST $B/api/v1/auth/login -H "$A" -d '{"email":"master@example.com","password":"password123"}')
echo "$BANNED" | grep -q "zablokirovan" && ok "Login blocked (banned)" || bad "Ban login"

# 11.3 Admin unbans
curl -s -b /tmp/ac -X POST $B/api/v1/admin/users/$MAST_ID/unban -H "$A" | grep -q "razblokirovan" && ok "Unban user" || bad "Unban"

# 11.4 Unbanned can login
curl -s -X POST $B/api/v1/auth/login -H "$A" -d '{"email":"master@example.com","password":"password123"}' | grep -q "access_token" && ok "Login after unban" || bad "Unban login"

# ═══════════════════════════════════════
echo ""
echo "──────────────────────────────────────────────"
echo "  12. NOTIFICATIONS"
echo "──────────────────────────────────────────────"
curl -s -b /tmp/cc $B/api/v1/notifications | grep -q '"success"' && ok "Notifications" || bad "Notif"

# ═══════════════════════════════════════
echo ""
echo "──────────────────────────────────────────────"
echo "  13. SECURITY"
echo "──────────────────────────────────────────────"

# 13.1 HMAC: direct access without signature
H1=$(curl -s -o /dev/null -w "%{http_code}" -H "X-User-Id: b0000000-0000-0000-0000-000000000002" http://localhost:8086/internal/orders)
[ "$H1" = "401" ] && ok "HMAC no-signature: 401" || bad "HMAC: $H1"

# 13.2 Self-assign admin blocked
S4=$(curl -s -X POST $B/api/v1/auth/register -H "$A" -d '{"email":"sec1@test.com","password":"ValidPass1","first_name":"A","last_name":"B","phone":"+79001000021"}')
echo "$S4" | grep -q '"admin"' && bad "Admin role leaked" || ok "Admin self-assign blocked"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
printf "║   PASS: %-46s║\n" "$P"
printf "║   FAIL: %-46s║\n" "$F"
if [ "$F" -eq 0 ]; then
    echo "║   ✅ ALL SCENARIOS PASSED                           ║"
else
    echo "║   ⚠️  FAILURES DETECTED                             ║"
fi
echo "╚══════════════════════════════════════════════════════╝"
