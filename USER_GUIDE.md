# FPT Knowledge — quick guide

**Database:** search subjects such as CEA201 or PRM393, read available syllabus
details, and browse curricula offline. Choose your own curriculum in My
Curriculum. Academic records are a snapshot; verify current requirements with
FPT. Not every record has a complete syllabus.

**Ask FPT Beta:** local retrieval and deterministic answers work offline.
Online language planning/answers use direct Groq with a compiled project
credential, which is extractable and shares the owner's quota. Beta can
misinterpret intent; check answers against Database. Limits or connectivity
errors fall back to local behavior. Students never enter a Groq key.

**My Notes:** choose a folder and create subject or linked curriculum Markdown
notes. Source JSON remains read-only. Open notes in optional Obsidian; if it is
missing, install it separately or use another Markdown editor. Your notes remain
in your selected folder, separate from managed database updates.

**Data updates:** Check for data updates appears in the top bar. The project's
public GitHub-hosted manifest is checked in the background at most daily; only
changed records transfer. Offline/errors preserve the last-good database. This
release uses dataset version 1. Data updates do not install
new application versions.

**Privacy:** chats/profile/settings are saved locally in AppData. Online AI sends
your question and selected relevant academic context directly to Groq; avoid
entering private information. No full database or notes folder is sent
automatically. Groq privacy/retention terms and account limits apply.

**Troubleshooting:** retry an offline request later; rate limiting is temporary.
Keep the full portable folder intact. Back up your selected notes folder and
AppData before moving computers. Uninstall/reinstall should preserve these.
