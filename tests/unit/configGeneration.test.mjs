import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '../..');
const liveKitPreinstall = path.join(repoRoot, 'liveKitServerAgent', 'scripts', 'hooks', 'preinstall.sh');
const turnPreinstall = path.join(repoRoot, 'turnServerAgent', 'scripts', 'hooks', 'preinstall.sh');
const turnStart = path.join(repoRoot, 'turnServerAgent', 'scripts', 'start-turn-server-agent.sh');
const LIVEKIT_API_KEY = 'a'.repeat(64);
const LIVEKIT_API_SECRET = 'b'.repeat(64);
const TURN_AUTH_SECRET = 'c'.repeat(64);

function workspace() {
    return fs.mkdtempSync(path.join(os.tmpdir(), 'webmeet-infra-test-'));
}

function run(script, root, extraEnv = {}) {
    return spawnSync('bash', [script], {
        encoding: 'utf8',
        env: {
            ...process.env,
            PLOINKY_WORKSPACE_ROOT: root,
            WEBMEET_LIVEKIT_API_KEY: LIVEKIT_API_KEY,
            WEBMEET_LIVEKIT_API_SECRET: LIVEKIT_API_SECRET,
            WEBMEET_TURN_AUTH_SECRET: TURN_AUTH_SECRET,
            ...extraEnv,
        },
    });
}

function runTurnStart(extraEnv = {}) {
    const root = workspace();
    try {
        const secretValue = Object.hasOwn(extraEnv, 'WEBMEET_TURN_AUTH_SECRET')
            ? extraEnv.WEBMEET_TURN_AUTH_SECRET
            : TURN_AUTH_SECRET;
        const runtimeEnv = { ...extraEnv };
        delete runtimeEnv.WEBMEET_TURN_AUTH_SECRET;
        const secretDir = path.join(root, 'run', 'webmeet-turn-secret');
        const secretFile = path.join(secretDir, 'auth-secret');
        const testScript = path.join(root, 'start-turn-server-agent.sh');
        fs.mkdirSync(secretDir, { recursive: true });
        fs.writeFileSync(secretFile, `${secretValue}\n`, { mode: 0o444 });
        fs.writeFileSync(
            testScript,
            fs.readFileSync(turnStart, 'utf8').replace(
                'SECRET_FILE="/run/webmeet-turn-secret/auth-secret"',
                `SECRET_FILE="${secretFile}"`,
            ),
        );
        return spawnSync('sh', [testScript], {
            encoding: 'utf8',
            env: {
                ...process.env,
                PLOINKY_PROFILE: 'prod',
                WEBMEET_TURN_HOST: 'turn.example.test',
                WEBMEET_LIVEKIT_NODE_IP: '203.0.113.44',
                WEBMEET_TURN_ALLOWED_PEER_IPS: '203.0.113.44/32',
                WEBMEET_TURN_EXTERNAL_IP: '198.51.100.10',
                ...runtimeEnv,
            },
        });
    } finally {
        remove(root);
    }
}

function remove(root) {
    fs.rmSync(root, { recursive: true, force: true });
}

test('default LiveKit config is relay-only, UDP-only, and resolves its node IP at container start', () => {
    const root = workspace();
    try {
        const result = run(liveKitPreinstall, root, {
            PLOINKY_PROFILE: 'default',
            WEBMEET_TURN_CREDENTIAL_TTL_SECONDS: '1200',
        });
        assert.equal(result.status, 0, result.stderr);
        const yaml = fs.readFileSync(path.join(root, '.data/liveKitServerAgent/generated/livekit.yaml'), 'utf8');
        assert.match(yaml, /use_external_ip: false/);
        assert.match(yaml, /node_ip: __WEBMEET_LOCAL_NODE_IP__/);
        assert.match(yaml, /protocol: udp/);
        assert.doesNotMatch(yaml, /protocol: tls/);
        assert.match(yaml, /ttl: 1200/);
    } finally {
        remove(root);
    }
});

test('prod LiveKit config uses the explicit canonical node IP and advertises UDP plus TLS', () => {
    const root = workspace();
    try {
        const result = run(liveKitPreinstall, root, {
            PLOINKY_PROFILE: 'prod',
            WEBMEET_TURN_HOST: 'turn.example.test',
            WEBMEET_LIVEKIT_NODE_IP: '203.0.113.44',
        });
        assert.equal(result.status, 0, result.stderr);
        const yaml = fs.readFileSync(path.join(root, '.data/liveKitServerAgent/generated/livekit.yaml'), 'utf8');
        assert.match(yaml, /node_ip: 203\.0\.113\.44/);
        assert.match(yaml, /port: 3478[\s\S]*protocol: udp/);
        assert.match(yaml, /port: 443[\s\S]*protocol: tls/);
        assert.doesNotMatch(yaml, /__WEBMEET_LOCAL_NODE_IP__/);
    } finally {
        remove(root);
    }
});

