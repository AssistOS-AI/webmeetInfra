#!/usr/bin/env bash
set -euo pipefail

workspace_root="${PLOINKY_CWD:-$PWD}"
profile="${PLOINKY_PROFILE:-default}"
agent_dir="${workspace_root}/.ploinky/agents/liveKitServerAgent"
data_dir="${workspace_root}/.ploinky/data/webmeet"
tls_dir="${workspace_root}/.ploinky/data/webmeetTls"

mkdir -p \
    "$agent_dir" \
    "$data_dir/redis" \
    "$data_dir/recordings" \
    "$tls_dir/letsencrypt" \
    "$tls_dir/webroot"

api_key="${WEBMEET_LIVEKIT_API_KEY:?WEBMEET_LIVEKIT_API_KEY is required}"
api_secret="${WEBMEET_LIVEKIT_API_SECRET:?WEBMEET_LIVEKIT_API_SECRET is required}"
turn_password="${WEBMEET_TURN_PASSWORD:?WEBMEET_TURN_PASSWORD is required}"
log_level="${WEBMEET_LIVEKIT_LOG_LEVEL:-info}"
force_tcp="${WEBMEET_LIVEKIT_FORCE_TCP:-false}"
use_external_ip_default="false"
node_ip="${WEBMEET_LIVEKIT_NODE_IP:-}"

signal_port=7880
rtc_tcp_port=7881
rtc_port_range_start=7882
rtc_port_range_end=7892
health_port="${WEBMEET_INFRA_HEALTH_PORT:-17000}"
turn_listen_port="${WEBMEET_TURN_PORT:-3478}"
turn_min_port="${WEBMEET_TURN_MIN_PORT:-20000}"
turn_max_port="${WEBMEET_TURN_MAX_PORT:-20010}"
turn_realm="${WEBMEET_TURN_REALM:-webmeet.local}"
turn_user="${WEBMEET_TURN_USER:-webmeet}"
turn_external_ip="${WEBMEET_TURN_EXTERNAL_IP:-127.0.0.1}"
turn_host="${WEBMEET_TURN_HOST:-127.0.0.1}"

case "$profile" in
    dev)
        signal_port=17880
        rtc_tcp_port=17881
        rtc_port_range_start=17882
        rtc_port_range_end=17892
        node_ip="${node_ip:-127.0.0.1}"
        ;;
    prod)
        use_external_ip_default="true"
        ;;
esac

use_external_ip="${WEBMEET_LIVEKIT_USE_EXTERNAL_IP:-$use_external_ip_default}"
redis_address="${WEBMEET_LIVEKIT_REDIS_ADDRESS:-127.0.0.1:6379}"
egress_ws_url="${WEBMEET_LIVEKIT_INTERNAL_WS_URL:-ws://127.0.0.1:${signal_port}}"
egress_redis_address="${WEBMEET_EGRESS_REDIS_ADDRESS:-127.0.0.1:6379}"

validate_port() {
    local name="$1" value="$2"
    case "$value" in
        ''|*[!0-9]*)
            echo "[liveKitServerAgent] ERROR: $name must be a positive integer (got '$value')." >&2
            exit 1
            ;;
    esac
    if [ "$value" -lt 1 ] || [ "$value" -gt 65535 ]; then
        echo "[liveKitServerAgent] ERROR: $name must be in 1..65535 (got '$value')." >&2
        exit 1
    fi
}

validate_port WEBMEET_INFRA_HEALTH_PORT "$health_port"
validate_port WEBMEET_TURN_PORT "$turn_listen_port"
validate_port WEBMEET_TURN_MIN_PORT "$turn_min_port"
validate_port WEBMEET_TURN_MAX_PORT "$turn_max_port"

if [ "$turn_min_port" -gt "$turn_max_port" ]; then
    echo "[liveKitServerAgent] ERROR: WEBMEET_TURN_MIN_PORT > WEBMEET_TURN_MAX_PORT." >&2
    exit 1
fi

{
    printf 'port: %s\n' "$signal_port"
    printf 'logging:\n  level: %s\n' "$log_level"
    printf 'rtc:\n'
    printf '  tcp_port: %s\n' "$rtc_tcp_port"
    printf '  port_range_start: %s\n' "$rtc_port_range_start"
    printf '  port_range_end: %s\n' "$rtc_port_range_end"
    printf '  use_external_ip: %s\n' "$use_external_ip"
    printf '  force_tcp: %s\n' "$force_tcp"
    if [ -n "$node_ip" ] && [ "$use_external_ip" != "true" ]; then
        printf '  node_ip: %s\n' "$node_ip"
    fi
    printf 'redis:\n  address: %s\n' "$redis_address"
    printf 'keys:\n  %s: %s\n' "$api_key" "$api_secret"
} > "${agent_dir}/livekit.yaml"

