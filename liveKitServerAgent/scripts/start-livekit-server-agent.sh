#!/bin/sh
set -eu

GENERATED_DIR="/working-data/generated"
LIVEKIT_CONFIG="${GENERATED_DIR}/livekit.yaml"
EGRESS_CONFIG="${GENERATED_DIR}/egress.yaml"
REDIS_CONFIG="${GENERATED_DIR}/redis.conf"
TURN_CONFIG="${GENERATED_DIR}/turnserver.conf"
NGINX_CONFIG="${GENERATED_DIR}/nginx.conf"
LIVEKIT_NGINX_CONFIG="${GENERATED_DIR}/livekit.conf"

REDIS_DATA_DIR="${WEBMEET_REDIS_DATA_DIR:-/data/redis}"
RECORDING_DIR="${WEBMEET_RECORDINGS_DIR:-/data/recordings}"
HEALTH_PORT="${WEBMEET_INFRA_HEALTH_PORT:-17000}"
HEALTH_INDEX_DIR="/tmp/webmeet-health"

PROFILE="${PLOINKY_PROFILE:-default}"
WAIT_FOR_TIMEOUT="${WEBMEET_INFRA_WAIT_TIMEOUT:-30}"

mkdir -p "$REDIS_DATA_DIR" "$RECORDING_DIR" "$HEALTH_INDEX_DIR"

PIDS=""
EXIT_REASON=""

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

require_file "$LIVEKIT_CONFIG"
require_file "$EGRESS_CONFIG"
require_file "$REDIS_CONFIG"
require_file "$TURN_CONFIG"

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

resolve_turn_external_ip() {
    if [ "${WEBMEET_TURN_EXTERNAL_IP:-}" = "auto" ]; then
        host="${WEBMEET_TURN_HOST:?WEBMEET_TURN_HOST is required when WEBMEET_TURN_EXTERNAL_IP=auto}"
        resolved=""
        if command -v getent >/dev/null 2>&1; then
            resolved=$(getent ahostsv4 "$host" 2>/dev/null | awk '{print $1; exit}')
        fi
        if [ -z "$resolved" ] && command -v dig >/dev/null 2>&1; then
            resolved=$(dig +short A "$host" 2>/dev/null | head -n 1)
        fi
        if [ -z "$resolved" ]; then
            err "failed to resolve WEBMEET_TURN_HOST='$host'"
            return 1
        fi
        export WEBMEET_TURN_RESOLVED_EXTERNAL_IP="$resolved"
        log "resolved TURN external IP: $resolved"
    fi
}

write_turn_runtime_config() {
    resolved="${WEBMEET_TURN_RESOLVED_EXTERNAL_IP:-${WEBMEET_TURN_EXTERNAL_IP:-127.0.0.1}}"
    runtime_config="${GENERATED_DIR}/turnserver.runtime.conf"
    awk -v ip="$resolved" '
        /^external-ip=/ { print "external-ip=" ip; next }
        { print }
    ' "$TURN_CONFIG" > "$runtime_config"
    echo "$runtime_config"
}

start_redis() {
    log "starting redis"
    redis-server "$REDIS_CONFIG" --dir "$REDIS_DATA_DIR" &
    REDIS_PID=$!
    PIDS="$PIDS $REDIS_PID"
    wait_for_tcp "redis" 127.0.0.1 6379
}

start_coturn() {
    log "starting coturn"
    runtime_config=$(write_turn_runtime_config)
    turnserver -c "$runtime_config" &
    COTURN_PID=$!
    PIDS="$PIDS $COTURN_PID"
    turn_port=$(awk -F= '/^listening-port=/ {print $2; exit}' "$runtime_config")
    [ -n "$turn_port" ] || turn_port=3478
    wait_for_tcp "coturn" 127.0.0.1 "$turn_port"
}

start_livekit() {
    log "starting livekit-server"
    livekit-server --config "$LIVEKIT_CONFIG" &
    LIVEKIT_PID=$!
    PIDS="$PIDS $LIVEKIT_PID"
    signal_port=$(awk '/^port:/ {print $2; exit}' "$LIVEKIT_CONFIG")
    [ -n "$signal_port" ] || signal_port=7880
    wait_for_tcp "livekit-server" 127.0.0.1 "$signal_port"
}

