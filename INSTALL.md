# Install FPT Knowledge (Windows 10/11 x64)

Use a named Windows portable ZIP or Setup EXE from a verified GitHub Release.
GitHub's automatic Source code ZIP is developer source, not the Windows app.
Download the named FPT-Knowledge Windows portable asset, not a source archive.

Portable: extract the complete folder, then double-click **FPT Knowledge.exe**.
Keep its DLLs and data folder beside it. No Flutter SDK, terminal, API key,
administrator login or FLM login is required for normal offline use.
Online Ask FPT uses direct Groq with a compiled project credential, which is
extractable and shares the owner's quota. Students configure no key.
The app-local Microsoft VC++ runtime DLLs are included. Installer: run Setup;
use its Start Menu shortcut. Unsigned builds may trigger Windows SmartScreen;
verify the publisher/checksum and follow your organization's security policy.

First launch installs the bundled database to `%APPDATA%\FPT Knowledge\Database`.
It requires no database download. Later launches use a small marker/manifest
instead of unpacking and scanning everything again. Keep personal notes in your
chosen folder; settings and chats remain in AppData. Updates and uninstall do
not intentionally erase either location.

If startup fails, use Retry. If DLLs are missing, extract the entire ZIP again.
Obsidian is optional and installed separately. WebView2 is needed only for the
maintainer's optional FLM collection screen, not offline browsing.

See USER_GUIDE.md for offline features, AI availability and privacy.
