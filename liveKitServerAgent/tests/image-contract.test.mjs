import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const agentRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const manifest = JSON.parse(fs.readFileSync(path.join(agentRoot, 'manifest.json'), 'utf8'));

test('manifest pins the bridge-compatible LiveKit image index', () => {
    assert.equal(
        manifest.container,
        'docker.io/assistos/livekit-server-agent@sha256:012bb28b82300a4e0b720decb6d3b023fc2f26c7a2665832bf1baaeb5b2bb6f9'
    );
    assert.doesNotMatch(manifest.container, /:webmeet-infra$/);
});
