import assert from 'node:assert/strict';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const agentRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const startScript = path.join(agentRoot, 'scripts/start-livekit-server-agent.sh');

test('runtime without the v5 image marker fails before reading generated config or opening listeners', () => {
  const result = spawnSync('sh', [startScript], {
    cwd: agentRoot,
    encoding: 'utf8',
    env: { PATH: process.env.PATH },
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /LiveKit Egress v5 image contract marker is missing/);
  assert.match(result.stderr, /pin its verified index before activation/);
  assert.doesNotMatch(result.stderr, /missing generated file/);
});
