import { execFileSync } from 'node:child_process';
import { readFileSync, statSync } from 'node:fs';
import { basename, resolve } from 'node:path';
import { createHash } from 'node:crypto';

const repo = 'nguyenthang135/FPT-KNOWLEDGE-WITH-OBSIDIAN';
const api = `https://api.github.com/repos/${repo}`;
const credential = execFileSync('git', ['credential', 'fill'], {
  input: 'protocol=https\nhost=github.com\n\n', encoding: 'utf8',
  env: { ...process.env, GIT_TERMINAL_PROMPT: '0' }, stdio: ['pipe', 'pipe', 'pipe'],
});
const token = credential.split(/\r?\n/).find(line => line.startsWith('password='))?.slice(9);
if (!token) throw new Error('GitHub credential unavailable');
async function call(url, method = 'GET', body, type = 'application/json') {
  const response = await fetch(url, {
    method, headers: { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28', ...(body ? { 'Content-Type': type } : {}) },
    body: body && (type === 'application/json' ? JSON.stringify(body) : body),
    signal: AbortSignal.timeout(120000),
  });
  if (!response.ok) throw new Error(`GitHub ${method}: HTTP ${response.status}`);
  return response.status === 204 ? null : response.json();
}
const [command, tag, ...args] = process.argv.slice(2);
if (command === 'inspect') {
  const user = await call('https://api.github.com/user');
  const repository = await call(api);
  const releases = await call(`${api}/releases?per_page=10`);
  console.log(JSON.stringify({ user: user.login, private: repository.private, defaultBranch: repository.default_branch,
    canPush: repository.permissions?.push, canAdmin: repository.permissions?.admin,
    releases: releases.map(r => ({ tag: r.tag_name, draft: r.draft, url: r.html_url })) }));
} else if (command === 'draft') {
  const release = await call(`${api}/releases`, 'POST', { tag_name: tag, target_commitish: 'main', name: `FPT Knowledge ${tag}`, draft: true,
    body: readFileSync(resolve(args[0]), 'utf8') });
  console.log(JSON.stringify({ id: release.id, url: release.html_url, draft: release.draft }));
} else if (command === 'upload') {
  const id = tag;
  for (const path of args) {
    const bytes = readFileSync(resolve(path));
    const asset = await call(`https://uploads.github.com/repos/${repo}/releases/${id}/assets?name=${encodeURIComponent(basename(path))}`,
      'POST', bytes, 'application/octet-stream');
    console.log(JSON.stringify({ name: asset.name, size: asset.size, url: asset.browser_download_url }));
  }
} else if (command === 'publish') {
  const release = await call(`${api}/releases/${tag}`, 'PATCH', { draft: false });
  console.log(JSON.stringify({ url: release.html_url, tag: release.tag_name, assets: release.assets.map(a => ({name:a.name,size:a.size,url:a.browser_download_url})) }));
} else if (command === 'verify') {
  const response = await fetch(`https://github.com/${repo}/releases/tag/${tag}`, { signal: AbortSignal.timeout(30000) });
  if (!response.ok) throw new Error(`Anonymous release page: HTTP ${response.status}`);
  const release = await call(`${api}/releases/tags/${tag}`);
  for (const path of args) {
    const asset = release.assets.find(asset => asset.name === basename(path));
    if (!asset) throw new Error(`Release asset missing: ${basename(path)}`);
    const download = await fetch(asset.browser_download_url, { signal: AbortSignal.timeout(120000) });
    if (!download.ok) throw new Error(`Anonymous download: HTTP ${download.status}`);
    const hash = createHash('sha256'); let size = 0;
    for await (const part of download.body) { hash.update(part); size += part.length; }
    const local = createHash('sha256').update(readFileSync(path)).digest('hex');
    if (hash.digest('hex') !== local || size !== statSync(path).size) throw new Error('Downloaded checksum mismatch');
    console.log(JSON.stringify({name:asset.name, size, anonymousDownload:'PASS', sha256:local}));
  }
  console.log(`Verified public release: ${release.html_url}`);
} else { throw new Error('Expected inspect, draft, upload, publish or verify'); }
