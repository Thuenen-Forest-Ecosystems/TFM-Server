#!/usr/bin/env bash
# ============================================================================
# Differential test: the same requests against two gateways (A = Kong, B = Envoy).
# ============================================================================
#   A_URL=http://127.0.0.1:8000 B_URL=http://127.0.0.1:8001 scripts/gateway-diff.sh
#
# Read-only by construction: every write either is rejected by the gateway (records block),
# targets a UUID that does not exist, or calls an RPC that does not exist. It is safe on prod.
#
# Environment:
#   A_URL, B_URL       gateways to compare (defaults: 127.0.0.1:8000 and 127.0.0.1:8001)
#   ENV_FILE           where ANON_KEY / SERVICE_ROLE_KEY / DASHBOARD_* are read from (default .env;
#                      read with grep, never sourced)
#   TFM_TEST_EMAIL / TFM_TEST_PASSWORD   optional: enables the cases that need a user session
#   ORIGIN             browser origin for the CORS cases
#
# Each case prints one line: SAME, DIFF(ok) for a difference that is approved below, or
# DIFF(!!) for one that is not. Exit 0 = no unapproved difference, 3 = at least one.
# ============================================================================
set -uo pipefail
cd "$(dirname "$0")/.."

A_URL="${A_URL:-http://127.0.0.1:8000}"
B_URL="${B_URL:-http://127.0.0.1:8001}"
ENV_FILE="${ENV_FILE:-.env}"
ORIGIN="${ORIGIN:-https://thuenen-forest-ecosystems.github.io}"

