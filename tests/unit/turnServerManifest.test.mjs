import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '../..');
const manifestPath = path.join(repoRoot, 'turnServerAgent', 'manifest.json');
const preinstallPath = path.join(repoRoot, 'turnServerAgent', 'scripts', 'hooks', 'preinstall.sh');
const startPath = path.join(repoRoot, 'turnServerAgent', 'scripts', 'start-turn-server-agent.sh');
const readinessPath = path.join(repoRoot, 'turnServerAgent', 'readiness.sh');

function readManifest() {
    return JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
}

function findEnv(profile, name) {
    return (profile.env || []).find((entry) => entry.name === name);
}

test('turnServerAgent pins Coturn and neutralizes the upstream argument-evaluating entrypoint', () => {
    const manifest = readManifest();
    assert.equal(
        manifest.container,
        'docker.io/coturn/coturn@sha256:0c0e8fc0c263b85a134e9e4242b5e46e1f4c077c5029633511191c05b5c2c814',
    );
    assert.equal(manifest.entrypoint, '/usr/bin/env');
    assert.equal(manifest.start, 'sh /code/scripts/start-turn-server-agent.sh');
    assert.equal(Object.hasOwn(manifest, 'agent'), false);
    assert.equal(manifest.containerSecurity?.privileged, false);
});

test('turnServerAgent uses script readiness and publishes only TURN listener/relay ports', () => {
    const manifest = readManifest();
    assert.equal(Object.hasOwn(manifest, 'readiness'), false);
    assert.equal(manifest.health?.readiness?.script, 'readiness.sh');

    assert.deepEqual(manifest.profiles.prod.openPorts, [
        '0.0.0.0:3478:3478/udp',
        '0.0.0.0:20000-20127:20000-20127/udp',
        '0.0.0.0:443:5349/tcp',
    ]);
    for (const profileName of ['default', 'dev']) {
        assert.deepEqual(manifest.profiles[profileName].openPorts, [
            '127.0.0.1:3478:3478/tcp',
            '127.0.0.1:3478:3478/udp',
            '127.0.0.1:20000-20127:20000-20127/udp',
        ]);
    }
});

test('turnServerAgent stays on the TURN trust-zone bridge and shares only the generated auth secret', () => {
    const manifest = readManifest();
    assert.deepEqual(manifest.network, {
        mode: 'bridge',
        attachments: [{ name: 'webmeet-turn', primary: true }],
    });
    assert.equal(JSON.stringify(manifest).includes('"aliases"'), false);
    for (const [profileName, profile] of Object.entries(manifest.profiles)) {
        assert.equal(Object.hasOwn(profile, 'network'), false, `${profileName} inherits root network atomically`);
        const secret = findEnv(profile, 'WEBMEET_TURN_AUTH_SECRET');
        assert.equal(secret?.sharedGeneratedSecret, true, `${profileName} shared secret`);
        assert.equal(secret?.runtime, false, `${profileName} keeps the secret out of runtime env`);
        assert.equal(Object.hasOwn(secret, 'explicitOverride'), false, `${profileName} ignores operator secret overrides`);
    }
});

test('turnServerAgent consumes Ploinky canonical DNS alias derivation', () => {
    const manifest = readManifest();
    for (const profileName of ['default', 'dev']) {
        assert.equal(
            findEnv(manifest.profiles[profileName], 'WEBMEET_LIVEKIT_PEER_HOST')?.default,
            'livekitserveragent',
        );
    }
});

test('turnServerAgent prod manifest is Ploinky-complete while runtime-required public values have no defaults', () => {
    const manifest = readManifest();
    const runtimeRequired = [
        'WEBMEET_TURN_HOST',
        'WEBMEET_LIVEKIT_NODE_IP',
        'WEBMEET_TURN_ALLOWED_PEER_IPS',
        'WEBMEET_TURN_EXTERNAL_IP',
    ];
    for (const name of runtimeRequired) {
        const entry = findEnv(manifest.profiles.prod, name);
        assert.ok(entry, `prod declares ${name}`);
        assert.equal(entry.required, false, `${name} uses hook-level fail-closed validation`);
        assert.equal(Object.hasOwn(entry, 'default'), false, `${name} has no deployment-specific fallback`);
    }

    const incomplete = manifest.profiles.prod.env.filter((entry) => {
        if (!entry.required || Object.hasOwn(entry, 'default')) return false;
        if (entry.sharedGeneratedSecret || entry.generatedSecret) return false;
        return !/(SECRET|PASSWORD|TOKEN|KEY)(?:_|$)/.test(entry.name);
    });
    assert.deepEqual(incomplete, []);
});

