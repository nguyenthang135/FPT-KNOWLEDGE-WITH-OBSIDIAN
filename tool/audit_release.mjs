import { execFileSync } from 'node:child_process';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { resolve, join, relative } from 'node:path';
import { inflateRawSync } from 'node:zlib';

// Report locations/types only. Never print matching secret values.
const rules = [
  ['provider key', /\bgsk_[A-Za-z0-9]{20,}\b/],
  ['GitHub token', /\b(?:gh[pousr]_[A-Za-z0-9]{25,}|github_pat_[A-Za-z0-9_]{30,})\b/],
  ['private key', /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/],
  ['session cookie', /(?:ASP\.NET_SessionId|\.ASPXAUTH|FedAuth)=[A-Za-z0-9%+/_=-]{12,}/i],
];
const findings = [];
let acceptedCompiledCredential = false;
function scan(bytes, location, depth = 0) {
  for (const encoding of ['utf8', 'utf16le']) {
    const text = bytes.toString(encoding);
    for (const [kind, expression] of rules) if (expression.test(text)) {
      if (process.argv.includes('--allow-compiled-groq') &&
          location.replaceAll('\\', '/') === 'artifact:data/app.so' && kind === 'provider key') {
        acceptedCompiledCredential = true;
      } else findings.push({ location, kind });
    }
  }
  // Scan compressed snapshot/archive contents too, including history blobs.
  if (bytes.length >= 22 && bytes.readUInt32LE(0) === 0x04034b50 && depth < 2) {
    try {
      let end = bytes.length - 22;
      while (end >= Math.max(0, bytes.length - 65557) && bytes.readUInt32LE(end) !== 0x06054b50) end--;
      if (end < 0) throw new Error('Invalid ZIP');
      const count = bytes.readUInt16LE(end + 10);
      let offset = bytes.readUInt32LE(end + 16);
      let expanded = 0;
      for (let i = 0; i < count; i++) {
        if (bytes.readUInt32LE(offset) !== 0x02014b50) throw new Error('Invalid ZIP index');
        const method = bytes.readUInt16LE(offset + 10);
        const size = bytes.readUInt32LE(offset + 20);
        const nameLength = bytes.readUInt16LE(offset + 28);
        const name = bytes.subarray(offset + 46, offset + 46 + nameLength).toString('utf8');
        const local = bytes.readUInt32LE(offset + 42);
        const start = local + 30 + bytes.readUInt16LE(local + 26) + bytes.readUInt16LE(local + 28);
        const packed = bytes.subarray(start, start + size);
        const unpacked = method === 0 ? packed : method === 8 ? inflateRawSync(packed, { maxOutputLength: 100 * 1024 * 1024 }) : null;
        if (!unpacked || (expanded += unpacked.length) > 250 * 1024 * 1024) throw new Error('Unsupported ZIP or size limit');
        if (!name.endsWith('/')) scan(unpacked, `${location}!${name}`, depth + 1);
        offset += 46 + nameLength + bytes.readUInt16LE(offset + 30) + bytes.readUInt16LE(offset + 32);
      }
    } catch { findings.push({ location, kind: 'archive could not be fully scanned' }); }
  }
}
const git = (...args) => execFileSync('git', args, { maxBuffer: 100 * 1024 * 1024 });
if (process.argv[2]) {
  const root = resolve(process.argv[2]);
  function walk(folder) {
    for (const entry of readdirSync(folder, { withFileTypes: true })) {
      const path = join(folder, entry.name);
      if (entry.isDirectory()) walk(path);
      else if (entry.isFile()) scan(readFileSync(path), `artifact:${relative(root, path)}`);
    }
  }
  walk(root);
} else {
  const files = git('ls-files', '-z').toString().split('\0').filter(Boolean);
  for (const path of files) if (existsSync(path)) scan(readFileSync(path), `worktree:${path}`);
  const untracked = git('ls-files', '--others', '--exclude-standard', '-z').toString().split('\0').filter(Boolean);
  for (const path of untracked) scan(readFileSync(path), `untracked:${path}`);
  const objects = git('rev-list', '--objects', '--all').toString().trim().split('\n');
  let blobs = 0;
  for (const line of objects) {
    const [sha, ...names] = line.split(' ');
    if (git('cat-file', '-t', sha).toString().trim() !== 'blob') continue;
    blobs++;
    scan(git('cat-file', 'blob', sha), `history:${sha.slice(0, 12)}:${names.join(' ')}`);
  }
  console.log(`Scanned ${files.length} tracked files and ${blobs} reachable history blobs.`);
  const sensitiveNames = files.filter(path => /(?:\.env(?:\.|$)|\.pfx$|\.p12$|PRIVATE_GROQ|app_settings\.json|ask_fpt_chat|webview_profile|\.log$)/i.test(path));
  for (const path of sensitiveNames) findings.push({ location: path, kind: 'sensitive tracked path' });
}
for (const finding of findings) console.log(JSON.stringify(finding));
console.log(`Potential secret findings: ${findings.length}`);
if (acceptedCompiledCredential) console.log('Owner-authorized extractable Groq credential detected in compiled app.so; no plaintext credential files allowed.');
if (findings.length) process.exitCode = 1;
