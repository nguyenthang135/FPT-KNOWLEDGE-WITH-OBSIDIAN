import 'package:flutter/material.dart';

import '../../flm/flm_syllabus_service.dart';
import '../../models/curriculum_subject.dart';
import '../../obsidian/obsidian_note_repository.dart';
import '../ai_chat_request.dart';
import '../ai_chat_response.dart';
import '../ai_chat_service.dart';
import '../ai_prompt_builder.dart';
import '../gemini_ai_chat_service.dart';
import '../mock_ai_chat_service.dart';

class AiAssistantDialog extends StatefulWidget {
  final String curriculumCode;
  final CurriculumSubject subject;
  final SyllabusDetailResult syllabus;

  const AiAssistantDialog({
    super.key,
    required this.curriculumCode,
    required this.subject,
    required this.syllabus,
  });

  @override
  State<AiAssistantDialog> createState() => _AiAssistantDialogState();
}

class _AiAssistantDialogState extends State<AiAssistantDialog> {
  static const _apiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const _model = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-3.8-flash',
  );

  final _questionController = TextEditingController();
  final _notesRepository = ObsidianNoteRepository();
  final _promptBuilder = const AiPromptBuilder();
  final List<_ChatMessage> _messages = [];

  bool _useObsidianNotes = true;
  bool _loadingNotes = true;
  bool _asking = false;
  String? _obsidianNotes;
  String _notesStatus = 'Đang kiểm tra My Notes.md...';

  @override
  void initState() {
    super.initState();
    _loadObsidianNotes();
  }

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  Future<void> _loadObsidianNotes() async {
    final result = await _notesRepository.readMyNotes(
      curriculumCode: widget.curriculumCode,
      subjectCode: widget.subject.code,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _obsidianNotes = result.notes;
      _notesStatus = result.status;
      _loadingNotes = false;
      if (!result.hasNotes) {
        _useObsidianNotes = false;
      }
    });
  }

  AiChatService get _chatService => _apiKey.trim().isEmpty
      ? const MockAiChatService()
      : GeminiAiChatService(apiKey: _apiKey, model: _model);

  Future<void> _send([String? quickQuestion]) async {
    final question = (quickQuestion ?? _questionController.text).trim();
    if (question.isEmpty || _asking) {
      return;
    }

    final request = AiChatRequest(
      curriculumCode: widget.curriculumCode,
      subjectCode: widget.subject.code,
      subjectName: widget.subject.name,
      syllabusContext: _promptBuilder.buildSyllabusContext(
        subject: widget.subject,
        syllabus: widget.syllabus,
      ),
      question: question,
      obsidianNotes: _useObsidianNotes ? _obsidianNotes : null,
    );

    setState(() {
      _asking = true;
      _messages.add(_ChatMessage.user(question));
      _questionController.clear();
    });

    try {
      final response = await _chatService.ask(request);
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.add(_ChatMessage.assistant(response));
      });
    } on AiChatException catch (error) {
      _addError(error.message);
    } catch (_) {
      _addError('Trợ lý AI gặp lỗi không xác định. Hãy thử lại.');
    } finally {
      if (mounted) {
        setState(() {
          _asking = false;
        });
      }
    }
  }

  void _addError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _messages.add(_ChatMessage.error(message));
    });
  }

  @override
  Widget build(BuildContext context) {
    final usingGemini = _apiKey.trim().isNotEmpty;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Trợ lý AI — ${widget.subject.code}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Đóng',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                usingGemini
                    ? 'Gemini AI đang trả lời dựa trên ngữ cảnh môn học.'
                    : 'Chế độ dữ liệu demo: thêm GEMINI_API_KEY để dùng AI thật.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              _ObsidianContextCard(
                loading: _loadingNotes,
                enabled: _useObsidianNotes,
                available: _obsidianNotes != null,
                status: _notesStatus,
                onChanged: _loadingNotes || _obsidianNotes == null
                    ? null
                    : (value) {
                        setState(() {
                          _useObsidianNotes = value;
                        });
                      },
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _QuickQuestionChip(
                    label: 'Tóm tắt môn',
                    onPressed: _asking
                        ? null
                        : () => _send(
                            'Hãy tóm tắt môn học này thành 5 ý dễ nhớ.',
                          ),
                  ),
                  _QuickQuestionChip(
                    label: 'Cách đánh giá',
                    onPressed: _asking
                        ? null
                        : () => _send('Môn này được đánh giá như thế nào?'),
                  ),
                  _QuickQuestionChip(
                    label: 'Kế hoạch ôn tập',
                    onPressed: _asking
                        ? null
                        : () =>
                              _send('Gợi ý kế hoạch ôn tập ngắn cho môn này.'),
                  ),
                  _QuickQuestionChip(
                    label: 'Quiz 3 câu',
                    onPressed: _asking
                        ? null
                        : () => _send(
                            'Tạo 3 câu hỏi ôn tập dựa trên dữ liệu hiện có.',
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: _messages.isEmpty
                    ? const _EmptyConversation()
                    : ListView.separated(
                        itemCount: _messages.length + (_asking ? 1 : 0),
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          if (index == _messages.length) {
                            return const _ThinkingBubble();
                          }
                          return _MessageBubble(message: _messages[index]);
                        },
                      ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _questionController,
                      enabled: !_asking,
                      minLines: 1,
                      maxLines: 3,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Hỏi về môn học hoặc ghi chú của bạn...',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _asking ? null : _send,
                    icon: const Icon(Icons.send),
                    label: const Text('Gửi'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;
  final bool isError;
  final AiChatResponse? response;

  const _ChatMessage._({
    required this.text,
    required this.isUser,
    required this.isError,
    this.response,
  });

  factory _ChatMessage.user(String text) =>
      _ChatMessage._(text: text, isUser: true, isError: false);

  factory _ChatMessage.assistant(AiChatResponse response) => _ChatMessage._(
    text: response.answer,
    isUser: false,
    isError: false,
    response: response,
  );

  factory _ChatMessage.error(String text) =>
      _ChatMessage._(text: text, isUser: false, isError: true);
}

class _ObsidianContextCard extends StatelessWidget {
  final bool loading;
  final bool enabled;
  final bool available;
  final String status;
  final ValueChanged<bool>? onChanged;

  const _ObsidianContextCard({
    required this.loading,
    required this.enabled,
    required this.available,
    required this.status,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SwitchListTile(
        value: enabled,
        onChanged: onChanged,
        secondary: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(available ? Icons.note_alt_outlined : Icons.note_outlined),
        title: const Text('Dùng My Notes.md từ Obsidian'),
        subtitle: Text(status),
      ),
    );
  }
}

class _QuickQuestionChip extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _QuickQuestionChip({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ActionChip(label: Text(label), onPressed: onPressed);
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Chọn một câu hỏi nhanh hoặc nhập câu hỏi của bạn.\n'
        'Chatbot chỉ dùng syllabus FLM và ghi chú bạn cho phép.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 10),
        Text('Trợ lý AI đang soạn câu trả lời...'),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = message.isUser
        ? colorScheme.primaryContainer
        : message.isError
        ? colorScheme.errorContainer
        : colorScheme.surfaceContainerHighest;

    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 620),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.isUser
                  ? 'Bạn'
                  : message.isError
                  ? 'Lỗi'
                  : 'Trợ lý AI',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            SelectableText(message.text),
            if (message.response != null) ...[
              const SizedBox(height: 10),
              Text(
                'Nguồn: ${message.response!.sourceLabel}'
                '${message.response!.isDemo ? ' • Dữ liệu demo' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
