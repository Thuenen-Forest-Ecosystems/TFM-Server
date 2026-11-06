#!/bin/bash
# ============================================================================
# HTTP test for guard_records_app_only_columns (20261106000000)
# ============================================================================
# Talks to the REAL REST API (Kong/Envoy → PostgREST) as a logged-in user,
# so it also proves that the proxy passes X-Client-Info through to the DB.
# Every change it makes is reverted at the end (original values are read
# first and written back with the app header).
#
#   ./run_app_only_guard_http.sh <log|enforce> [record_id]
#
# Environment:
#   API_URL   default http://127.0.0.1:54321 (local stack)
#   ANON_KEY  default: key of the local stack (supabase status)
#   TFM_TEST_EMAIL / TFM_TEST_PASSWORD  default: ../../../tfm-credentials/env/tfm-app.env
#   record_id default f7a2ed08-… (1000000070 / 3, training plot)
#
# Exit 0 = every case as expected, 3 = deviation.
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:?usage: $0 <log|enforce> [record_id]}"
RECORD="${2:-f7a2ed08-3bd2-49f7-97d4-06a7f81ade7a}"
API_URL="${API_URL:-http://127.0.0.1:54321}"
APP_HEADER="supabase-flutter/2.10.3"

if [[ -z "${TFM_TEST_EMAIL:-}" ]]; then
    set -a; source ../../../tfm-credentials/env/tfm-app.env; set +a
fi
if [[ -z "${ANON_KEY:-}" ]]; then
    ANON_KEY=$(cd ../.. && supabase status -o env 2>/dev/null | sed -n 's/^ANON_KEY="\(.*\)"$/\1/p')
fi

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

TOKEN=$(curl -sf "$API_URL/auth/v1/token?grant_type=password" \
    -H "apikey: $ANON_KEY" -H 'Content-Type: application/json' \
    -d "$(jq -n --arg e "$TFM_TEST_EMAIL" --arg p "$TFM_TEST_PASSWORD" '{email:$e,password:$p}')" \
    | jq -r .access_token)
[[ -n "$TOKEN" && "$TOKEN" != null ]] || { echo "login failed"; exit 1; }

COMMON=(-H "apikey: $ANON_KEY" -H "Authorization: Bearer $TOKEN"
        -H "Accept-Profile: public" -H "Content-Profile: public"
        -H "Content-Type: application/json" -H "Prefer: return=representation")
URL="$API_URL/rest/v1/records?id=eq.$RECORD&select=id"

curl -sf "$API_URL/rest/v1/records?id=eq.$RECORD&select=properties,note,is_to_be_recorded,completed_at_troop,validation_errors,plausibility_errors,schema_id_validated_by" \
    "${COMMON[@]}" | jq '.[0]' > "$TMP/orig.json"
[[ "$(jq -r type "$TMP/orig.json")" == object ]] || { echo "record $RECORD not visible"; exit 1; }

FIELDS='{properties, note, is_to_be_recorded, completed_at_troop, validation_errors, plausibility_errors, schema_id_validated_by}'
SELECT_COLS="properties,note,is_to_be_recorded,completed_at_troop,validation_errors,plausibility_errors,schema_id_validated_by"
FAIL=0
N=0

# Write the original values back (with the app header) and check the row is
# identical again — every case starts from the same state.
restore() {
    local code
    code=$(curl -s -o /dev/null -w '%{http_code}' -X PATCH "$URL" "${COMMON[@]}" -H "X-Client-Info: $APP_HEADER" \
        -d "$(jq -c "$FIELDS" "$TMP/orig.json")")
    curl -sf "$API_URL/rest/v1/records?id=eq.$RECORD&select=$SELECT_COLS" "${COMMON[@]}" | jq '.[0]' > "$TMP/now.json"
    if ! jq -e -n --slurpfile a "$TMP/orig.json" --slurpfile b "$TMP/now.json" '$a[0] == $b[0]' >/dev/null; then
        echo "*** Wiederherstellung fehlgeschlagen (HTTP $code) — Ausgangszustand gesichert in $TMP/orig.json"
        trap - EXIT; exit 4
    fi
}

# mark: original properties + a marker unique to this case
mark() { jq -c --argjson n "$N" '.properties + {"_guard_http_test": $n}' "$TMP/orig.json"; }

# patch <label> <header|-> <json body> <expected http code>
patch() {
    local label="$1" header="$2" body="$3" want="$4" args=("${COMMON[@]}") code rows res=ok
    [[ "$header" != - ]] && args+=(-H "X-Client-Info: $header")
    code=$(curl -s -o "$TMP/out" -w '%{http_code}' -X PATCH "$URL" "${args[@]}" -d "$body")
    rows=$(jq 'if type=="array" then length else 0 end' "$TMP/out" 2>/dev/null || echo 0)
    [[ "$code" == 200 && "$rows" == 0 ]] && code="200/0rows"
    [[ "$code" == "$want" ]] || { res="*** FAIL ***"; FAIL=1; }
    printf '%-42s %-24s erwartet %-4s ist %-9s %s %s\n' "$label" \
        "$([[ $header == - ]] && echo "(kein Header)" || echo "$header")" "$want" "$code" "$res" \
        "$(jq -r 'if type=="object" then .message // "" else "" end' "$TMP/out" 2>/dev/null)"
    restore
}

BLOCKED=$([[ "$MODE" == enforce ]] && echo 403 || echo 200)

echo "Guard-HTTP-Test  API=$API_URL  Modus=$MODE  Datensatz=$RECORD"
N=1; patch "properties ändern"                  -                        "{\"properties\":$(mark)}" "$BLOCKED"
N=2; patch "properties ändern"                  "$APP_HEADER"            "{\"properties\":$(mark)}" 200
N=3; patch "properties ändern"                  "supabase-js-web/2.45.0" "{\"properties\":$(mark)}" "$BLOCKED"
N=4; patch "properties ändern"                  "supabase-dart/2.10.0"   "{\"properties\":$(mark)}" "$BLOCKED"
N=5; patch "completed_at_troop setzen"          -            '{"completed_at_troop":"2026-11-06T12:00:00Z"}' "$BLOCKED"
N=6; patch "validation_errors ändern"           -            '{"validation_errors":"[\"guard-test\"]"}' "$BLOCKED"
N=7; patch "App-Speichern (properties-edit.dart)" "$APP_HEADER" \
      "$(jq -c --argjson p "$(mark)" '{properties:$p, schema_id_validated_by:.schema_id_validated_by, local_updated_at:(now|todate), validation_errors:"[]", plausibility_errors:"[]"}' "$TMP/orig.json")" 200
N=8; patch "App: Aufnahme abschließen"          "$APP_HEADER" \
      "$(jq -c --argjson p "$(mark)" '{properties:$p, completed_at_troop:(now|todate), local_updated_at:(now|todate)}' "$TMP/orig.json")" 200
N=9; patch "note ändern"                        -            '{"note":"Guard-HTTP-Test"}' 200
N=10; patch "is_to_be_recorded umschalten"      -            "$(jq -c '{is_to_be_recorded: ((.is_to_be_recorded // false) | not)}' "$TMP/orig.json")" 200
N=11; patch "Vollzeile unverändert + note"      - \
      "$(jq -c '{properties, completed_at_troop, validation_errors, plausibility_errors, schema_id_validated_by, note:"x"}' "$TMP/orig.json")" 200
echo "Datensatz nach jedem Fall auf den Ausgangszustand zurückgesetzt und geprüft."

[[ $FAIL == 0 ]] && echo "TEST PASSED" || { echo "TEST FAILED"; exit 3; }
