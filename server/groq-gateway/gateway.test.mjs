import { test } from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createGateway, Quota } from './gateway.mjs';

const request = { model: 'openai/gpt-oss-20b', messages: [{ role: 'user', content: 'CEA201 học gì?' }], max_tokens: 450 };

test('fixed upstream, Vietnamese UTF-8, safe response, input restrictions, quotas', async () => {
  let calls = 0;
  const server = createGateway({ key: 'test-only', quota: new Quota(), upstreamFetch: async (url, options) => {
    calls++;
    assert.equal(url, 'https://api.groq.com/openai/v1/chat/completions');
    assert.equal(JSON.parse(options.body).model, 'openai/gpt-oss-20b');
    assert.equal(JSON.parse(options.body).messages[0].content, 'CEA201 học gì?');
    return new Response(JSON.stringify({ choices: [{ message: { content: 'Kiến trúc máy tính' } }], private: 'not-forwarded' }));
  }});
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const endpoint = `http://127.0.0.1:${server.address().port}/api/ai/chat`;
  const send = body => fetch(endpoint, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  try {
    assert.equal((await send({ ...request, model: 'other' })).status, 400);
    assert.equal((await send({ ...request, max_tokens: 9999 })).status, 400);
    assert.equal((await send({ ...request, url: 'https://elsewhere.invalid' })).status, 400);
    assert.equal((await send({ ...request, messages: [{ role: 'user', content: 'x'.repeat(49000) }] })).status, 400);
    const response = await send(request);
    assert.deepEqual(await response.json(), { choices: [{ message: { role: 'assistant', content: 'Kiến trúc máy tính' } }] });
    for (let i = 0; i < 5; i++) assert.equal((await send(request)).status, 200);
    assert.equal((await send(request)).status, 429);
    assert.equal(calls, 6);
  } finally { await new Promise(done => server.close(done)); }
});

test('daily budget survives restart; global budget and day rollover', () => {
  const folder = mkdtempSync(join(tmpdir(), 'fpt-quota-'));
  const file = join(folder, 'quota.json');
  let now = Date.UTC(2026, 9, 21);
  try {
    const quota = new Quota(file, () => now);
    assert.equal(quota.reserve('a', 600000), true);
    const restarted = new Quota(file, () => now);
    assert.equal(restarted.reserve('b', 600000), false);
    now += 86400000;
    assert.equal(restarted.reserve('b', 600000), true);
  } finally { rmSync(folder, { recursive: true, force: true }); }
});

test('provider errors never expose credentials or messages', async () => {
  const server = createGateway({ key: 'test-only', quota: new Quota(), upstreamFetch: async () => new Response('private provider error', { status: 401 }) });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  try {
    const response = await fetch(`http://127.0.0.1:${server.address().port}/api/ai/chat`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(request) });
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), { error: 'ai_unavailable' });
  } finally { await new Promise(done => server.close(done)); }
});
