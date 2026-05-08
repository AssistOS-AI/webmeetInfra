#!/usr/bin/env bash
set -euo pipefail

workspace_root="${PLOINKY_CWD:-$PWD}"
agent_dir="${workspace_root}/.ploinky/agents/webmeetLivekitNginx"
data_dir="${workspace_root}/.ploinky/data/webmeetTls"

mkdir -p "$agent_dir" "$data_dir/letsencrypt" "$data_dir/webroot"

hostname="${WEBMEET_TLS_HOSTNAME:?WEBMEET_TLS_HOSTNAME is required}"
http_port="${WEBMEET_TLS_HTTP_PORT:-80}"
https_port="${WEBMEET_TLS_HTTPS_PORT:-443}"
upstream="${WEBMEET_LIVEKIT_UPSTREAM:-http://127.0.0.1:7880}"

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

cat > "${agent_dir}/start.sh" <<'STARTEOF'
#!/bin/sh
set -eu

CERT="/etc/letsencrypt/live/${WEBMEET_TLS_HOSTNAME}/fullchain.pem"

if [ ! -f "$CERT" ]; then
  echo "[nginx-agent] waiting for certificate at $CERT (certbot agent must populate /etc/letsencrypt first)..."
  while [ ! -f "$CERT" ]; do
    sleep 5
  done
fi

nginx -g 'daemon off;' &
NGINX_PID=$!

LAST_HASH="$(sha256sum "$CERT" | awk '{print $1}')"
(
  while sleep 60; do
    if [ -f "$CERT" ]; then
      H="$(sha256sum "$CERT" | awk '{print $1}')"
      if [ "$H" != "$LAST_HASH" ]; then
        echo "[nginx-agent] certificate changed; reloading nginx"
        nginx -s reload || true
        LAST_HASH="$H"
      fi
    fi
  done
) &

wait "$NGINX_PID"
STARTEOF

chmod +x "${agent_dir}/start.sh"
