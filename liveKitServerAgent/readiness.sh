#!/bin/sh
# Runs inside the liveKitServerAgent container as its script readiness probe.
# The pinned image contract includes nc; its absence is a hard image failure.
# Deliberately does not use `set -e` so all three fixed internal endpoints are
# checked and reported in one run.
set -u

REDIS_PORT=6379
LIVEKIT_PORT=7880
EGRESS_HEALTH_PORT=7980
HOST="127.0.0.1"

log() {
    printf '[liveKitServerAgent readiness] %s\n' "$1"
}

check_tcp() {
    host="$1"
    port="$2"
    nc -z -w 2 "$host" "$port" >/dev/null 2>&1
}

overall_ok=1

if ! command -v nc >/dev/null 2>&1; then
    log "ERROR: pinned image is missing nc."
    exit 1
fi

if ! check_tcp "$HOST" "$REDIS_PORT"; then
    log "ERROR: redis is not reachable on ${HOST}:${REDIS_PORT}."
    overall_ok=0
fi

if ! check_tcp "$HOST" "$LIVEKIT_PORT"; then
    log "ERROR: livekit-server is not reachable on ${HOST}:${LIVEKIT_PORT}."
    overall_ok=0
fi

if ! check_tcp "$HOST" "$EGRESS_HEALTH_PORT"; then
    log "ERROR: livekit-egress is not reachable on ${HOST}:${EGRESS_HEALTH_PORT}."
    overall_ok=0
fi

if [ "$overall_ok" -eq 1 ]; then
    log "ready"
    exit 0
fi
exit 1