test('LiveKit rejects zero credential TTL', () => {
    const root = workspace();
    try {
        const result = run(liveKitPreinstall, root, {
            PLOINKY_PROFILE: 'default',
            WEBMEET_TURN_CREDENTIAL_TTL_SECONDS: '0',
        });
        assert.notEqual(result.status, 0);
        assert.match(result.stderr, /must be greater than zero/);
    } finally {
        remove(root);
    }
});

test('LiveKit accepts the credential-TTL ceiling and rejects max+1 and overflow-length values', () => {
    for (const [value, shouldPass] of [['86400', true], ['86401', false], ['9'.repeat(256), false]]) {
        const root = workspace();
        try {
            const result = run(liveKitPreinstall, root, {
                PLOINKY_PROFILE: 'default',
                WEBMEET_TURN_CREDENTIAL_TTL_SECONDS: value,
            });
            if (shouldPass) {
                assert.equal(result.status, 0, result.stderr);
            } else {
                assert.notEqual(result.status, 0, value);
                assert.match(result.stderr, /must not exceed 86400/, value);
            }
        } finally {
            remove(root);
        }
    }
});

test('LiveKit rejects non-generated secret material before serializing YAML', () => {
    const root = workspace();
    try {
        const result = run(liveKitPreinstall, root, {
            PLOINKY_PROFILE: 'default',
            WEBMEET_TURN_AUTH_SECRET: `${'d'.repeat(64)}\nkeys:\n  attacker: injected`,
        });
        assert.notEqual(result.status, 0);
        assert.match(result.stderr, /64-character lowercase hexadecimal value generated by Ploinky/);
        assert.equal(fs.existsSync(path.join(root, '.data/liveKitServerAgent/generated/livekit.yaml')), false);
    } finally {
        remove(root);
    }
});

test('LiveKit rejects symlinked workspace directories and atomically replaces config leaf symlinks', () => {
    const escapedGeneratedRoot = workspace();
    const rootWithDirectoryEscape = workspace();
    const outsideLeafRoot = workspace();
    const rootWithLeafSymlink = workspace();
    try {
        fs.mkdirSync(path.join(rootWithDirectoryEscape, '.data/liveKitServerAgent'), { recursive: true });
        fs.symlinkSync(escapedGeneratedRoot, path.join(rootWithDirectoryEscape, '.data/liveKitServerAgent/generated'));
        const escaped = run(liveKitPreinstall, rootWithDirectoryEscape, { PLOINKY_PROFILE: 'default' });
        assert.notEqual(escaped.status, 0);
        assert.match(escaped.stderr, /cannot contain symlinked path components/);
        assert.equal(fs.existsSync(path.join(escapedGeneratedRoot, 'livekit.yaml')), false);

        const generatedDir = path.join(rootWithLeafSymlink, '.data/liveKitServerAgent/generated');
        fs.mkdirSync(generatedDir, { recursive: true });
        const captured = path.join(outsideLeafRoot, 'captured.yaml');
        fs.writeFileSync(captured, 'outside-must-not-change');
        fs.symlinkSync(captured, path.join(generatedDir, 'livekit.yaml'));
        const replaced = run(liveKitPreinstall, rootWithLeafSymlink, { PLOINKY_PROFILE: 'default' });
        assert.equal(replaced.status, 0, replaced.stderr);
        assert.equal(fs.readFileSync(captured, 'utf8'), 'outside-must-not-change');
        assert.equal(fs.lstatSync(path.join(generatedDir, 'livekit.yaml')).isSymbolicLink(), false);
        assert.match(fs.readFileSync(path.join(generatedDir, 'livekit.yaml'), 'utf8'), /turn_servers:/);
    } finally {
        remove(escapedGeneratedRoot);
        remove(rootWithDirectoryEscape);
        remove(outsideLeafRoot);
        remove(rootWithLeafSymlink);
    }
});

