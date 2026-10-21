# FPT Knowledge Windows 1.0.1

The final portable release uses direct Groq HTTPS with an owner-authorized
compiled credential. That credential is extractable from the executable; it is
not secret storage. No plaintext credential, private input, personal notes,
student profile or developer AppData is included in source or ZIP staging.
The optional gateway server is not deployed or required.

## Dataset

Dataset version 1, schema 1: 490 curricula, 1,313 subject records, 490
specialization files, with 451 curricula reporting specialization data. Only
690 subjects have nonempty learning outcomes; syllabus completeness varies.
All checked curriculum references and 10,781 specialization references resolve.
The 4,583,066-byte bundled snapshot SHA-256 is:
`472e8ba468d69f8a9a8ec58af34f4ce106b41b549063c5a20b1375d1ef2147dd`.

The owner affirmed permission to redistribute the dataset in this task. That is
an owner attestation, not an independently supplied institutional license.

First launch verifies and installs local assets into AppData. Later launches
use the installation marker and prebuilt search index. Data updates stage and
validate managed records, retain last-good data on failure and never manage
personal notes/chat/settings.

## Update feed

https://raw.githubusercontent.com/nguyenthang135/FPT-KNOWLEDGE-WITH-OBSIDIAN/main/releases/data/latest.json

The manifest is hosted directly from main. Version 1 is the current baseline,
so no new academic delta is needed for this release. Future versioned deltas
are generated using tool/release_database.dart, hash-checked and served from
the same HTTPS origin. Whole application ZIPs are not data updates. No-op
checks use ETag/304 and a 24-hour TTL. Manifests are not independently signed.

## Release procedure and evidence

The EXE supports isolated release checks with --verify-release-online and
--verify-release-offline, guarded by a test-profile marker. They exercise the
actual compiled app's installer, repository, Markdown exporter and Ask FPT
controller. Online reports require a real HTTP 200, a successfully parsed Groq
answer and nonempty academic answer; a local fallback/status label cannot pass.
Offline verification blocks Dart HTTP before exercising local data and notes.
Reports never include a key or Authorization header.

Final measured test/build/EXE/public-download results are recorded in the GitHub
Release notes after verification, rather than inferred from these procedures.
Release binaries are unsigned; the existing project icon is retained. Portable
ZIP includes Flutter/native DLLs, data/assets and Microsoft app-local VC++ CRT.
No installer compiler is required for this portable-only release.

Fresh AppData on this developer machine is not a separate clean Windows VM.
If screen capture fails, visual mouse/keyboard/Obsidian checks remain unverified;
automated executable checks do not substitute for that physical UI coverage.

Recoverable Git bundles, working-tree patch and untracked source backup are
kept privately outside the repository. Old branches are removed only after
main ancestry, verified publication and backup checks; stash entries are retained.
