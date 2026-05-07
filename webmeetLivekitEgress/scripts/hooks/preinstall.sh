#!/usr/bin/env bash
set -euo pipefail

workspace_root="${PLOINKY_CWD:-$PWD}"
profile="${PLOINKY_PROFILE:-dev}"
agent_dir="${workspace_root}/.ploinky/agents/webmeetLivekitEgress"

mkdir -p "$agent_dir"

if [[ "$profile" == "prod" ]]; then
  : "${WEBMEET_LIVEKIT_API_KEY:?WEBMEET_LIVEKIT_API_KEY is required in prod profile}"
  : "${WEBMEET_LIVEKIT_API_SECRET:?WEBMEET_LIVEKIT_API_SECRET is required in prod profile}"
fi

api_key="${WEBMEET_LIVEKIT_API_KEY:-devkey}"
api_secret="${WEBMEET_LIVEKIT_API_SECRET:-devsecretdevsecretdevsecretdevsecret}"

cat > "${agent_dir}/egress.yaml" <<EOF
api_key: ${api_key}
api_secret: ${api_secret}
ws_url: ws://webmeetLivekitServer:7880
insecure: true
redis:
  address: webmeetRedis:6379
health_port: 7980
EOF