env_get() { grep -E "^$1=" "$ENV_FILE" | tail -n 1 | cut -d= -f2- | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/"; }
ANON_KEY="${ANON_KEY:-$(env_get ANON_KEY)}"
SERVICE_ROLE_KEY="${SERVICE_ROLE_KEY:-$(env_get SERVICE_ROLE_KEY)}"
DASH_USER="${DASHBOARD_USERNAME:-$(env_get DASHBOARD_USERNAME)}"
DASH_PASS="${DASHBOARD_PASSWORD:-$(env_get DASHBOARD_PASSWORD)}"
[ -n "$ANON_KEY" ] && [ -n "$SERVICE_ROLE_KEY" ] || { echo "ANON_KEY / SERVICE_ROLE_KEY not found in $ENV_FILE"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
NOID="00000000-0000-4000-8000-000000000000"
UNAPPROVED=0
N=0

sha() { if command -v sha256sum >/dev/null; then sha256sum | cut -c1-12; else shasum -a 256 | cut -c1-12; fi; }

# one request -> "<status>|<body sha>|<selected response headers>"
probe() { # probe BASE_URL PATH [curl args…]
    local base="$1" path="$2"; shift 2
    local code
    code="$(curl -s --max-time 40 -o "$TMP/body" -D "$TMP/hdr" -w '%{http_code}' "$@" "$base$path" 2>/dev/null)"
    local hdrs
    hdrs="$(tr -d '\r' <"$TMP/hdr" | grep -iE '^(content-type|www-authenticate|content-range):' |
        tr 'A-Z' 'a-z' | sed 's/; *charset=utf-8//' | sort | tr '\n' ';')"
    printf '%s|%s|%s' "$code" "$(sha <"$TMP/body")" "$hdrs"
}

# case MODE "description" "approved reason or -" PATH [curl args…]
#   MODE: status = compare the status code only; full = status, body and selected headers
case_() {
    local mode="$1" desc="$2" approved="$3" path="$4"; shift 4
    local a b
    a="$(probe "$A_URL" "$path" "$@")"
    b="$(probe "$B_URL" "$path" "$@")"
    N=$((N + 1))
    local ka="$a" kb="$b"
    if [ "$mode" = status ]; then ka="${a%%|*}"; kb="${b%%|*}"; fi
    if [ "$ka" = "$kb" ]; then
        printf 'SAME      %-62s %s\n' "$desc" "${a%%|*}"
    elif [ "$approved" != "-" ]; then
        printf 'DIFF(ok)  %-62s A=%s B=%s  [%s]\n' "$desc" "${a%%|*}" "${b%%|*}" "$approved"
    else
        UNAPPROVED=$((UNAPPROVED + 1))
        printf 'DIFF(!!)  %-62s A=%s B=%s\n' "$desc" "${a%%|*}" "${b%%|*}"
        printf '            A: %s\n            B: %s\n' "$a" "$b"
    fi
}

K=(-H "apikey: $ANON_KEY")
KA=(-H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY")
KS=(-H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY")
PUB=(-H "Accept-Profile: public" -H "Content-Profile: public" -H "Content-Type: application/json")
LOOKUP=(-H "Accept-Profile: lookup")

echo "A = $A_URL   B = $B_URL"
echo "── records write block (must be byte-identical: 401, JSON body without a code field)"
for m in POST PATCH PUT DELETE; do
    case_ full "$m /rest/v1/records, no Authorization" - "/rest/v1/records?id=eq.$NOID" -X "$m" "${K[@]}" "${PUB[@]}" -d '{}'
    case_ full "$m /rest/v1/records, Bearer anon" - "/rest/v1/records?id=eq.$NOID" -X "$m" "${KA[@]}" "${PUB[@]}" -d '{}'
done
case_ full "PATCH /rest/v1/records, no apikey at all" - "/rest/v1/records?id=eq.$NOID" -X PATCH "${PUB[@]}" -d '{}'
case_ full "PATCH /rest/v1/records, service apikey without Authorization" - "/rest/v1/records?id=eq.$NOID" -X PATCH -H "apikey: $SERVICE_ROLE_KEY" "${PUB[@]}" -d '{}'
case_ full "PATCH /rest/v1/records_messages, Bearer anon" - "/rest/v1/records_messages?id=eq.$NOID" -X PATCH "${KA[@]}" "${PUB[@]}" -d '{}'
case_ full "PATCH /rest/v1/%72ecords (encoded), Bearer anon" "Envoy normalises the path and blocks it; Kong lets it through to PostgREST" "/rest/v1/%72ecords?id=eq.$NOID" -X PATCH "${KA[@]}" "${PUB[@]}" -d '{}'
case_ status "GET /rest/v1/records, Bearer anon (not blocked)" - "/rest/v1/records?select=id&limit=1" "${KA[@]}" "${PUB[@]}"
case_ status "PATCH /rest/v1/troop, Bearer anon (other table, not blocked)" - "/rest/v1/troop?id=eq.$NOID" -X PATCH "${KA[@]}" "${PUB[@]}" -d '{}'

echo "── API key handling"
case_ status "GET /rest/v1/ (OpenAPI root), anon key" - "/rest/v1/" "${K[@]}"
case_ status "GET /rest/v1/ (OpenAPI root), service key" - "/rest/v1/" "${KS[@]}"
case_ status "GET /rest/v1/ without apikey" - "/rest/v1/"
case_ status "GET /rest/v1/lookup_state, wrong apikey" - "/rest/v1/lookup_state?limit=1" -H "apikey: wrong" "${LOOKUP[@]}"
case_ status "GET /auth/v1/health, apikey as query parameter" - "/auth/v1/health?apikey=$ANON_KEY"
case_ status "GET /auth/v1/health, apikey header" - "/auth/v1/health" "${K[@]}"
case_ status "GET /auth/v1/.well-known/jwks.json without apikey" "Envoy has an open JWKS route, Kong requires the apikey" "/auth/v1/.well-known/jwks.json"

echo "── REST shapes"
case_ full "GET lookup_state (lookup profile)" - "/rest/v1/lookup_state?select=*&order=code&limit=5" "${K[@]}" "${LOOKUP[@]}"
case_ full "GET lookup_state, Prefer count=exact + Range" - "/rest/v1/lookup_state?select=code" "${K[@]}" "${LOOKUP[@]}" -H "Prefer: count=exact" -H "Range: 0-2"
for kb in 2 6 7; do
    list="$(awk -v n=$((kb * 1024 / 7)) 'BEGIN{for(i=0;i<n;i++) printf "%s%06d", (i?",":""), i}')"
    case_ status "GET with in.(…) filter, URL ≈ ${kb} KB" - "/rest/v1/lookup_state?select=code&code=in.($list)" "${K[@]}" "${LOOKUP[@]}"
done
head -c 1048576 /dev/zero | tr '\0' 'a' >"$TMP/1mb"
printf '{"x":"%s"}' "$(cat "$TMP/1mb")" >"$TMP/1mb.json"
case_ status "POST 1 MB JSON to a non-existent RPC" - "/rest/v1/rpc/__gateway_diff_does_not_exist" -X POST "${KA[@]}" "${PUB[@]}" --data-binary "@$TMP/1mb.json"
case_ status "GET with a 6 KB request header" - "/rest/v1/lookup_state?limit=1" "${K[@]}" "${LOOKUP[@]}" -H "X-Padding: $(head -c 6000 "$TMP/1mb")"
case_ status "GET with a 16 KB request header" "Kong (nginx) rejects headers above 8 KB with 400, Envoy accepts up to 60 KB" "/rest/v1/lookup_state?limit=1" "${K[@]}" "${LOOKUP[@]}" -H "X-Padding: $(head -c 16000 "$TMP/1mb")"
case_ status "GET with %2F in the path" "Envoy rejects escaped slashes with 400 (documented)" "/rest/v1/lookup_state%2Fx?limit=1" "${K[@]}" "${LOOKUP[@]}"
case_ status "GET with an underscore header" "Envoy rejects headers with underscores (documented)" "/rest/v1/lookup_state?limit=1" "${K[@]}" "${LOOKUP[@]}" -H "x_under_score: 1"
case_ status "GET /graphql/v1 without apikey" - "/graphql/v1"

echo "── CORS (origin $ORIGIN) — asserted per gateway, not compared: Kong answers '*', Envoy echoes"
# cors_check LABEL BASE_URL PATH [curl args…]: origin allowed, and for preflights all four headers
cors_check() {
    local label="$1" base="$2" path="$3" kind="$4"; shift 4
    curl -s --max-time 20 -o /dev/null -D "$TMP/hdr" "$@" "$base$path" 2>/dev/null
    local acao acah ok=1
    acao="$(tr -d '\r' <"$TMP/hdr" | grep -i '^access-control-allow-origin:' | cut -d' ' -f2- | tr '\n' ',')"
    acah="$(tr -d '\r' <"$TMP/hdr" | grep -i '^access-control-allow-headers:' | cut -d' ' -f2- | tr 'A-Z' 'a-z')"
    case "$acao" in "*,"|"$ORIGIN,") ;; *) ok=0 ;; esac   # exactly one value, '*' or the origin
    if [ "$kind" = preflight ] && [ "$acah" != "*" ]; then
        for h in authorization apikey x-client-info content-type; do
            case ",$(echo "$acah" | tr -d ' ')," in *",$h,"*) ;; *) ok=0 ;; esac
        done
    fi
    N=$((N + 1))
    if [ "$ok" = 1 ]; then printf 'OK        %-62s origin=%s\n' "$label $path" "${acao%,}"
    else UNAPPROVED=$((UNAPPROVED + 1)); printf 'CORS(!!)  %-62s origin=[%s] headers=[%s]\n' "$label $path" "$acao" "$acah"; fi
}
for gw in "A $A_URL" "B $B_URL"; do
    set -- $gw
    for p in /rest/v1/records /auth/v1/token /storage/v1/object/list/validation /functions/v1/validation /functions/v1/invite-user; do
        cors_check "$1 preflight" "$2" "$p" preflight -X OPTIONS -H "Origin: $ORIGIN" -H "Access-Control-Request-Method: POST" \
            -H "Access-Control-Request-Headers: authorization,apikey,x-client-info,content-type"
    done
    cors_check "$1 GET" "$2" "/rest/v1/lookup_state?limit=1" simple "${K[@]}" "${LOOKUP[@]}" -H "Origin: $ORIGIN"
    cors_check "$1 blocked PATCH" "$2" "/rest/v1/records?id=eq.$NOID" simple -X PATCH "${KA[@]}" "${PUB[@]}" -H "Origin: $ORIGIN" -d '{}'
