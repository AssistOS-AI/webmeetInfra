import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const agentRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const hook = path.join(agentRoot, 'scripts/hooks/preinstall.sh');

function runPreinstall(topology) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'livekit-config-test-'));
  const workspace = path.join(root, 'workspace');
  const agentLib = path.join(root, 'agent-lib');
  const topologyFile = path.join(root, 'topology.json');
  fs.mkdirSync(path.join(agentLib, 'lib'), { recursive: true });
  fs.writeFileSync(topologyFile, JSON.stringify(topology));
  fs.writeFileSync(path.join(agentLib, 'lib/edgeTopology.mjs'), `
    import fs from 'node:fs';
    export function readEdgeTopology({ file }) {
      return JSON.parse(fs.readFileSync(file, 'utf8'));
    }
  `);
  const result = spawnSync('bash', [hook], {
    encoding: 'utf8',
    env: {
      ...process.env,
      PLOINKY_WORKSPACE_ROOT: workspace,
      PLOINKY_EDGE_TOPOLOGY_FILE: topologyFile,
      PLOINKY_AGENT_LIB_DIR: agentLib,
      LIVEKIT_API_KEY: 'test-key',
      LIVEKIT_API_SECRET: 'test-secret-never-log',
    },
  });
  return { root, workspace, result };
}

function validTopology(overrides = {}) {
  return {
    schemaVersion: 2,
    media: {
      publicIPv4: '8.8.8.8',
      udpPort: 7882,
      addressMode: 'direct',
      ...overrides,
    },
  };
}

for (const addressMode of ['direct', 'nat-forward']) {
test(`preinstall generates literal ${addressMode} LiveKit and fixed private Egress config`, () => {
  const run = runPreinstall(validTopology({ addressMode }));
  try {
    assert.equal(run.result.status, 0, run.result.stderr);
    assert.equal(run.result.stdout.includes('test-secret'), false);
    const generated = path.join(run.workspace, '.data/liveKitServerAgent/generated');
    const livekit = JSON.parse(fs.readFileSync(path.join(generated, 'livekit.yaml'), 'utf8'));
    const egress = JSON.parse(fs.readFileSync(path.join(generated, 'egress.yaml'), 'utf8'));
    const redis = fs.readFileSync(path.join(generated, 'redis.conf'), 'utf8');
    assert.deepEqual(livekit.rtc, {
      node_ip: '8.8.8.8',
      tcp_port: 0,
      udp_port: 7882,
      use_external_ip: false,
    });
    assert.deepEqual(livekit.bind_addresses, ['127.0.0.1']);
    assert.equal(livekit.port, 7880);
    assert.deepEqual(livekit.turn, { enabled: false });
    assert.deepEqual(livekit.redis, { address: '127.0.0.1:6379' });
    assert.equal('port_range_start' in livekit.rtc, false);
    assert.equal('port_range_end' in livekit.rtc, false);
    assert.equal(egress.template_port, 7980);
    assert.equal(egress.health_port, 7981);
    assert.equal(egress.ws_url, 'ws://127.0.0.1:7880');
    assert.match(redis, /^bind 127\.0\.0\.1$/m);
    assert.match(redis, /^protected-mode yes$/m);
  } finally {
    fs.rmSync(run.root, { recursive: true, force: true });
  }
});
}

