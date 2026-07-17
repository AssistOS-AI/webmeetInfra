#!/usr/bin/env bash
set -euo pipefail

workspace_root="${PLOINKY_WORKSPACE_ROOT:?PLOINKY_WORKSPACE_ROOT is required}"
topology_file="${PLOINKY_EDGE_TOPOLOGY_FILE:?PLOINKY_EDGE_TOPOLOGY_FILE is required}"
agent_lib_dir="${PLOINKY_AGENT_LIB_DIR:-/Agent}"
generated_dir="${workspace_root}/.data/liveKitServerAgent/generated"

mkdir -p \
  "$generated_dir" \
  "${workspace_root}/.ploinky/data/webmeet/redis" \
  "${workspace_root}/.ploinky/data/webmeet/recordings"

LIVEKIT_CONFIG_PATH="${generated_dir}/livekit.yaml" \
EGRESS_CONFIG_PATH="${generated_dir}/egress.yaml" \
REDIS_CONFIG_PATH="${generated_dir}/redis.conf" \
LIVEKIT_API_KEY="${LIVEKIT_API_KEY:?LIVEKIT_API_KEY is required}" \
LIVEKIT_API_SECRET="${LIVEKIT_API_SECRET:?LIVEKIT_API_SECRET is required}" \
PLOINKY_EDGE_TOPOLOGY_FILE="$topology_file" \
PLOINKY_AGENT_LIB_DIR="$agent_lib_dir" \
node --input-type=module <<'NODE'
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const moduleUrl = pathToFileURL(path.join(process.env.PLOINKY_AGENT_LIB_DIR, 'lib', 'edgeTopology.mjs')).href;
const { readEdgeTopology } = await import(moduleUrl);
const topology = readEdgeTopology({ file: process.env.PLOINKY_EDGE_TOPOLOGY_FILE });
const media = topology?.media;

function parseLiteralIpv4(value) {
  if (typeof value !== 'string' || !/^\d{1,3}(?:\.\d{1,3}){3}$/.test(value)) return null;
  const sourceOctets = value.split('.');
  const octets = sourceOctets.map(Number);
  if (octets.some((octet, index) => octet > 255 || String(octet) !== sourceOctets[index])) return null;
  return octets.reduce((result, octet) => (result * 256) + octet, 0) >>> 0;
}

const NON_GLOBAL_IPV4_CIDRS = [
  ['0.0.0.0', 8],
  ['10.0.0.0', 8],
  ['100.64.0.0', 10],
  ['127.0.0.0', 8],
  ['169.254.0.0', 16],
  ['172.16.0.0', 12],
  ['192.0.0.0', 24],
  ['192.0.2.0', 24],
  ['192.31.196.0', 24],
  ['192.52.193.0', 24],
  ['192.88.99.0', 24],
  ['192.168.0.0', 16],
  ['192.175.48.0', 24],
  ['198.18.0.0', 15],
  ['198.51.100.0', 24],
  ['203.0.113.0', 24],
  ['224.0.0.0', 4],
  ['240.0.0.0', 4],
].map(([base, prefix]) => [parseLiteralIpv4(base), prefix]);

function isLiteralGlobalUnicastIpv4(value) {
  const address = parseLiteralIpv4(value);
  if (address === null) return false;
  return !NON_GLOBAL_IPV4_CIDRS.some(([base, prefix]) => {
    const mask = (0xffffffff << (32 - prefix)) >>> 0;
    return ((address & mask) >>> 0) === ((base & mask) >>> 0);
  });
}

if (topology?.schemaVersion !== 2) {
  throw new Error('LiveKit requires edge topology schemaVersion 2');
}
if (!isLiteralGlobalUnicastIpv4(media?.publicIPv4)) {
  throw new Error('LiveKit media.publicIPv4 must be a literal globally routable unicast IPv4 address');
}
if (media?.udpPort !== 7882) {
  throw new Error('LiveKit media.udpPort must equal the box-owned port 7882');
}
if (!['direct', 'nat-forward'].includes(media?.addressMode)) {
  throw new Error('LiveKit media.addressMode must be direct or nat-forward');
}

const apiKey = process.env.LIVEKIT_API_KEY;
const apiSecret = process.env.LIVEKIT_API_SECRET;
if (!apiKey || !apiSecret) throw new Error('LiveKit API key and secret are required');

const livekitConfig = {
  port: 7880,
  bind_addresses: ['127.0.0.1'],
  logging: { level: 'info' },
  rtc: {
    node_ip: media.publicIPv4,
    tcp_port: 0,
    udp_port: 7882,
    use_external_ip: false,
  },
  turn: { enabled: false },
  redis: { address: '127.0.0.1:6379' },
  keys: { [apiKey]: apiSecret },
};
const egressConfig = {
  api_key: apiKey,
  api_secret: apiSecret,
  ws_url: 'ws://127.0.0.1:7880',
  insecure: true,
  redis: { address: '127.0.0.1:6379' },
  template_port: 7980,
  health_port: 7981,
};

fs.writeFileSync(process.env.LIVEKIT_CONFIG_PATH, `${JSON.stringify(livekitConfig, null, 2)}\n`, { mode: 0o600 });
fs.writeFileSync(process.env.EGRESS_CONFIG_PATH, `${JSON.stringify(egressConfig, null, 2)}\n`, { mode: 0o600 });
fs.writeFileSync(
  process.env.REDIS_CONFIG_PATH,
  'bind 127.0.0.1\nprotected-mode yes\nport 6379\ndir /data/redis\nsave 60 1\nloglevel warning\nappendonly no\n',
  { mode: 0o600 },
);
NODE

printf '[liveKitServerAgent] generated fixed LiveKit/Egress/Redis configuration from topology generation (credentials redacted)\n'
