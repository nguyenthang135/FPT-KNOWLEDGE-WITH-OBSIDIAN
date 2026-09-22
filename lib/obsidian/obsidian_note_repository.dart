import 'dart:io';

import 'obsidian_service.dart';

class ObsidianNotesResult {
  final String? notes;
  final String status;

  const ObsidianNotesResult({required this.notes, required this.status});

  bool get hasNotes => notes != null && notes!.trim().isNotEmpty;
}

class ObsidianNoteRepository {
  final ObsidianService _obsidianService;
  final Future<String?> Function()? _vaultPathProvider;

  factory ObsidianNoteRepository({
    ObsidianService? obsidianService,
    Future<String?> Function()? vaultPathProvider,
  }) {
    return ObsidianNoteRepository._(
      obsidianService ?? ObsidianService(),
      vaultPathProvider,
    );
  }

  ObsidianNoteRepository._(
    this._obsidianService,
    this._vaultPathProvider,
  );

  Future<ObsidianNotesResult> readMyNotes({
    required String curriculumCode,
    required String subjectCode,
  }) async {
    final vaultPath = _vaultPathProvider != null
        ? await _vaultPathProvider()
        : await _obsidianService.getSavedVaultPath();

    if (vaultPath == null || vaultPath.trim().isEmpty) {
      return const ObsidianNotesResult(
        notes: null,
        status: 'Chưa chọn Vault Obsidian. Chatbot sẽ chỉ dùng syllabus FLM.',
      );
    }

    final notesFile = File(
      _join(
        vaultPath,
        'FPT Knowledge',
        _safeSegment(curriculumCode),
        'Subjects',
        _safeSegment(subjectCode),
        'My Notes.md',
      ),
    );

    if (!await notesFile.exists()) {
      return const ObsidianNotesResult(
        notes: null,
        status:
            'Chưa có My Notes.md cho môn này. Chatbot sẽ chỉ dùng syllabus FLM.',
      );
    }

    try {
      final content = (await notesFile.readAsString()).trim();
      if (content.isEmpty) {
        return const ObsidianNotesResult(
          notes: null,
          status: 'My Notes.md đang trống. Chatbot sẽ chỉ dùng syllabus FLM.',
        );
      }

      return ObsidianNotesResult(
        notes: content,
        status: 'Đã dùng My Notes.md từ Obsidian làm ngữ cảnh.',
      );
    } on FileSystemException {
      return const ObsidianNotesResult(
        notes: null,
        status: 'Không thể đọc My Notes.md. Chatbot sẽ chỉ dùng syllabus FLM.',
      );
    }
  }

  String _safeSegment(String value) {
    return value.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  String _join(
    String first,
    String second, [
    String? third,
    String? fourth,
    String? fifth,
    String? sixth,
  ]) {
    return [first, second, third, fourth, fifth, sixth]
        .whereType<String>()
        .where((part) => part.isNotEmpty)
        .join(Platform.pathSeparator);
  }
}