done

echo "── auth, storage, functions, realtime, studio"
case_ status "POST /auth/v1/token, wrong password" - "/auth/v1/token?grant_type=password" -X POST "${K[@]}" -H "Content-Type: application/json" -d '{"email":"nobody@example.invalid","password":"wrong-password"}'
case_ status "GET /auth/v1/settings" - "/auth/v1/settings" "${K[@]}"
case_ full "GET storage object that does not exist (app matches the message)" - "/storage/v1/object/validation/__gateway_diff_missing.js" "${KA[@]}"
case_ status "GET storage bucket list, service key" - "/storage/v1/bucket" "${KS[@]}"
case_ status "GET /functions/v1/health" - "/functions/v1/health" "${KA[@]}"
case_ status "GET /realtime/v1/api/tenants/realtime-dev/health" "blocked on Envoy (tenant API is 403 by design)" "/realtime/v1/api/tenants/realtime-dev/health" "${KA[@]}"
case_ status "websocket upgrade /realtime/v1/websocket" - "/realtime/v1/websocket?apikey=$ANON_KEY&vsn=1.0.0" --http1.1 --max-time 5 \
    -H "Connection: Upgrade" -H "Upgrade: websocket" -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ=="
case_ status "GET / (studio) without basic auth" - "/"
if [ -n "$DASH_USER" ]; then
    case_ status "GET / (studio) with basic auth" - "/" -u "$DASH_USER:$DASH_PASS" -L --max-redirs 3