test('LiveKit prod rejects unspecified, loopback, link-local, and multicast node addresses', () => {
    const root = workspace();
    try {
        for (const address of ['0.0.0.0', '127.0.0.1', '169.254.1.2', '224.0.0.1']) {
            const result = run(liveKitPreinstall, root, {
                PLOINKY_PROFILE: 'prod',
                WEBMEET_TURN_HOST: 'turn.example.test',
                WEBMEET_LIVEKIT_NODE_IP: address,
            });
            assert.notEqual(result.status, 0, address);
            assert.match(result.stderr, /must be a unicast IPv4 address/, address);
        }
    } finally {
        remove(root);
    }
});

test('TURN preinstall has no host-engine ordering dependency and rejects zero limits', () => {
    const root = workspace();
    try {
        const good = run(turnPreinstall, root, { PLOINKY_PROFILE: 'default' });
        assert.equal(good.status, 0, good.stderr);
        const secretParent = path.join(root, '.ploinky/data/webmeetSecrets');
        const secretDir = path.join(secretParent, 'turn');
        const secretFile = path.join(secretDir, 'auth-secret');
        assert.equal(fs.readFileSync(secretFile, 'utf8'), `${TURN_AUTH_SECRET}\n`);
        assert.equal(fs.statSync(secretParent).mode & 0o777, 0o700);
        assert.equal(fs.statSync(secretDir).mode & 0o777, 0o755);
        assert.equal(fs.statSync(secretFile).mode & 0o777, 0o444);
        const bad = run(turnPreinstall, root, {
            PLOINKY_PROFILE: 'default',
            WEBMEET_TURN_USER_QUOTA: '0',
        });
        assert.notEqual(bad.status, 0);
        assert.match(bad.stderr, /must be greater than zero/);
    } finally {
        remove(root);
    }
});

test('TURN secret generation rejects directory and leaf symlinks without altering targets', () => {
    const outsideDirectory = workspace();
    const directoryRoot = workspace();
    const outsideFileRoot = workspace();
    const leafRoot = workspace();
    try {
        fs.mkdirSync(path.join(directoryRoot, '.ploinky/data/webmeetSecrets'), { recursive: true });
        fs.symlinkSync(outsideDirectory, path.join(directoryRoot, '.ploinky/data/webmeetSecrets/turn'));
        const directoryResult = run(turnPreinstall, directoryRoot, { PLOINKY_PROFILE: 'default' });
        assert.notEqual(directoryResult.status, 0);
        assert.match(directoryResult.stderr, /TURN secret directory cannot contain symlinked path components/);
        assert.deepEqual(fs.readdirSync(outsideDirectory), []);

        const secretDir = path.join(leafRoot, '.ploinky/data/webmeetSecrets/turn');
        fs.mkdirSync(secretDir, { recursive: true });
        const outsideFile = path.join(outsideFileRoot, 'captured-secret');
        fs.writeFileSync(outsideFile, 'outside-must-not-change');
        fs.symlinkSync(outsideFile, path.join(secretDir, 'auth-secret'));
        const leafResult = run(turnPreinstall, leafRoot, { PLOINKY_PROFILE: 'default' });
        assert.notEqual(leafResult.status, 0);
        assert.match(leafResult.stderr, /TURN secret file cannot be a symlink/);
        assert.equal(fs.readFileSync(outsideFile, 'utf8'), 'outside-must-not-change');
    } finally {
        remove(outsideDirectory);
        remove(directoryRoot);
        remove(outsideFileRoot);
        remove(leafRoot);
    }
});

test('TURN host and container validation reject quota/rate/lifetime max+1 and overflow-length values', () => {
    const cases = [
        ['WEBMEET_TURN_USER_QUOTA', 10000],
        ['WEBMEET_TURN_TOTAL_QUOTA', 100000],
        ['WEBMEET_TURN_MAX_BPS', 1000000000],
        ['WEBMEET_TURN_BPS_CAPACITY', 2000000000],
        ['WEBMEET_TURN_UNAUTHORIZED_RPS', 100000],
        ['WEBMEET_TURN_MAX_ALLOCATION_LIFETIME_SECONDS', 86400],
        ['WEBMEET_TURN_NONCE_LIFETIME_SECONDS', 86400],
    ];
    for (const [name, maximum] of cases) {
        for (const value of [String(maximum + 1), '9'.repeat(256)]) {
            const root = workspace();
            try {
                const hostResult = run(turnPreinstall, root, {
                    PLOINKY_PROFILE: 'default',
                    [name]: value,
                });
                assert.notEqual(hostResult.status, 0, `${name} host ${value}`);
                assert.match(hostResult.stderr, new RegExp(`must not exceed ${maximum}`), `${name} host ${value}`);

                const containerResult = runTurnStart({ [name]: value });
                assert.notEqual(containerResult.status, 0, `${name} container ${value}`);
                assert.match(containerResult.stderr, new RegExp(`must not exceed ${maximum}`), `${name} container ${value}`);
            } finally {
                remove(root);
            }
        }
    }
});

