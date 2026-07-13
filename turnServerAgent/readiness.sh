#!/bin/sh
# Runs inside the pinned Coturn container through Ploinky's script-based
# readiness probe. The pinned image includes awk, openssl, timeout, and
# turnutils_stunclient; their absence is a contract failure, not a soft skip.
set -u

PROFILE="${PLOINKY_PROFILE:-default}"
PID_FILE="/tmp/turnserver.pid"

log() {
    printf '[turnServerAgent readiness] %s\n' "$1"
}

check_process_alive() {
    [ -f "$PID_FILE" ] || return 1
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    case "$pid" in
        ''|*[!0-9]*)
            return 1
            ;;
    esac
    kill -0 "$pid" 2>/dev/null
}

port_bound_in_file() {
    proto="$1"
    port_dec="$2"
    file="$3"
    [ -r "$file" ] || return 1
    hex="$(printf '%04X' "$port_dec")"
    if [ "$proto" = "tcp" ]; then
        awk -v want="$hex" 'NR > 1 { n=split($2,a,":"); if (a[n] == want && $4 == "0A") { found=1; exit } } END { exit(found ? 0 : 1) }' "$file" 2>/dev/null
    else
        awk -v want="$hex" 'NR > 1 { n=split($2,a,":"); if (a[n] == want) { found=1; exit } } END { exit(found ? 0 : 1) }' "$file" 2>/dev/null
    fi
}

port_bound_v4() {
    port_bound_in_file "$1" "$2" "/proc/net/$1"
}

port_bound_v6() {
    port_bound_in_file "$1" "$2" "/proc/net/$1"6
}

check_prod_tls() {
    cert_path="${WEBMEET_TURN_TLS_CERT_PATH:-/etc/turnserver/tls/fullchain.pem}"
    key_path="${WEBMEET_TURN_TLS_KEY_PATH:-/etc/turnserver/tls/privkey.pem}"
    turn_host="${WEBMEET_TURN_HOST:-}"

    command -v openssl >/dev/null 2>&1 || {
        log "ERROR: pinned image is missing openssl."
        return 1
    }
    [ -n "$turn_host" ] || {
        log "ERROR: WEBMEET_TURN_HOST is empty in prod."
        return 1
    }
    [ -f "$cert_path" ] && [ -r "$cert_path" ] || {
        log "ERROR: TLS certificate is unreadable at '$cert_path'."
        return 1
    }
    [ -f "$key_path" ] && [ -r "$key_path" ] || {
        log "ERROR: TLS private key is unreadable at '$key_path'."
        return 1
    }
    openssl x509 -in "$cert_path" -noout -checkend 0 >/dev/null 2>&1 || {
        log "ERROR: TLS certificate is invalid or expired."
        return 1
    }
    openssl x509 -in "$cert_path" -noout -checkhost "$turn_host" >/dev/null 2>&1 || {
        log "ERROR: TLS certificate does not cover '$turn_host'."
        return 1
    }
    cert_public_key="$(openssl x509 -in "$cert_path" -pubkey -noout \
        | openssl pkey -pubin -outform DER 2>/dev/null \
        | openssl dgst -sha256 2>/dev/null)" || return 1
    private_public_key="$(openssl pkey -in "$key_path" -pubout -outform DER 2>/dev/null \
        | openssl dgst -sha256 2>/dev/null)" || return 1
    [ -n "$cert_public_key" ] && [ "$cert_public_key" = "$private_public_key" ] || {
        log "ERROR: TLS certificate and private key do not match."
        return 1
    }
}

run_stun_binding_smoke() {
    command -v timeout >/dev/null 2>&1 || {
        log "ERROR: pinned image is missing timeout."
        return 1
    }
    command -v turnutils_stunclient >/dev/null 2>&1 || {
        log "ERROR: pinned image is missing turnutils_stunclient."
        return 1
    }

    # Keep credentials out of argv. Nested ploinky-box workloads share an
    # enclosing /proc view, so even a short-lived credential argument would
    # expose the TURN secret to unrelated sibling agents. End-to-end REST auth
    # and the peer ACL are proved by the relay-only browser smoke suite.
    timeout 5 turnutils_stunclient -p 3478 127.0.0.1 >/dev/null 2>&1 || {
        log "ERROR: STUN Binding probe against UDP 3478 failed."
        return 1
    }
}

overall_ok=1

if ! check_process_alive; then
    log "ERROR: turnserver process is not running."
    overall_ok=0
fi
if ! port_bound_v4 udp 3478; then
    log "ERROR: IPv4 UDP 3478 is not bound."
    overall_ok=0
fi
if ! port_bound_v4 tcp 3478; then
    log "ERROR: IPv4 TCP 3478 is not bound."
    overall_ok=0
fi
if port_bound_v6 udp 3478 || port_bound_v6 tcp 3478; then
    log "ERROR: an IPv6 listener is bound on 3478."
    overall_ok=0
fi

if [ "$PROFILE" = "prod" ]; then
    if ! port_bound_v4 tcp 5349; then
        log "ERROR: IPv4 TURN/TLS 5349 is not bound."
        overall_ok=0
    fi
    if port_bound_v6 tcp 5349 || port_bound_v6 udp 5349; then
        log "ERROR: an IPv6 listener is bound on 5349."
        overall_ok=0
    fi
    if ! check_prod_tls; then
        overall_ok=0
    fi
fi

if [ "$overall_ok" -eq 1 ] && ! run_stun_binding_smoke; then
    overall_ok=0
fi

if [ "$overall_ok" -eq 1 ]; then
    log "ready"
    exit 0
fi
exit 1