const rejectedPublicIpv4Cases = [
  ['missing value', undefined],
  ['null value', null],
  ['numeric value', 16843009],
  ['array value', ['1.1.1.1']],
  ['empty value', ''],
  ['surrounding whitespace', ' 1.1.1.1'],
  ['non-decimal octet', '1.2.3.a'],
  ['too few octets', '1.2.3'],
  ['too many octets', '1.2.3.4.5'],
  ['out-of-range octet', '1.2.3.256'],
  ['non-canonical leading zeroes', '001.2.3.4'],
  ['this-network lower boundary', '0.0.0.0'],
  ['this-network upper boundary', '0.255.255.255'],
  ['private 10/8 lower boundary', '10.0.0.0'],
  ['private 10/8 upper boundary', '10.255.255.255'],
  ['CGNAT lower boundary', '100.64.0.0'],
  ['CGNAT upper boundary', '100.127.255.255'],
  ['loopback lower boundary', '127.0.0.0'],
  ['loopback upper boundary', '127.255.255.255'],
  ['link-local lower boundary', '169.254.0.0'],
  ['link-local upper boundary', '169.254.255.255'],
  ['private 172/12 lower boundary', '172.16.0.0'],
  ['private 172/12 upper boundary', '172.31.255.255'],
  ['IETF protocol assignments', '192.0.0.9'],
  ['TEST-NET-1', '192.0.2.1'],
  ['AS112 service prefix', '192.31.196.1'],
  ['AMT relay anycast prefix', '192.52.193.1'],
  ['deprecated 6to4 relay prefix', '192.88.99.1'],
  ['private 192.168/16 lower boundary', '192.168.0.0'],
  ['private 192.168/16 upper boundary', '192.168.255.255'],
  ['direct-delegation AS112 prefix', '192.175.48.1'],
  ['benchmark lower boundary', '198.18.0.0'],
  ['benchmark upper boundary', '198.19.255.255'],
  ['TEST-NET-2', '198.51.100.44'],
  ['TEST-NET-3', '203.0.113.20'],
  ['multicast lower boundary', '224.0.0.0'],
  ['multicast upper boundary', '239.255.255.255'],
  ['reserved lower boundary', '240.0.0.0'],
  ['limited broadcast', '255.255.255.255'],
];

test('preinstall rejects every non-global IPv4 class without generating active config', () => {
  for (const [label, publicIPv4] of rejectedPublicIpv4Cases) {
    const run = runPreinstall(validTopology({ publicIPv4 }));
    try {
      assert.notEqual(run.result.status, 0, `${label} (${JSON.stringify(publicIPv4)}) was accepted`);
      assert.match(run.result.stderr, /globally routable unicast IPv4/, label);
      assert.equal(run.result.stderr.includes('test-secret-never-log'), false, label);
      assert.equal(
        fs.existsSync(path.join(run.workspace, '.data/liveKitServerAgent/generated/livekit.yaml')),
        false,
        `${label} generated an active LiveKit config`,
      );
    } finally {
      fs.rmSync(run.root, { recursive: true, force: true });
    }
  }
});

for (const publicIPv4 of [
  '1.1.1.1',
  '100.63.255.255',
  '100.128.0.0',
  '169.253.255.255',
  '169.255.0.0',
  '172.15.255.255',
  '172.32.0.0',
  '192.167.255.255',
  '192.169.0.0',
  '198.17.255.255',
  '198.20.0.0',
  '223.255.255.254',
]) {
  test(`preinstall accepts literal global unicast boundary ${publicIPv4}`, () => {
    const run = runPreinstall(validTopology({ publicIPv4 }));
    try {
      assert.equal(run.result.status, 0, run.result.stderr);
      const generated = path.join(run.workspace, '.data/liveKitServerAgent/generated/livekit.yaml');
      assert.equal(JSON.parse(fs.readFileSync(generated, 'utf8')).rtc.node_ip, publicIPv4);
    } finally {
      fs.rmSync(run.root, { recursive: true, force: true });
    }
  });
}

for (const [label, topology, message] of [
  ['wrong mux', validTopology({ udpPort: 7881 }), /udpPort must equal/],
  ['discovery mode', validTopology({ addressMode: 'discover' }), /addressMode must be direct or nat-forward/],
  ['old schema', { ...validTopology(), schemaVersion: 1 }, /schemaVersion 2/],
]) {
  test(`preinstall rejects ${label} without generating an active config`, () => {
    const run = runPreinstall(topology);
    try {
      assert.notEqual(run.result.status, 0);
      assert.match(run.result.stderr, message);
      assert.equal(run.result.stderr.includes('test-secret-never-log'), false);
    } finally {
      fs.rmSync(run.root, { recursive: true, force: true });
    }
  });
}
