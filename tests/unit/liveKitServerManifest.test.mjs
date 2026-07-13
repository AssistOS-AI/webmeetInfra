import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '../..');
const manifestPath = path.join(repoRoot, 'liveKitServerAgent', 'manifest.json');
const preinstallPath = path.join(repoRoot, 'liveKitServerAgent', 'scripts', 'hooks', 'preinstall.sh');
const startPath = path.join(repoRoot, 'liveKitServerAgent', 'scripts', 'start-livekit-server-agent.sh');
const readinessPath = path.join(repoRoot, 'liveKitServerAgent', 'readiness.sh');

function readManifest() {
    return JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
}

function findEnv(profile, name) {
    return (profile.env || []).find((entry) => entry.name === name);
}

test('liveKitServerAgent uses script readiness and never republishes private control-plane ports', () => {
    const manifest = readManifest();
    assert.equal(manifest.start, 'sh /code/scripts/start-livekit-server-agent.sh');
    assert.equal(Object.hasOwn(manifest, 'agent'), false);
    assert.equal(Object.hasOwn(manifest, 'readiness'), false);
    assert.equal(manifest.health?.readiness?.script, 'readiness.sh');
    const expected = {
        default: [],
        dev: [],
        prod: ['0.0.0.0:7881:7881', '0.0.0.0:7882-7892:7882-7892/udp'],
    };
    for (const [name, profile] of Object.entries(manifest.profiles)) {
        assert.deepEqual(profile.openPorts, expected[name]);
        assert.equal(Object.hasOwn(profile, 'network'), false, `${name} inherits root network atomically`);
    }
});

test('liveKitServerAgent uses schema-2 multi-network topology without declared aliases', () => {
    const manifest = readManifest();
    assert.deepEqual(manifest.network, {
        mode: 'bridge',
        attachments: [
            { name: 'webmeet-signaling', primary: true },
            { name: 'webmeet-turn' },
        ],
    });
    assert.equal(manifest.network.attachments.filter((attachment) => attachment.primary === true).length, 1);
    assert.equal(JSON.stringify(manifest).includes('"aliases"'), false);
});

test('liveKitServerAgent shares TURN auth and owns the credential TTL', () => {
    const manifest = readManifest();
    for (const [name, profile] of Object.entries(manifest.profiles)) {
        const secret = findEnv(profile, 'WEBMEET_TURN_AUTH_SECRET');
        assert.equal(secret?.sharedGeneratedSecret, true, `${name} shared TURN secret`);
        assert.equal(secret?.runtime, false, `${name} keeps TURN auth out of runtime env`);
        assert.equal(findEnv(profile, 'WEBMEET_LIVEKIT_API_KEY')?.runtime, false, `${name} keeps API key out of runtime env`);
        assert.equal(findEnv(profile, 'WEBMEET_LIVEKIT_API_SECRET')?.runtime, false, `${name} keeps API secret out of runtime env`);
        assert.equal(Object.hasOwn(secret, 'explicitOverride'), false, `${name} ignores operator TURN overrides`);
        assert.equal(findEnv(profile, 'WEBMEET_TURN_CREDENTIAL_TTL_SECONDS')?.default, '29100');
        assert.equal(findEnv(profile, 'WEBMEET_LIVEKIT_LOG_LEVEL')?.default, 'warn');
    }
});

test('liveKitServerAgent keeps SDP-bearing info/debug logging opt-in', () => {
    const preinstall = fs.readFileSync(preinstallPath, 'utf8');
    assert.match(preinstall, /WEBMEET_LIVEKIT_LOG_LEVEL:-warn/);
    assert.match(preinstall, /info.*logging can include SDP ICE credentials and candidate addresses/s);
});

test('liveKitServerAgent scrubs generated credentials before starting long-lived processes', () => {
    const start = fs.readFileSync(startPath, 'utf8');
    assert.match(start, /exec env[\s\\]*-u WEBMEET_TURN_AUTH_SECRET/);
    assert.match(start, /-u WEBMEET_LIVEKIT_API_KEY/);
    assert.match(start, /-u WEBMEET_LIVEKIT_API_SECRET/);
    assert.match(start, /WEBMEET_RUNTIME_ENV_SCRUBBED=1/);
});

