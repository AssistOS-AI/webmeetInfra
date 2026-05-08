#!/usr/bin/env bash
set -euo pipefail

profile="${PLOINKY_PROFILE:-default}"
if [ "$profile" != "prod" ]; then
    echo "[webmeetLivekitCertbot] ERROR: this agent runs only in the 'prod' profile (active profile: '$profile')." >&2
    echo "[webmeetLivekitCertbot] To enable, switch to prod first: ploinky profile prod" >&2
    exit 1
fi

workspace_root="${PLOINKY_CWD:-$PWD}"
agent_dir="${workspace_root}/.ploinky/agents/webmeetLivekitCertbot"
data_dir="${workspace_root}/.ploinky/data/webmeetTls"

mkdir -p "$agent_dir" "$data_dir/letsencrypt" "$data_dir/webroot"

cat > "${agent_dir}/start.sh" <<'STARTEOF'
#!/bin/sh
set -eu

HOST="${WEBMEET_TLS_HOSTNAME:?WEBMEET_TLS_HOSTNAME is required}"
EMAIL="${WEBMEET_CERT_EMAIL:-}"
INTERVAL="${WEBMEET_CERTBOT_RENEW_INTERVAL_SECONDS:-43200}"
AUTO_ISSUE="${WEBMEET_CERTBOT_AUTO_ISSUE:-false}"
WEBROOT="/var/www/certbot"
LIVE_DIR="/etc/letsencrypt/live/${HOST}"

echo "[certbot-agent] hostname=${HOST} interval=${INTERVAL}s auto_issue=${AUTO_ISSUE}"

if [ ! -d "$LIVE_DIR" ]; then
  if [ "$AUTO_ISSUE" = "true" ]; then
    if [ -z "$EMAIL" ]; then
      echo "[certbot-agent] WEBMEET_CERTBOT_AUTO_ISSUE=true requires WEBMEET_CERT_EMAIL"
      exit 1
    fi
    echo "[certbot-agent] no cert at ${LIVE_DIR}; issuing via standalone HTTP-01 (binds :80 briefly)"
    certbot certonly \
      --standalone \
      -d "$HOST" \
      --email "$EMAIL" \
      --agree-tos \
      --non-interactive \
      --no-eff-email
  else
    echo "[certbot-agent] no cert at ${LIVE_DIR}; auto-issue disabled, will only renew when a cert is present"
  fi
fi

while true; do
  if [ -d "$LIVE_DIR" ]; then
    echo "[certbot-agent] running renew via webroot (no-op until <30 days from expiry)"
    certbot renew \
      --webroot --webroot-path "$WEBROOT" \
      --no-random-sleep-on-renew || true
  else
    echo "[certbot-agent] no live cert directory; skipping renew"
  fi
  echo "[certbot-agent] sleeping ${INTERVAL}s"
  sleep "$INTERVAL"
done
STARTEOF

chmod +x "${agent_dir}/start.sh"