start_egress() {
    log "starting livekit-egress"
    EGRESS_CONFIG_FILE="$EGRESS_CONFIG" egress &
    EGRESS_PID=$!
    PIDS="$PIDS $EGRESS_PID"
    egress_health_port=$(awk '/^[[:space:]]*health_port:/ {print $2; exit}' "$EGRESS_CONFIG")
    [ -n "$egress_health_port" ] || egress_health_port=7980
    wait_for_tcp "livekit-egress" 127.0.0.1 "$egress_health_port"
}

maybe_start_nginx() {
    if [ "$PROFILE" != "prod" ]; then
        return 0
    fi
    if [ ! -f "$NGINX_CONFIG" ] || [ ! -f "$LIVEKIT_NGINX_CONFIG" ]; then
        log "nginx config missing; skipping TLS terminator"
        return 0
    fi
    hostname="${WEBMEET_TLS_HOSTNAME:-}"
    if [ -z "$hostname" ]; then
        err "prod profile requires WEBMEET_TLS_HOSTNAME for nginx"
        return 1
    fi
    cert_path="/etc/letsencrypt/live/${hostname}/fullchain.pem"
    if [ ! -f "$cert_path" ]; then
        log "waiting for TLS certificate at $cert_path"
        # In prod, certbot writes the cert below; we wait up to 5 minutes the
        # first time, then start nginx asynchronously once it appears.
        ( deadline=$(( $(date +%s) + 300 ))
          while [ ! -f "$cert_path" ] && [ "$(date +%s)" -lt "$deadline" ]; do
              sleep 5
          done
          if [ -f "$cert_path" ]; then
              log "starting nginx after cert is present"
              nginx -c "$NGINX_CONFIG" -g 'daemon off;' &
          else
              err "TLS certificate did not appear; nginx not started"
          fi
        ) &
        return 0
    fi
    log "starting nginx"
    nginx -c "$NGINX_CONFIG" -g 'daemon off;' &
    NGINX_PID=$!
    PIDS="$PIDS $NGINX_PID"
}

maybe_start_certbot_loop() {
    if [ "$PROFILE" != "prod" ]; then
        return 0
    fi
    auto_issue="${WEBMEET_CERTBOT_AUTO_ISSUE:-false}"
    hostname="${WEBMEET_TLS_HOSTNAME:-}"
    if [ -z "$hostname" ]; then
        return 0
    fi
    email="${WEBMEET_CERT_EMAIL:-}"
    interval="${WEBMEET_CERTBOT_RENEW_INTERVAL_SECONDS:-43200}"
    webroot="/var/www/certbot"
    live_dir="/etc/letsencrypt/live/${hostname}"
    mkdir -p "$webroot"

    if [ ! -d "$live_dir" ] && [ "$auto_issue" = "true" ]; then
        if [ -z "$email" ]; then
            err "WEBMEET_CERTBOT_AUTO_ISSUE=true requires WEBMEET_CERT_EMAIL"
            return 1
        fi
        log "issuing initial cert via standalone HTTP-01"
        certbot certonly --standalone \
            -d "$hostname" \
            --email "$email" \
            --agree-tos --non-interactive --no-eff-email || \
            err "initial certbot issuance failed"
    fi

    (
        while true; do
            if [ -d "$live_dir" ]; then
                certbot renew --webroot --webroot-path "$webroot" --no-random-sleep-on-renew >/dev/null 2>&1 || true
            fi
            sleep "$interval"
        done
    ) &
    CERTBOT_PID=$!
    PIDS="$PIDS $CERTBOT_PID"
}

start_health_listener() {
    printf 'ok\n' > "${HEALTH_INDEX_DIR}/index.html"
    log "starting health endpoint on 0.0.0.0:${HEALTH_PORT}"
    ( cd "${HEALTH_INDEX_DIR}" && python3 -m http.server "${HEALTH_PORT}" --bind 0.0.0.0 >/dev/null 2>&1 ) &
    HEALTH_PID=$!
    PIDS="$PIDS $HEALTH_PID"
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
}

trap 'EXIT_REASON=signal; shutdown_children; exit 0' INT TERM
trap 'rc=$?; shutdown_children; exit $rc' EXIT

resolve_turn_external_ip
start_redis
start_coturn
start_livekit
start_egress
maybe_start_nginx
maybe_start_certbot_loop
start_health_listener

log "all required services started"

# Watch supervised pids; exit nonzero if any required service dies.
while true; do
    for pid in $REDIS_PID $COTURN_PID $LIVEKIT_PID $EGRESS_PID $HEALTH_PID; do
        if ! kill -0 "$pid" 2>/dev/null; then
            err "supervised service pid $pid exited; tearing down"
            exit 1
        fi
    done
    sleep 5
done