test('TURN rejects injected shared-secret values at host and container boundaries', () => {
    const injected = `${'d'.repeat(64)}\nallowed-peer-ip=0.0.0.0-255.255.255.255`;
    const root = workspace();
    try {
        const hostResult = run(turnPreinstall, root, {
            PLOINKY_PROFILE: 'default',
            WEBMEET_TURN_AUTH_SECRET: injected,
        });
        assert.notEqual(hostResult.status, 0);
        assert.match(hostResult.stderr, /64-character lowercase hexadecimal value generated by Ploinky/);

        const containerResult = runTurnStart({ WEBMEET_TURN_AUTH_SECRET: injected });
        assert.notEqual(containerResult.status, 0);
        assert.match(containerResult.stderr, /must contain exactly one line|64-character lowercase hexadecimal value generated by Ploinky/);
    } finally {
        remove(root);
    }
});

test('TURN rejects a symlinked TLS directory with its intended diagnostic and does not alter the target', () => {
    const outside = workspace();
    const root = workspace();
    try {
        fs.chmodSync(outside, 0o711);
        fs.mkdirSync(path.join(root, '.ploinky/data/webmeetTls'), { recursive: true });
        fs.symlinkSync(outside, path.join(root, '.ploinky/data/webmeetTls/turn'));
        const result = run(turnPreinstall, root, { PLOINKY_PROFILE: 'default' });
        assert.notEqual(result.status, 0);
        assert.match(result.stderr, /TURN TLS directory cannot contain symlinked path components/);
        assert.doesNotMatch(result.stderr, /command not found/);
        assert.equal(fs.statSync(outside).mode & 0o777, 0o711);
    } finally {
        remove(outside);
        remove(root);
    }
});

test('all production entry points reject local, IP-literal, and single-label TURN hostnames', () => {
    for (const turnHost of ['127.0.0.1', 'localhost', 'turn.local', '12345']) {
        const liveRoot = workspace();
        const turnRoot = workspace();
        try {
            const liveResult = run(liveKitPreinstall, liveRoot, {
                PLOINKY_PROFILE: 'prod',
                WEBMEET_TURN_HOST: turnHost,
                WEBMEET_LIVEKIT_NODE_IP: '203.0.113.44',
            });
            assert.notEqual(liveResult.status, 0, `LiveKit ${turnHost}`);
            assert.match(liveResult.stderr, /public multi-label DNS hostname/, `LiveKit ${turnHost}`);

            const turnResult = run(turnPreinstall, turnRoot, {
                PLOINKY_PROFILE: 'prod',
                WEBMEET_TURN_HOST: turnHost,
                WEBMEET_LIVEKIT_NODE_IP: '203.0.113.44',
                WEBMEET_TURN_ALLOWED_PEER_IPS: '203.0.113.44/32',
                WEBMEET_TURN_EXTERNAL_IP: '198.51.100.10',
            });
            assert.notEqual(turnResult.status, 0, `TURN host ${turnHost}`);
            assert.match(turnResult.stderr, /public multi-label DNS hostname/, `TURN host ${turnHost}`);

            const containerResult = runTurnStart({ WEBMEET_TURN_HOST: turnHost });
            assert.notEqual(containerResult.status, 0, `TURN container ${turnHost}`);
            assert.match(containerResult.stderr, /public multi-label DNS hostname/, `TURN container ${turnHost}`);
        } finally {
            remove(liveRoot);
            remove(turnRoot);
        }
    }
});

test('TURN prod rejects an allow-list that differs from the canonical LiveKit node IP', () => {
    const root = workspace();
    try {
        const result = run(turnPreinstall, root, {
            PLOINKY_PROFILE: 'prod',
            WEBMEET_TURN_HOST: 'turn.example.test',
            WEBMEET_LIVEKIT_NODE_IP: '203.0.113.44',
            WEBMEET_TURN_ALLOWED_PEER_IPS: '203.0.113.45/32',
            WEBMEET_TURN_EXTERNAL_IP: '198.51.100.10',
        });
        assert.notEqual(result.status, 0);
        assert.match(result.stderr, /must equal WEBMEET_LIVEKIT_NODE_IP exactly/);
    } finally {
        remove(root);
    }
});

