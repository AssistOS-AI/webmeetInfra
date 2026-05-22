#!/bin/sh
set -eu

# Smoke checks the liveKitServerAgent supervisor health endpoint and a few of
# the supervised service ports. Intended for ad-hoc operator use and for the
# Ploinky readiness probe fallback.

HOST="${WEBMEET_INFRA_HEALTH_HOST:-127.0.0.1}"
HEALTH_PORT="${WEBMEET_INFRA_HEALTH_PORT:-17000}"
LIVEKIT_HOST="${WEBMEET_INFRA_LIVEKIT_HOST:-127.0.0.1}"
LIVEKIT_PORT="${WEBMEET_INFRA_LIVEKIT_PORT:-7880}"
REDIS_PORT="${WEBMEET_INFRA_REDIS_PORT:-6379}"

fail() {
    printf '[health] %s\n' "$1" >&2
    exit 1
}

check_tcp() {
    label="$1"
    host="$2"
    port="$3"
    if command -v nc >/dev/null 2>&1; then
        nc -z "$host" "$port" >/dev/null 2>&1 || fail "$label tcp $host:$port unreachable"
    else
        # Fallback: try /dev/tcp under bash; otherwise rely on curl.
        ( exec 3<>/dev/tcp/"$host"/"$port" ) 2>/dev/null || \
            curl -fsS --max-time 1 -o /dev/null "http://$host:$port" >/dev/null 2>&1 || \
            fail "$label tcp $host:$port unreachable"
    fi
}

if command -v curl >/dev/null 2>&1; then
    curl -fsS --max-time 1 -o /dev/null "http://${HOST}:${HEALTH_PORT}/" \
        || fail "health endpoint http://${HOST}:${HEALTH_PORT}/ failed"
else
    check_tcp "health" "$HOST" "$HEALTH_PORT"
fi

check_tcp "redis" "$HOST" "$REDIS_PORT"
check_tcp "livekit" "$LIVEKIT_HOST" "$LIVEKIT_PORT"

printf 'ok\n'