test('turnServerAgent mounts TLS and its host-generated startup secret read-only', () => {
    const manifest = readManifest();
    assert.deepEqual(manifest.volumes, {
        '.ploinky/data/webmeetTls/turn': '/etc/turnserver/tls',
        '.ploinky/data/webmeetSecrets/turn': '/run/webmeet-turn-secret',
    });
    assert.deepEqual(manifest.volumeOptions['/etc/turnserver/tls'], { readOnly: true });
    assert.deepEqual(manifest.volumeOptions['/run/webmeet-turn-secret'], {
        generated: true,
        required: true,
        readOnly: true,
        chmod: 493,
    });
    assert.equal(Object.values(manifest.volumes).includes('/working-data/generated'), false);
});

test('turnServerAgent fixes relay publication and credential TTL at their owning layers', () => {
    const manifest = readManifest();
    for (const profile of Object.values(manifest.profiles)) {
        assert.equal(findEnv(profile, 'WEBMEET_TURN_MIN_PORT'), undefined);
        assert.equal(findEnv(profile, 'WEBMEET_TURN_MAX_PORT'), undefined);
        assert.equal(findEnv(profile, 'WEBMEET_TURN_CREDENTIAL_TTL_SECONDS'), undefined);
        assert.equal(findEnv(profile, 'WEBMEET_TURN_REALM'), undefined);
    }
    const start = fs.readFileSync(startPath, 'utf8');
    assert.match(start, /MIN_PORT=20000/);
    assert.match(start, /MAX_PORT=20127/);
    assert.match(start, /TURN_REALM="webmeet\.local"/);
    assert.match(start, /TURN_REALM="\$TURN_HOST"/);
    assert.match(start, /public multi-label DNS hostname/);
});

test('turnServerAgent uses bridge DNS, not host engine/container-name discovery', () => {
    const preinstall = fs.readFileSync(preinstallPath, 'utf8');
    const start = fs.readFileSync(startPath, 'utf8');
    assert.doesNotMatch(preinstall, /docker|podman|network inspect|container name/i);
    assert.doesNotMatch(start, /docker|podman|network inspect|container name/i);
    assert.match(start, /getent ahostsv4/);
    assert.match(start, /did not resolve to exactly one IPv4 address/);
});

test('turnServerAgent emits exclusive IPv4/IPv6 denies and an exact canonical allow', () => {
    const start = fs.readFileSync(startPath, 'utf8');
    assert.match(start, /denied-peer-ip=0\.0\.0\.0-255\.255\.255\.255/);
    assert.match(start, /denied-peer-ip=::-ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff/);
    assert.match(start, /allowed-peer-ip=%s/);
    assert.match(start, /WEBMEET_TURN_ALLOWED_PEER_IPS must equal WEBMEET_LIVEKIT_NODE_IP/);
    assert.match(start, /listening-ip=0\.0\.0\.0/);
    assert.doesNotMatch(start, /no-cli|no-rfc5780/);
});

test('turnServerAgent readiness proves the live STUN listener without putting credentials in argv', () => {
    const readiness = fs.readFileSync(readinessPath, 'utf8');
    assert.match(readiness, /turnutils_stunclient/);
    assert.match(readiness, /timeout 5 turnutils_stunclient -p 3478 127\.0\.0\.1/);
    assert.doesNotMatch(readiness, /turnutils_uclient|WEBMEET_TURN_AUTH_SECRET|-W|-w/);
    assert.doesNotMatch(readiness, /skipping|optional/i);
});

test('turnServerAgent removes the shared secret from Coturn process environment and argv', () => {
    const start = fs.readFileSync(startPath, 'utf8');
    assert.match(start, /unset SECRET/);
    assert.match(start, /SECRET_FILE="\/run\/webmeet-turn-secret\/auth-secret"/);
    assert.doesNotMatch(start, /SECRET="\$\{WEBMEET_TURN_AUTH_SECRET/);
    assert.match(start, /exec env -u WEBMEET_TURN_AUTH_SECRET turnserver -c "\$CONFIG_FILE"/);
    assert.doesNotMatch(start, /turnserver[^\n]*WEBMEET_TURN_AUTH_SECRET/);
});