test('TURN prod preinstall rejects unsafe canonical and external addresses', () => {
    const root = workspace();
    try {
        for (const address of ['0.0.0.0', '127.0.0.1', '169.254.1.2', '224.0.0.1']) {
            const badNode = run(turnPreinstall, root, {
                PLOINKY_PROFILE: 'prod',
                WEBMEET_TURN_HOST: 'turn.example.test',
                WEBMEET_LIVEKIT_NODE_IP: address,
                WEBMEET_TURN_ALLOWED_PEER_IPS: `${address}/32`,
                WEBMEET_TURN_EXTERNAL_IP: '198.51.100.10',
            });
            assert.notEqual(badNode.status, 0, `node ${address}`);
            assert.match(badNode.stderr, /WEBMEET_LIVEKIT_NODE_IP must be a unicast IPv4 address/, address);

            const badExternal = run(turnPreinstall, root, {
                PLOINKY_PROFILE: 'prod',
                WEBMEET_TURN_HOST: 'turn.example.test',
                WEBMEET_LIVEKIT_NODE_IP: '203.0.113.44',
                WEBMEET_TURN_ALLOWED_PEER_IPS: '203.0.113.44/32',
                WEBMEET_TURN_EXTERNAL_IP: address,
            });
            assert.notEqual(badExternal.status, 0, `external ${address}`);
            assert.match(badExternal.stderr, /WEBMEET_TURN_EXTERNAL_IP must be a unicast IPv4 address/, address);
        }
    } finally {
        remove(root);
    }
});

test('TURN container startup revalidates unsafe canonical and external addresses', () => {
    for (const address of ['0.0.0.0', '127.0.0.1', '169.254.1.2', '224.0.0.1']) {
        const badNode = runTurnStart({
            WEBMEET_LIVEKIT_NODE_IP: address,
            WEBMEET_TURN_ALLOWED_PEER_IPS: `${address}/32`,
        });
        assert.notEqual(badNode.status, 0, `node ${address}`);
        assert.match(badNode.stderr, /WEBMEET_LIVEKIT_NODE_IP must be a unicast IPv4 address/, address);

        const badExternal = runTurnStart({ WEBMEET_TURN_EXTERNAL_IP: address });
        assert.notEqual(badExternal.status, 0, `external ${address}`);
        assert.match(badExternal.stderr, /WEBMEET_TURN_EXTERNAL_IP must be a unicast IPv4 address/, address);
    }
});

test('TURN prod validates matching TLS material and applies the secure direct-bind modes', (t) => {
    const openssl = spawnSync('openssl', ['version'], { encoding: 'utf8' });
    if (openssl.status !== 0) {
        t.skip('openssl is unavailable');
        return;
    }

    const root = workspace();
    try {
        const tlsDir = path.join(root, '.ploinky/data/webmeetTls/turn');
        fs.mkdirSync(tlsDir, { recursive: true });
        const cert = path.join(tlsDir, 'fullchain.pem');
        const key = path.join(tlsDir, 'privkey.pem');
        const generated = spawnSync('openssl', [
            'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
            '-keyout', key, '-out', cert, '-days', '1',
            '-subj', '/CN=turn.example.test',
            '-addext', 'subjectAltName=DNS:turn.example.test',
        ], { encoding: 'utf8' });
        assert.equal(generated.status, 0, generated.stderr);

        const result = run(turnPreinstall, root, {
            PLOINKY_PROFILE: 'prod',
            WEBMEET_TURN_HOST: 'turn.example.test',
            WEBMEET_LIVEKIT_NODE_IP: '203.0.113.44',
            WEBMEET_TURN_ALLOWED_PEER_IPS: '203.0.113.44/32',
            WEBMEET_TURN_EXTERNAL_IP: '198.51.100.10',
        });
        assert.equal(result.status, 0, result.stderr);
        assert.equal(fs.statSync(path.join(root, '.ploinky/data/webmeetTls')).mode & 0o777, 0o700);
        assert.equal(fs.statSync(tlsDir).mode & 0o777, 0o755);
        assert.equal(fs.statSync(cert).mode & 0o777, 0o444);
        assert.equal(fs.statSync(key).mode & 0o777, 0o444);
    } finally {
        remove(root);
    }
});
