#!/usr/bin/env bash
set -euo pipefail

workspace_root="${PLOINKY_CWD:-$PWD}"
profile="${PLOINKY_PROFILE:-dev}"
agent_dir="${workspace_root}/.ploinky/agents/webmeetLivekitEgress"

mkdir -p "$agent_dir"

api_key="${WEBMEET_LIVEKIT_API_KEY:?WEBMEET_LIVEKIT_API_KEY is required}"
api_secret="${WEBMEET_LIVEKIT_API_SECRET:?WEBMEET_LIVEKIT_API_SECRET is required}"
default_livekit_ws_url="ws://webmeetLivekitServer:7880"
if [[ "$profile" == "dev" ]]; then
  default_livekit_ws_url="ws://webmeetLivekitServer:17880"
elif [[ "$profile" == "prod" ]]; then
  default_livekit_ws_url="ws://host.containers.internal:7880"
fi
livekit_ws_url="${WEBMEET_LIVEKIT_INTERNAL_WS_URL:-$default_livekit_ws_url}"
redis_address="${WEBMEET_EGRESS_REDIS_ADDRESS:-webmeetRedis:6379}"

cat > "${agent_dir}/egress.yaml" <<EOF
api_key: ${api_key}
api_secret: ${api_secret}
ws_url: ${livekit_ws_url}
insecure: true
redis:
  address: ${redis_address}
health_port: 7980
EOF
