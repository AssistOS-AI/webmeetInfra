#!/usr/bin/env bash
set -euo pipefail

workspace_root="${PLOINKY_CWD:-$PWD}"
profile="${PLOINKY_PROFILE:-dev}"
agent_dir="${workspace_root}/.ploinky/agents/webmeetLivekitServer"
mkdir -p "$agent_dir"

api_key="${WEBMEET_LIVEKIT_API_KEY:?WEBMEET_LIVEKIT_API_KEY is required}"
api_secret="${WEBMEET_LIVEKIT_API_SECRET:?WEBMEET_LIVEKIT_API_SECRET is required}"
use_external_ip="${WEBMEET_LIVEKIT_USE_EXTERNAL_IP:-false}"
node_ip="${WEBMEET_LIVEKIT_NODE_IP:-}"

rtc_tcp_port=7881
rtc_port_range_start=7882
rtc_port_range_end=7892
if [[ "$profile" == "dev" ]]; then
  rtc_tcp_port=17881
  rtc_port_range_start=17882
  rtc_port_range_end=17892
  node_ip="${node_ip:-127.0.0.1}"
fi

cat > "${agent_dir}/livekit.yaml" <<EOF
port: 7880
rtc:
  tcp_port: ${rtc_tcp_port}
  port_range_start: ${rtc_port_range_start}
  port_range_end: ${rtc_port_range_end}
  use_external_ip: ${use_external_ip}
EOF
if [[ -n "$node_ip" && "$use_external_ip" != "true" ]]; then
  cat >> "${agent_dir}/livekit.yaml" <<EOF
  node_ip: ${node_ip}
EOF
fi
cat >> "${agent_dir}/livekit.yaml" <<EOF
redis:
  address: webmeetRedis:6379
keys:
  ${api_key}: ${api_secret}
EOF
