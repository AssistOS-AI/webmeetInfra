#!/usr/bin/env bash
set -euo pipefail

workspace_root="${PLOINKY_CWD:-$PWD}"
agent_dir="${workspace_root}/.ploinky/agents/webmeetLivekitEgress"

mkdir -p "$agent_dir"

api_key="${WEBMEET_LIVEKIT_API_KEY:?WEBMEET_LIVEKIT_API_KEY is required}"
api_secret="${WEBMEET_LIVEKIT_API_SECRET:?WEBMEET_LIVEKIT_API_SECRET is required}"

cat > "${agent_dir}/egress.yaml" <<EOF
api_key: ${api_key}
api_secret: ${api_secret}
ws_url: ws://webmeetLivekitServer:7880
insecure: true
redis:
  address: webmeetRedis:6379
health_port: 7980
EOF
