#!/usr/bin/env bash
# ============================================================================
# Switch the public API gateway between Envoy (api-gw) and Kong (rollback).
# ============================================================================
#   scripts/gateway-switch.sh status   show which gateway is live, change nothing
#   scripts/gateway-switch.sh envoy    Envoy takes host port KONG_HTTP_PORT and the alias `kong`
#   scripts/gateway-switch.sh kong     Kong takes them back, Envoy returns to 127.0.0.1:8001
#
# The mode lives in three keys of .env (see the Envoy block in docker-compose.yaml):
#   COMPOSE_PROFILES, GW_ENVOY_PUBLISH, GW_ENVOY_EXTRA_ALIAS
# The script edits only those keys, keeps a copy of the previous .env next to it and never
# sources .env (the production .env is not shell-safe).
#
# Only the two gateway containers are touched (`--no-deps`); no other service is recreated.
# Expect a few seconds without a gateway; a reverse proxy in front may answer 503 for up to a
# minute if it has marked the backend as failed.
#
# Exit 0 = the requested gateway is live and the checks passed, 1 = usage, 2 = check failed.
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

ENV_FILE=.env
ENVOY_CTR=supabase-envoy
KONG_CTR=supabase-kong

env_get() { # env_get KEY -> value of the last KEY= line, empty if absent
    grep -E "^$1=" "$ENV_FILE" | tail -n 1 | cut -d= -f2- || true
}

env_set() { # env_set KEY VALUE -> replace every KEY= line, or append
    local key="$1" value="$2" tmp
    tmp="$(mktemp)"
    awk -v k="$key" -v v="$value" '
        BEGIN { done = 0 }
        index($0, k "=") == 1 { if (!done) { print k "=" v; done = 1 } ; next }
        { print }
        END { if (!done) print k "=" v }
    ' "$ENV_FILE" >"$tmp"
    cat "$tmp" >"$ENV_FILE" # keep owner and mode of .env
    rm -f "$tmp"
}

env_unset() { # env_unset KEY -> drop every KEY= line
    local key="$1" tmp
    tmp="$(mktemp)"
    awk -v k="$key" 'index($0, k "=") != 1 { print }' "$ENV_FILE" >"$tmp"
    cat "$tmp" >"$ENV_FILE"
    rm -f "$tmp"
}

running() { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null || echo false)" = "true" ]; }

publishes_port() { # publishes_port CONTAINER HOSTPORT
    docker port "$1" 8000/tcp 2>/dev/null | grep -Eq "[:.]$2\$"
}

has_kong_name() { # does the running container answer to the DNS name `kong` on supabase-net?
    docker inspect -f '{{range $n, $c := .NetworkSettings.Networks}}{{$n}} {{join $c.Aliases ","}} {{join $c.DNSNames ","}}{{"\n"}}{{end}}' "$1" 2>/dev/null |
        grep supabase-net | tr ' ,' '\n\n' | grep -qx kong
}

status() {
    local port_spec host_port live_port=0 live_name=0 c
    port_spec="$(env_get KONG_HTTP_PORT)"
    host_port="${port_spec##*:}"
    echo ".env: COMPOSE_PROFILES='$(env_get COMPOSE_PROFILES)' GW_ENVOY_PUBLISH='$(env_get GW_ENVOY_PUBLISH)' GW_ENVOY_EXTRA_ALIAS='$(env_get GW_ENVOY_EXTRA_ALIAS)' KONG_HTTP_PORT='$port_spec'"
    for c in "$ENVOY_CTR" "$KONG_CTR"; do
        if running "$c"; then
            local p=no n=no
            if publishes_port "$c" "$host_port"; then p=yes; live_port=$((live_port + 1)); fi
            if has_kong_name "$c"; then n=yes; live_name=$((live_name + 1)); fi
            echo "$c: running, publishes :$host_port=$p, answers to 'kong'=$n ($(docker port "$c" 8000/tcp 2>/dev/null | tr '\n' ' '))"
        else
            echo "$c: not running"
        fi
    done
    STATUS_PORT_OWNERS=$live_port
    STATUS_NAME_OWNERS=$live_name
}

check() { # check CONTAINER-that-must-be-live
    local want="$1" host_port
    host_port="$(env_get KONG_HTTP_PORT)"; host_port="${host_port##*:}"
    status
    local ok=1
    [ "$STATUS_PORT_OWNERS" = 1 ] || { echo "FAIL: $STATUS_PORT_OWNERS containers publish host port $host_port (want 1)"; ok=0; }
    [ "$STATUS_NAME_OWNERS" = 1 ] || { echo "FAIL: $STATUS_NAME_OWNERS running containers answer to 'kong' (want 1)"; ok=0; }
    publishes_port "$want" "$host_port" || { echo "FAIL: $want does not publish host port $host_port"; ok=0; }
    has_kong_name "$want" || { echo "FAIL: $want does not answer to 'kong'"; ok=0; }
    if [ "$ok" = 1 ]; then echo "OK: $want is the live gateway"; else exit 2; fi
}

backup_env() {
    local copy="$ENV_FILE.bak-gateway-$(date +%Y%m%d_%H%M%S)"
    cp -p "$ENV_FILE" "$copy"
    echo "previous .env saved as $copy"
}

case "${1:-}" in
status)
    status
    ;;
envoy)
    port_spec="$(env_get KONG_HTTP_PORT)"
    [ -n "$port_spec" ] || { echo "KONG_HTTP_PORT is not set in $ENV_FILE"; exit 2; }
    backup_env
    docker stop "$KONG_CTR" >/dev/null 2>&1 || true
    env_set COMPOSE_PROFILES ""
    env_set GW_ENVOY_PUBLISH "$port_spec"
    env_set GW_ENVOY_EXTRA_ALIAS kong
    docker compose up -d --no-deps --force-recreate api-gw
    check "$ENVOY_CTR"
    ;;
kong)
    backup_env
    docker stop "$ENVOY_CTR" >/dev/null 2>&1 || true
    env_set COMPOSE_PROFILES gw-kong
    env_unset GW_ENVOY_PUBLISH
    env_unset GW_ENVOY_EXTRA_ALIAS
    docker compose up -d --no-deps kong
    docker compose up -d --no-deps --force-recreate api-gw # back to the loopback shadow
    check "$KONG_CTR"
    ;;
*)
    sed -n '2,8p' "$0"
    exit 1
    ;;
esac
