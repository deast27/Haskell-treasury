#!/usr/bin/env bash
# End-to-end walk-through against a running treasury-api (:8080).
# Requires: pg-start, cabal run treasury-api, cabal run mock-partner,
#           cabal run treasury-workers -- submit, cabal run treasury-workers -- poll
set -euo pipefail
API=${API:-http://localhost:8080}
j() { python3 -c "import sys,json; print(json.load(sys.stdin)$1)"; }

echo "# create a business and an operating account"
BID=$(curl -sS -X POST $API/businesses -H 'Content-Type: application/json' -d '{"name":"Acme Robotics"}' | j "['id']")
AID=$(curl -sS -X POST $API/accounts -H 'Content-Type: application/json' -d "{\"businessId\":$BID,\"name\":\"Operating\"}" | j "['id']")
echo "business=$BID account=$AID"

echo "# fund it with \$50,000.00"
curl -sS -X POST $API/accounts/$AID/deposits -H 'Content-Type: application/json' -d '{"amount":5000000,"description":"Series A wire"}' | j "['balanceFormatted']"

echo "# send an ACH payment of \$1,250.00 (idempotent)"
PID=$(curl -sS -X POST $API/payments -H 'Content-Type: application/json' -H "Idempotency-Key: demo-$(date +%s)" \
  -d "{\"accountId\":$AID,\"rail\":\"Ach\",\"amount\":125000,\"counterpartyName\":\"Northwind Supplies\",\"counterpartyRouting\":\"021000021\",\"counterpartyAccount\":\"000123456789\",\"memo\":\"Invoice 1042\"}" | j "['id']")
echo "payment=$PID"

echo "# a payment the partner will return (amount ends in 13)"
curl -sS -X POST $API/payments -H 'Content-Type: application/json' -H "Idempotency-Key: demo-ret-$(date +%s)" \
  -d "{\"accountId\":$AID,\"rail\":\"Wire\",\"amount\":100013,\"counterpartyName\":\"Contoso Ltd\",\"counterpartyRouting\":\"026009593\",\"counterpartyAccount\":\"998877\"}" | j "['status']"

echo "# watch the lifecycle (workers advance it every ~5s)"
for i in 1 2 3 4 5 6; do
  sleep 5
  curl -sS $API/payments/$PID | j "['status']"
done
echo "# ledger"
curl -sS $API/accounts/$AID/ledger | python3 -m json.tool | head -40
curl -sS $API/accounts/$AID | j "['balanceFormatted']"