{
    printf 'api_key: %s\n' "$api_key"
    printf 'api_secret: %s\n' "$api_secret"
    printf 'ws_url: %s\n' "$egress_ws_url"
    printf 'insecure: true\n'
    printf 'redis:\n  address: %s\n' "$egress_redis_address"
    printf 'health_port: 7980\n'
} > "${agent_dir}/egress.yaml"

{
    printf 'bind 127.0.0.1\n'
    printf 'port 6379\n'
    printf 'dir /data/redis\n'
    printf 'save 60 1\n'
    printf 'loglevel warning\n'
    printf 'appendonly no\n'
} > "${agent_dir}/redis.conf"

{
    printf 'listening-port=%s\n' "$turn_listen_port"
    printf 'min-port=%s\n' "$turn_min_port"
    printf 'max-port=%s\n' "$turn_max_port"
    printf 'external-ip=%s\n' "$turn_external_ip"
    printf 'realm=%s\n' "$turn_realm"
    printf 'fingerprint\n'
    printf 'lt-cred-mech\n'
    printf 'no-cli\n'
    printf 'no-tls\n'
    printf 'no-dtls\n'
    printf 'user=%s:%s\n' "$turn_user" "$turn_password"
    if [ "$turn_host" != "$turn_external_ip" ] && [ "$turn_external_ip" = "auto" ]; then
        # The supervisor script will resolve WEBMEET_TURN_HOST at runtime when
        # external IP is 'auto'; coturn config still needs a static fallback.
        printf '# external-ip resolved dynamically at startup\n'
    fi
} > "${agent_dir}/turnserver.conf"

if [ "$profile" = "prod" ]; then
    hostname="${WEBMEET_TLS_HOSTNAME:?WEBMEET_TLS_HOSTNAME is required in prod profile}"
    http_port="${WEBMEET_TLS_HTTP_PORT:-80}"
    https_port="${WEBMEET_TLS_HTTPS_PORT:-443}"
    upstream="${WEBMEET_LIVEKIT_UPSTREAM:-http://127.0.0.1:7880}"

    validate_port WEBMEET_TLS_HTTP_PORT "$http_port"
    validate_port WEBMEET_TLS_HTTPS_PORT "$https_port"

    if ! printf '%s' "$hostname" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$'; then
        echo "[liveKitServerAgent] ERROR: WEBMEET_TLS_HOSTNAME is not a valid DNS name (got '$hostname')." >&2
        exit 1
    fi

    if ! printf '%s' "$upstream" | grep -Eq '^https?://[A-Za-z0-9._-]+(:[0-9]+)?(/[A-Za-z0-9._/-]*)?$'; then
        echo "[liveKitServerAgent] ERROR: WEBMEET_LIVEKIT_UPSTREAM must be http(s)://host[:port][/path] (got '$upstream')." >&2
        exit 1
    fi

    cat > "${agent_dir}/livekit.conf" <<EOF
server {
    listen ${http_port} default_server;
    server_name ${hostname};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen ${https_port} ssl;
    server_name ${hostname};

    ssl_certificate /etc/letsencrypt/live/${hostname}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${hostname}/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    location / {
        proxy_pass ${upstream};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
}
EOF

    cat > "${agent_dir}/nginx.conf" <<'NGINXEOF'
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /run/nginx-livekit.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 65;

    include /working-data/generated/livekit.conf;
}
NGINXEOF
fi

# Mirror the canonical startup script into the workspace so operators can
# inspect or override it without rebuilding the container image.
script_src_dir="$(cd "$(dirname "$0")/.." && pwd)"
if [ -d "$script_src_dir" ]; then
    mkdir -p "${agent_dir}/scripts/health"
    cp "$script_src_dir/start-livekit-server-agent.sh" "${agent_dir}/scripts/start-livekit-server-agent.sh"
    cp "$script_src_dir/health/livekit-server-agent-health.sh" "${agent_dir}/scripts/health/livekit-server-agent-health.sh"
    chmod +x "${agent_dir}/scripts/start-livekit-server-agent.sh"
    chmod +x "${agent_dir}/scripts/health/livekit-server-agent-health.sh"
fi
