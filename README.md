# FPT Knowledge

**Your FPT subjects, curriculum and study notes — together on your computer.**

Think of FPT Knowledge as an **FLM-style academic reference for your desktop**:
look up a subject, understand what it covers, check your semester subjects and
turn useful information into your own study notes. The academic database comes
with the app, so you can start browsing **without logging into FLM**, including
when you are offline.

Ask FPT adds a conversational way to explore that information. Instead of
searching through syllabus sections yourself, ask a question in Vietnamese and
get a readable explanation based on the available academic data.

This is an independent student project, not an official replacement for FLM or
FAP. It does not manage your grades, attendance or course registration.

[Download FPT Knowledge for Windows](https://github.com/nguyenthang135/FPT-KNOWLEDGE-WITH-OBSIDIAN/releases/latest)

1. Download the named **Windows-Portable.zip** asset, not Source code ZIP.
2. Extract the entire **FPT Knowledge** folder.
3. Double-click **FPT Knowledge.exe**; keep its DLLs and `data` folder beside it.

Requires **Windows 10/11 x64**. You do not need Flutter, Node.js, a terminal,
an FLM account or your own AI API key to use the downloaded app. Obsidian is
optional, not a requirement for browsing the database.

## What can I do with it?

### Database — find and understand a subject

Search by subject code or name, such as **CEA201**, **PRM393**, or
**Computer Organization**. Open a subject to read its available information in
organized sections rather than working through a raw data file.

Depending on the record, you can find:

- What the subject is about and what you are expected to learn.
- Credits, prerequisites and other available course requirements.
- Assessment components, their weights and available passing requirements.
- Learning outcomes, textbooks and other learning materials.

You can also browse curricula and follow their subject entries. The bundled
snapshot contains **490 curricula and 1,313 subject records**. Some records have
more complete syllabus details than others; missing information is not filled
in with invented facts.

### My Curriculum — see how subjects fit into your studies

Find the curriculum that matches your programme/cohort and choose
**Use this curriculum** to save it. My Curriculum keeps your saved curricula
together, with one active curriculum for personal questions.

Browse subjects by semester, check their credits and prerequisites, and select
a professional specialization where the curriculum provides one. Your
specialization is your choice: the app should not silently assume it for you.
This gives questions such as “Kỳ 5 tôi học những môn gì?” a useful academic
context instead of treating every student as following the same programme.

### Ask FPT — ask about academic information in normal language

Ask directly about a subject without entering a Student ID first. For questions
about *your* semesters or curriculum, set your active curriculum in
**My Curriculum** so the app has the right context.

For example:

> CEA201 là môn gì? Giải thích ngắn gọn bằng tiếng Việt.
>
> PRM393 được đánh giá như thế nào?
>
> Môn CEA201 sử dụng tài liệu gì?
>
> Kỳ 5 tôi học những môn gì?

The AI retrieves relevant local academic information and helps present it in a
more readable form. Vietnamese is the default language. **Ask FPT is Beta**:
it can misunderstand a request or lack enough information, so check important
answers against the subject record and official FPT guidance.

Online AI needs an internet connection and shares the project's Groq quota.
Students do not enter a key. If AI is unavailable or rate-limited, you can still
browse the local database and use the app's available local answers.

### My Notes — turn academic information into your own knowledge base

Use **Add to My Notes** from a subject or curriculum to create Markdown notes
from the local academic data. Choose a notes folder, collect individual subjects
or export a linked curriculum, then add your own explanations and study notes.

Curriculum exports use links between related notes, so you can move from a
curriculum to its subjects. Open them in **Obsidian** for a connected Markdown
workspace, or use another Markdown editor. Your personal notes live separately
from the read-only source database; changing your notes does not change the
academic records.

## A simple first session

1. Open **Database**, search for a subject you are studying and read its details.
2. Find your curriculum and select **Use this curriculum**.
3. Open **Ask FPT** to ask about a subject or your semester.
4. Choose **Add to My Notes** for information you want to keep and build on.

## What works offline?

The bundled database, subject/curriculum browsing and Markdown exports work
locally. Your first launch prepares the included data; it does not require an
FLM login, a new crawl or a database download. Later launches reuse the installed
data. Chats, profile/settings and your chosen notes folder are saved locally.

Internet is needed for Groq-powered AI and optional data-update checks.
**Check for data updates** checks the project's published version manifest;
compatible updates transfer changed records instead of recrawling FLM. Updates
manage academic data, not your personal notes. The database is a snapshot,
not a live view of every change on FLM.

## Important notes

- Verify current academic rules with FPT; this app is a study/reference companion.
- Online AI sends your question and selected academic context to Groq. Avoid
  entering private information.
- AI availability is limited by the shared account quota. The owner chose a
  compiled credential, which is extractable from the binary; it is not secret
  storage or a promise of unlimited service.

See [INSTALL.md](INSTALL.md), [USER_GUIDE.md](USER_GUIDE.md) and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for more help and distribution
terms, and [RELEASE_STATUS.md](RELEASE_STATUS.md) for release verification details.

<details>
<summary>For developers and maintainers</summary>

### Development

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

</details>