fi
case_ status "GET /pg/ with anon key (admin only)" - "/pg/tables" "${KA[@]}"
case_ status "GET /api/mcp" "blocked on Envoy by design" "/api/mcp" -u "$DASH_USER:$DASH_PASS"
case_ status "GET /analytics/v1/ without key" "Envoy has no analytics route; falls through to studio basic auth" "/analytics/v1/health"

if [ -n "${TFM_TEST_EMAIL:-}" ] && [ -n "${TFM_TEST_PASSWORD:-}" ]; then
    echo "── with a user session ($TFM_TEST_EMAIL)"
    login() { curl -s --max-time 20 "$1/auth/v1/token?grant_type=password" "${K[@]}" -H 'Content-Type: application/json' \
        -d "{\"email\":\"$TFM_TEST_EMAIL\",\"password\":\"$TFM_TEST_PASSWORD\"}" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p'; }
    TOK_A="$(login "$A_URL")"; TOK_B="$(login "$B_URL")"
    if [ -n "$TOK_A" ] && [ -n "$TOK_B" ]; then
        echo "SAME      login works through both gateways"
        U=(-H "apikey: $ANON_KEY" -H "Authorization: Bearer $TOK_A")
        case_ status "GET /auth/v1/user" - "/auth/v1/user" "${U[@]}"
        case_ full "PATCH records with user JWT, no matching row (passes the block)" - "/rest/v1/records?id=eq.$NOID&select=id" -X PATCH "${U[@]}" "${PUB[@]}" -H "X-Client-Info: supabase-flutter/2.10.3" -H "Prefer: return=representation" -d '{"note":"gateway-diff"}'
        case_ status "GET records with user JWT" - "/rest/v1/records?select=id&limit=3" "${U[@]}" "${PUB[@]}"
        case_ status "GET view_records_details with user JWT" - "/rest/v1/view_records_details?select=id&limit=1" "${U[@]}" "${PUB[@]}"
    else
        UNAPPROVED=$((UNAPPROVED + 1))
        echo "DIFF(!!)  login failed (A token: ${#TOK_A} chars, B token: ${#TOK_B} chars)"
    fi
else
    echo "── user-session cases skipped (set TFM_TEST_EMAIL and TFM_TEST_PASSWORD)"
fi

echo
echo "$N cases, $UNAPPROVED unapproved difference(s)"
[ "$UNAPPROVED" = 0 ] || exit 3
