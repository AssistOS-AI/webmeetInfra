#!/bin/sh
set -eu

# Preinstall has already materialized the required private configs. Re-exec
# immediately without secrets that the supervisor and its children never need,
# so long-lived process environments do not duplicate those credentials.
if [ "${WEBMEET_RUNTIME_ENV_SCRUBBED:-}" != "1" ]; then
    exec env \
        -u WEBMEET_TURN_AUTH_SECRET \
        -u WEBMEET_LIVEKIT_API_KEY \
        -u WEBMEET_LIVEKIT_API_SECRET \
        WEBMEET_RUNTIME_ENV_SCRUBBED=1 \
        sh "$0" "$@"
fi

GENERATED_DIR="/working-data/generated"
LIVEKIT_TEMPLATE="${GENERATED_DIR}/livekit.yaml"
EGRESS_CONFIG="${GENERATED_DIR}/egress.yaml"
REDIS_CONFIG="${GENERATED_DIR}/redis.conf"
PROFILE="${PLOINKY_PROFILE:-default}"
RUNTIME_DIR="$(mktemp -d /tmp/livekit-server-agent.XXXXXX)"
LIVEKIT_CONFIG="${RUNTIME_DIR}/livekit.yaml"

REDIS_DATA_DIR="/data/redis"
RECORDING_DIR="/data/recordings"
WAIT_FOR_TIMEOUT=30

mkdir -p "$REDIS_DATA_DIR" "$RECORDING_DIR"

PIDS=""

log() {
    printf '[liveKitServerAgent] %s\n' "$1"
}

err() {
    printf '[liveKitServerAgent] ERROR: %s\n' "$1" >&2
}

require_file() {
    if [ ! -f "$1" ]; then
        err "missing generated file '$1'; ensure preinstall ran"
        exit 1
    fi
}

require_file "$LIVEKIT_TEMPLATE"
require_file "$EGRESS_CONFIG"
require_file "$REDIS_CONFIG"

command -v nc >/dev/null 2>&1 || {
    err "pinned image is missing nc"
    exit 1
}

is_ipv4() {
    printf '%s' "$1" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'
}

resolve_local_node_ip() {
    command -v getent >/dev/null 2>&1 || {
        err "getent is required to resolve the TURN trust-zone peer"
        return 1
    }
    command -v ip >/dev/null 2>&1 || {
        err "ip is required to select the local LiveKit TURN trust-zone address"
        return 1
    }
    attempt=0
    while [ "$attempt" -lt "$WAIT_FOR_TIMEOUT" ]; do
        peer_addresses="$(getent ahostsv4 turnserveragent 2>/dev/null \
            | awk '{print $1}' \
            | sort -u \
            | sed '/^$/d' || true)"
        peer_count="$(printf '%s\n' "$peer_addresses" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
        if [ "$peer_count" = "1" ] && is_ipv4 "$peer_addresses"; then
            local_address="$(ip -4 route get "$peer_addresses" 2>/dev/null \
                | awk '{ for (i = 1; i <= NF; i++) if ($i == "src" && (i + 1) <= NF) { print $(i + 1); exit } }' \
                || true)"
            if is_ipv4 "$local_address"; then
                printf '%s\n' "$local_address"
                return 0
            fi
        fi
        attempt=$((attempt + 1))
        sleep 1
    done
    err "turnserveragent did not resolve to one reachable TURN trust-zone IPv4 address within ${WAIT_FOR_TIMEOUT}s"
    return 1
}

prepare_livekit_config() {
    cp "$LIVEKIT_TEMPLATE" "$LIVEKIT_CONFIG"
    chmod 0600 "$LIVEKIT_CONFIG"
    case "$PROFILE" in
        default|dev)
            local_node_ip="$(resolve_local_node_ip)" || exit 1
            marker_count="$(grep -c '__WEBMEET_LOCAL_NODE_IP__' "$LIVEKIT_CONFIG" || true)"
            [ "$marker_count" = "1" ] || {
                err "local LiveKit config must contain exactly one node-IP marker"
                exit 1
            }
            sed "s/__WEBMEET_LOCAL_NODE_IP__/${local_node_ip}/" "$LIVEKIT_CONFIG" > "${LIVEKIT_CONFIG}.resolved"
            chmod 0600 "${LIVEKIT_CONFIG}.resolved"
            mv "${LIVEKIT_CONFIG}.resolved" "$LIVEKIT_CONFIG"
            log "resolved local relay-only LiveKit media address on the webmeet-turn bridge"
            ;;
        prod)
            if grep -q '__WEBMEET_LOCAL_NODE_IP__' "$LIVEKIT_CONFIG"; then
                err "prod LiveKit config contains a local node-IP marker"
                exit 1
            fi
            ;;
        *)
            err "unknown PLOINKY_PROFILE '$PROFILE'"
            exit 1
            ;;
    esac
}

prepare_livekit_config

wait_for_tcp() {
    label="$1"
    host="$2"
    port="$3"
    deadline=$(( $(date +%s) + WAIT_FOR_TIMEOUT ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if nc -z -w 1 "$host" "$port" >/dev/null 2>&1; then
            log "$label is ready on $host:$port"
            return 0
        fi
        sleep 1
    done
    err "$label did not become ready on $host:$port within ${WAIT_FOR_TIMEOUT}s"
    return 1
}

start_redis() {
    log "starting redis"
    redis-server "$REDIS_CONFIG" --dir "$REDIS_DATA_DIR" &
    REDIS_PID=$!
    PIDS="$PIDS $REDIS_PID"
    wait_for_tcp "redis" 127.0.0.1 6379
}

start_livekit() {
    log "starting livekit-server"
    livekit-server --config "$LIVEKIT_CONFIG" &
    LIVEKIT_PID=$!
    PIDS="$PIDS $LIVEKIT_PID"
    wait_for_tcp "livekit-server" 127.0.0.1 7880
}

start_egress() {
    log "starting livekit-egress"
    EGRESS_CONFIG_FILE="$EGRESS_CONFIG" egress &
    EGRESS_PID=$!
    PIDS="$PIDS $EGRESS_PID"
    wait_for_tcp "livekit-egress" 127.0.0.1 7980
}

shutdown_children() {
    log "stopping supervised services"
    for pid in $PIDS; do
        [ -n "$pid" ] || continue
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
    done
    sleep 1
    for pid in $PIDS; do
        [ -n "$pid" ] || continue
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null || true
        fi
    done
    rm -rf "$RUNTIME_DIR"
}

trap 'shutdown_children; exit 0' INT TERM
trap 'rc=$?; shutdown_children; exit $rc' EXIT

start_redis
start_livekit
start_egress

log "all required services started"

# Watch supervised pids; exit nonzero if any required service dies.
while true; do
    for pid in $REDIS_PID $LIVEKIT_PID $EGRESS_PID; do
        if ! kill -0 "$pid" 2>/dev/null; then
            err "supervised service pid $pid exited; tearing down"
            exit 1
        fi
    done
    sleep 5
done
