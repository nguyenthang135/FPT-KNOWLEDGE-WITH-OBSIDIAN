# FPT Knowledge

Windows curriculum/subject browser with offline academic JSON, My Curriculum,
Markdown notes, optional Obsidian integration, and Ask FPT Beta.

[Download FPT Knowledge for Windows](https://github.com/nguyenthang135/FPT-KNOWLEDGE-WITH-OBSIDIAN/releases/latest)

1. Download the named **Windows-Portable.zip** asset, not Source code ZIP.
2. Extract the entire **FPT Knowledge** folder.
3. Double-click **FPT Knowledge.exe**; keep its DLLs and `data` folder beside it.

Windows 10/11 x64. Ask FPT Beta uses direct Groq HTTPS with the owner's compiled
credential, which can be extracted from the binary. Online usage/quota is shared
and may become unavailable. Offline browsing remains available. No unlimited
service promise is made. See RELEASE_STATUS.md for verification.

Normal use needs no Flutter SDK, terminal, FLM login or API key. The approved
bundled snapshot contains 490 curricula and 1,313 subject records. Syllabus depth
varies. The first launch installs it from the package; subsequent launches use
the installation marker and a prebuilt search index.

See [INSTALL.md](INSTALL.md), [USER_GUIDE.md](USER_GUIDE.md) and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for use and distribution terms.

## Development

Install a compatible Flutter Windows SDK and Visual Studio C++ desktop tools.
Run `flutter pub get`, `flutter run -d windows`, `flutter analyze`, `flutter test`.
Local debug-only Groq configuration can use GROQ_API_KEY/GROQ_MODEL environment
variables. Never commit their values. Release builds receive GROQ_API_KEY and
GROQ_MODEL via a temporary private `--dart-define-from-file` input created by the
packaging script. This compiled credential is extractable, not secret storage.
The optional gateway source is not used or deployed by this release.

Maintainers validate/prepare a snapshot with
`dart run tool/release_database.dart prepare assets/database/fpt_knowledge_database.zip`.
Generate an incremental ZIP/manifest from versioned snapshots with
`dart run tool/release_database.dart delta old.zip new.zip delta.zip`.
Publish both at an approved HTTPS origin; configure `FPT_DATA_UPDATE_URL` with
the manifest's real URL. Preserve prior snapshots. The app checks hashes and
same-origin HTTPS; trust depends on the publisher's HTTPS account. Manifests are
not independently signed. Major schema/full-snapshot migrations are not automatic.

`tool/package_windows.ps1` builds the complete Windows runtime. Supply the
Flutter BAT path, Microsoft REDIST x64 CRT directory and `-DirectGroqPrivateInput`
pointing to your private local CMD-style configuration outside Git. Temporary
secret JSON is removed after build; no plaintext key is published. Final output
is the source folder's sibling `FPT Knowledge`, with the portable ZIP beside it.
Existing vault/notes and unknown files are preserved. ZIPs come only from clean
release staging, never your personal vault. Portable ZIP is sufficient; optional
Inno installer source requires its compiler.