test('liveKitServerAgent selects its webmeet-turn address through the TURN peer route', () => {
    const start = fs.readFileSync(startPath, 'utf8');
    assert.match(start, /getent ahostsv4 turnserveragent/);
    assert.match(start, /ip -4 route get "\$peer_addresses"/);
    assert.match(start, /\$i == "src"/);
    assert.doesNotMatch(start, /getent ahostsv4 liveKitServerAgent/);
});

test('liveKitServerAgent requires an explicit prod TURN hostname and canonical node IP at runtime', () => {
    const manifest = readManifest();
    for (const name of ['WEBMEET_TURN_HOST', 'WEBMEET_LIVEKIT_NODE_IP']) {
        const entry = findEnv(manifest.profiles.prod, name);
        assert.ok(entry);
        assert.equal(entry.required, false);
        assert.equal(Object.hasOwn(entry, 'default'), false);
    }
    const preinstall = fs.readFileSync(preinstallPath, 'utf8');
    assert.match(preinstall, /WEBMEET_TURN_HOST is required in the prod profile/);
    assert.match(preinstall, /WEBMEET_LIVEKIT_NODE_IP is required in the prod profile/);
    assert.match(preinstall, /public multi-label DNS hostname/);
});

test('liveKitServerAgent removes external-IP discovery and workspace-var seeding surfaces', () => {
    const manifest = readManifest();
    for (const profile of Object.values(manifest.profiles)) {
        assert.equal(findEnv(profile, 'WEBMEET_LIVEKIT_USE_EXTERNAL_IP'), undefined);
        assert.equal(findEnv(profile, 'WEBMEET_LOCAL_PUBLIC_HOST'), undefined);
    }
    const preinstall = fs.readFileSync(preinstallPath, 'utf8');
    assert.doesNotMatch(preinstall, /ploinky var|seed_webmeet|detect_local_public_host/);
    assert.match(preinstall, /use_external_ip: false/);
    assert.match(preinstall, /__WEBMEET_LOCAL_NODE_IP__/);
});

test('liveKitServerAgent has no undeclared path, timeout, port, or copied-startup override surfaces', () => {
    const preinstall = fs.readFileSync(preinstallPath, 'utf8');
    const start = fs.readFileSync(startPath, 'utf8');
    const readiness = fs.readFileSync(readinessPath, 'utf8');
    const sources = `${preinstall}\n${start}\n${readiness}`;

    for (const name of [
        'WEBMEET_REDIS_DATA_DIR',
        'WEBMEET_RECORDINGS_DIR',
        'WEBMEET_INFRA_WAIT_TIMEOUT',
        'WEBMEET_INFRA_REDIS_PORT',
        'WEBMEET_INFRA_LIVEKIT_PORT',
        'WEBMEET_INFRA_EGRESS_HEALTH_PORT',
    ]) {
        assert.doesNotMatch(sources, new RegExp(name), name);
    }
    assert.doesNotMatch(preinstall, /cp .*start-livekit-server-agent\.sh/);
    assert.doesNotMatch(readiness, /\/dev\/tcp|curl|docker exec/);
    assert.match(readiness, /command -v nc/);
});

test('liveKitServerAgent generated config volume is owner-only', () => {
    const manifest = readManifest();
    const options = manifest.volumeOptions['/working-data/generated'];
    assert.equal(options.generated, true);
    assert.equal(options.required, true);
    assert.equal(options.chmod, 448);
});

test('liveKitServerAgent no longer owns Coturn, TLS-edge, or removed health settings', () => {
    const manifest = readManifest();
    const removedNames = [
        'WEBMEET_INFRA_HEALTH_PORT',
        'WEBMEET_TURN_EXTERNAL_IP',
        'WEBMEET_TURN_PORT',
        'WEBMEET_TURN_REALM',
        'WEBMEET_TURN_USER',
        'WEBMEET_TURN_PASSWORD',
        'WEBMEET_TURN_MIN_PORT',
        'WEBMEET_TURN_MAX_PORT',
        'WEBMEET_TLS_HOSTNAME',
        'WEBMEET_LIVEKIT_UPSTREAM',
        'WEBMEET_CERT_EMAIL',
    ];
    for (const profile of Object.values(manifest.profiles)) {
        for (const name of removedNames) {
            assert.equal(findEnv(profile, name), undefined, name);
        }
    }
    assert.equal(Object.hasOwn(manifest.volumes, '.ploinky/data/webmeetTls/letsencrypt'), false);
});
