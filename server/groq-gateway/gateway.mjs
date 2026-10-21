import http from 'node:http';
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync, renameSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const MODEL = 'openai/gpt-oss-20b';
const UPSTREAM = 'https://api.groq.com/openai/v1/chat/completions';
const MAX_BODY = 64 * 1024;
const MAX_CONTENT = 48000;

// One process/replica only. Daily reservations survive restarts; storage failure
// denies AI. Put behind an HTTPS proxy that replaces forwarding headers.
export class Quota {
  constructor(file, now = () => Date.now()) {
    this.file = file;
    this.now = now;
    this.minute = new Map();
    this.active = 0;
    if (file) {
      mkdirSync(dirname(file), { recursive: true });
      try { this.daily = JSON.parse(readFileSync(file, 'utf8')); }
      catch (error) {
        if (error.code !== 'ENOENT') throw new Error('Quota storage is invalid');
      }
    }
    this.daily ??= { day: '', requests: 0, tokens: 0, clients: {} };
  }

  reserve(ip, tokens) {
    const now = this.now();
    const day = new Date(now).toISOString().slice(0, 10);
    if (this.daily.day !== day) this.daily = { day, requests: 0, tokens: 0, clients: {} };
    for (const [id, record] of this.minute) {
      if (record.until <= now) this.minute.delete(id);
    }
    const client = createHash('sha256').update(`${day}:${ip}`).digest('hex');
    const ipMinute = this.minute.get(client)?.count ?? 0;
    const globalMinute = this.minute.get('global')?.count ?? 0;
    if (this.active >= 4 || ipMinute >= 6 || globalMinute >= 30 ||
        (this.daily.clients[client] ?? 0) >= 40 || this.daily.requests >= 500 ||
        this.daily.tokens + tokens > 1000000) return false;
    this.daily.requests++;
    this.daily.tokens += tokens; // Conservative byte-based reservation, no refunds.
    this.daily.clients[client] = (this.daily.clients[client] ?? 0) + 1;
    if (this.file) {
      writeFileSync(`${this.file}.tmp`, JSON.stringify(this.daily), { mode: 0o600 });
      renameSync(`${this.file}.tmp`, this.file);
    }
    for (const id of [client, 'global']) {
      const record = this.minute.get(id) ?? { until: now + 60000, count: 0 };
      record.count++;
      this.minute.set(id, record);
    }
    this.active++;
    return true;
  }
}

function validate(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  if (Object.keys(value).some(key => !['model', 'messages', 'temperature', 'max_tokens'].includes(key))) return null;
  if (value.model !== undefined && value.model !== MODEL) return null;
  if (!Array.isArray(value.messages) || value.messages.length < 1 || value.messages.length > 6) return null;
  let bytes = 0;
  const messages = [];
  for (const message of value.messages) {
    if (!message || Object.keys(message).some(key => !['role', 'content'].includes(key)) ||
        !['system', 'user', 'assistant'].includes(message.role) ||
        typeof message.content !== 'string' || !message.content.trim()) return null;
    bytes += Buffer.byteLength(message.content);
    messages.push({ role: message.role, content: message.content });
  }
  const maxTokens = value.max_tokens ?? 700;
  const temperature = value.temperature ?? 0.1;
  if (bytes > MAX_CONTENT || !Number.isInteger(maxTokens) || maxTokens < 1 || maxTokens > 700 ||
      typeof temperature !== 'number' || temperature < 0 || temperature > 0.2) return null;
  return { body: { model: MODEL, messages, temperature, max_tokens: maxTokens }, tokens: bytes + maxTokens + 128 };
}

function reply(res, code, data) {
  res.writeHead(code, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
    ...(code === 429 ? { 'retry-after': '60' } : {}),
  });
  res.end(JSON.stringify(data));
}

export function createGateway({ key, quota, upstreamFetch = fetch, trustProxy = false } = {}) {
  if (!quota) throw new Error('Persistent quota storage is required');
  const server = http.createServer(async (req, res) => {
    if (req.url === '/health' && req.method === 'GET') {
      reply(res, key ? 200 : 503, { ready: Boolean(key), model: MODEL });
      return;
    }
    if (req.url !== '/api/ai/chat') { reply(res, 404, { error: 'not_found' }); return; }
    if (req.method !== 'POST') { reply(res, 405, { error: 'method_not_allowed' }); return; }
    if (!key) { reply(res, 503, { error: 'ai_unavailable' }); return; }
    if (trustProxy && req.headers['x-forwarded-proto'] !== 'https') {
      reply(res, 400, { error: 'https_required' }); return;
    }
    if (!(req.headers['content-type'] ?? '').toLowerCase().startsWith('application/json')) {
      reply(res, 415, { error: 'json_required' }); return;
    }
    if (Number(req.headers['content-length']) > MAX_BODY) { reply(res, 413, { error: 'request_too_large' }); return; }
    let reserved = false;
    try {
      const chunks = [];
      let bytes = 0;
      for await (const chunk of req) {
        bytes += chunk.length;
        if (bytes > MAX_BODY) { reply(res, 413, { error: 'request_too_large' }); return; }
        chunks.push(chunk);
      }
      let input;
      try { input = validate(JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks)))); }
      catch { reply(res, 400, { error: 'invalid_request' }); return; }
      if (!input) { reply(res, 400, { error: 'invalid_request' }); return; }
      // Trust only a controlled local reverse proxy, never arbitrary client IDs.
      const ip = trustProxy ? req.headers['x-real-ip'] : req.socket.remoteAddress;
      if (typeof ip !== 'string' || !ip) { reply(res, 400, { error: 'client_address_required' }); return; }
      reserved = quota.reserve(ip, input.tokens);
      if (!reserved) { reply(res, 429, { error: 'quota_reached' }); return; }
      const upstream = await upstreamFetch(UPSTREAM, {
        method: 'POST',
        headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json; charset=utf-8' },
        body: JSON.stringify(input.body),
        signal: AbortSignal.timeout(20000),
        redirect: 'error',
      });
      if (!upstream.ok) {
        await upstream.body?.cancel();
        reply(res, upstream.status === 429 ? 429 : 503, { error: upstream.status === 429 ? 'quota_reached' : 'ai_unavailable' });
        return;
      }
      let responseBytes = 0;
      const parts = [];
      for await (const part of upstream.body) {
        responseBytes += part.length;
        if (responseBytes > 65536) throw new Error('Invalid upstream response');
        parts.push(part);
      }
      const value = JSON.parse(Buffer.concat(parts).toString('utf8'));
      const content = value.choices?.[0]?.message?.content;
      if (typeof content !== 'string' || !content.trim() || Buffer.byteLength(content) > 32000) throw new Error('Invalid upstream response');
      reply(res, 200, { choices: [{ message: { role: 'assistant', content } }] });
    } catch {
      // Never return upstream errors, prompts, HTTP headers, or secrets.
      if (!res.headersSent) reply(res, 503, { error: 'ai_unavailable' });
    } finally {
      if (reserved) quota.active--;
    }
  });
  server.requestTimeout = 25000;
  server.headersTimeout = 10000;
  server.maxConnections = 64;
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const quota = new Quota(resolve(process.env.QUOTA_FILE ?? '.gateway-state/quota.json'));
  createGateway({ key: process.env.GROQ_API_KEY, quota, trustProxy: process.env.TRUST_LOCAL_PROXY === '1' })
    .listen(Number(process.env.PORT ?? 8787), '127.0.0.1', () => console.log('FPT Knowledge gateway listening on loopback'));
}
