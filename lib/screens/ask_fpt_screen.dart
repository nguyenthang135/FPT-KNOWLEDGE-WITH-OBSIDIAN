import 'package:flutter/material.dart';

import '../ai/ask_fpt_controller.dart';
import '../ai/groq_ai_service.dart';

class AskFptScreen extends StatefulWidget {
  final AskFptController controller;
  final VoidCallback onBrowseDatabase;
  final VoidCallback onOpenCurriculum;
  final VoidCallback onOpenNotes;
  final VoidCallback onProfileChanged;
  final ValueChanged<String> onViewMyNotesItem;
  final ValueChanged<String> onOpenMyNotesItem;

  const AskFptScreen({
    super.key,
    required this.controller,
    required this.onBrowseDatabase,
    required this.onOpenCurriculum,
    required this.onOpenNotes,
    required this.onProfileChanged,
    required this.onViewMyNotesItem,
    required this.onOpenMyNotesItem,
  });

  @override
  State<AskFptScreen> createState() => _AskFptScreenState();
}

class _AskFptScreenState extends State<AskFptScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  static const examples = [
    'HSF có thi PE không?',
    'CEA201 là môn gì?',
    'Kỳ 5 tôi học những môn nào?',
    'Sau học kỳ 4 tôi cần làm gì?',
  ];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_controllerChanged);
  }

  void _controllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? value]) async {
    final question = (value ?? _input.text).trim();
    if (question.isEmpty || _sending) return;
    _input.clear();
    setState(() {
      _sending = true;
    });
    await widget.controller.recordUserMessage(question);
    if (!mounted) return;
    _scrollToEnd();
    final response = await widget.controller.ask(question);
    await widget.controller.recordAssistantResponse(response);
    widget.onProfileChanged();
    if (!mounted) return;
    setState(() {
      _sending = false;
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool get _showOfflineActions {
    final messages = widget.controller.messages;
    final state = messages.isEmpty ? null : messages.last.state;
    return state == AskFptResponseState.offline ||
        state == AskFptResponseState.rateLimited ||
        state == AskFptResponseState.apiError;
  }

  Future<void> _clearConversation() async {
    await widget.controller.clearConversation();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 18),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Ask FPT',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                ),
                TextButton.icon(
                  onPressed: _sending ? null : _clearConversation,
                  icon: const Icon(Icons.add_comment_outlined),
                  label: const Text('New chat'),
                ),
                TextButton(
                  onPressed: _sending ? null : _clearConversation,
                  child: const Text('Clear conversation'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Hỏi bất cứ điều gì về chương trình học FPT của bạn.',
                  ),
                ),
                _GroqStatusChip(
                  diagnostics: widget.controller.groq.diagnostics,
                ),
              ],
            ),
            if (widget.controller.messages.isEmpty) ...[
              const SizedBox(height: 28),
              Text('Ví dụ', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final example in examples)
                    ActionChip(
                      label: Text(example),
                      onPressed: () => _send(example),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            for (final message in widget.controller.messages)
              _MessageBubble(
                message: message,
                onAction: (action) {
                  switch (action.type) {
                    case AskFptActionType.selectSpecialization:
                      _send(action.value);
                      break;
                    case AskFptActionType.changeSpecialization:
                    case AskFptActionType.clearSpecialization:
                      _send(action.value);
                      break;
                    case AskFptActionType.viewMyNotes:
                      widget.onViewMyNotesItem(action.value);
                      break;
                    case AskFptActionType.openObsidian:
                      widget.onOpenMyNotesItem(action.value);
                      break;
                  }
                },
              ),
            if (_sending)
              const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text('Đang tra cứu dữ liệu phù hợp...'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      if (_showOfflineActions)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
          child: Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: widget.onBrowseDatabase,
                child: const Text('Browse Database'),
              ),
              OutlinedButton(
                onPressed: widget.onOpenCurriculum,
                child: const Text('My Curriculum'),
              ),
              OutlinedButton(
                onPressed: widget.onOpenNotes,
                child: const Text('My Notes'),
              ),
            ],
          ),
        ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  enabled: !_sending,
                  minLines: 1,
                  maxLines: 4,
                  autofocus: true,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(
                    hintText: 'Hỏi về môn học, chương trình, học kỳ, thi cử...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                tooltip: 'Send',
                onPressed: _sending ? null : _send,
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _GroqStatusChip extends StatelessWidget {
  final GroqDiagnostics diagnostics;

  const _GroqStatusChip({required this.diagnostics});

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (diagnostics.lastStatus) {
      GroqRequestStatus.success => (
        'AI Online',
        Icons.cloud_done_outlined,
        Colors.green,
      ),
      GroqRequestStatus.unauthorized => (
        'Unauthorized',
        Icons.key_off_outlined,
        Colors.red,
      ),
      GroqRequestStatus.rateLimited => (
        'Rate limited',
        Icons.speed_outlined,
        Colors.orange,
      ),
      GroqRequestStatus.socketError => (
        'Socket error',
        Icons.cloud_off_outlined,
        Colors.red,
      ),
      GroqRequestStatus.tlsError => (
        'TLS error',
        Icons.gpp_bad_outlined,
        Colors.red,
      ),
      GroqRequestStatus.timeout => (
        'Timeout',
        Icons.timer_off_outlined,
        Colors.red,
      ),
      GroqRequestStatus.http5xx => (
        'Groq server error',
        Icons.cloud_off_outlined,
        Colors.red,
      ),
      GroqRequestStatus.httpError ||
      GroqRequestStatus.parseError ||
      GroqRequestStatus.unknownError => (
        'AI error',
        Icons.error_outline,
        Colors.red,
      ),
      _ =>
        diagnostics.keyDetected
            ? ('AI configured', Icons.cloud_outlined, Colors.blue)
            : ('Local mode', Icons.offline_bolt_outlined, Colors.orange),
    };
    return Tooltip(
      message:
          'Groq key detected: ${diagnostics.keyDetected ? 'yes' : 'no'}\n'
          'Model: ${diagnostics.model}\n'
          'Endpoint: ${diagnostics.endpointHost}\n'
          'Last status: ${diagnostics.lastStatus.name}'
          '${diagnostics.lastError == null ? '' : '\nDetail: ${diagnostics.lastError}'}',
      child: Chip(
        avatar: Icon(icon, size: 17, color: color),
        label: Text(label),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final AskFptChatMessage message;
  final ValueChanged<AskFptAction> onAction;

  const _MessageBubble({required this.message, required this.onAction});

  @override
  Widget build(BuildContext context) => Align(
    alignment: message.user ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 760),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: message.user
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.user)
            SelectableText(message.text)
          else
            _StructuredAnswer(
              content:
                  message.content ?? AskFptContent.fromPlainText(message.text),
              onAction: onAction,
            ),
          if (message.source != null) ...[
            const SizedBox(height: 9),
            Text(
              'Nguồn: ${message.source}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    ),
  );
}

class _StructuredAnswer extends StatelessWidget {
  final AskFptContent content;
  final ValueChanged<AskFptAction> onAction;

  const _StructuredAnswer({required this.content, required this.onAction});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (content.title.isNotEmpty) ...[
        Text(content.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
      ],
      if (content.summary.isNotEmpty) SelectableText(content.summary),
      for (final section in content.sections) ...[
        const SizedBox(height: 12),
        if (section.heading case final heading?) ...[
          Text(heading, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
        ],
        _ResponseSection(section: section),
      ],
      if (content.actions.isNotEmpty) ...[
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final action in content.actions)
              action.type == AskFptActionType.selectSpecialization
                  ? ActionChip(
                      label: Text(action.label),
                      onPressed: () => onAction(action),
                    )
                  : OutlinedButton.icon(
                      onPressed: () => onAction(action),
                      icon: Icon(
                        action.type == AskFptActionType.openObsidian
                            ? Icons.open_in_new
                            : action.type ==
                                  AskFptActionType.clearSpecialization
                            ? Icons.clear
                            : action.type ==
                                  AskFptActionType.changeSpecialization
                            ? Icons.swap_horiz
                            : Icons.note_alt_outlined,
                      ),
                      label: Text(action.label),
                    ),
          ],
        ),
      ],
    ],
  );
}

class _ResponseSection extends StatelessWidget {
  final AskFptSection section;

  const _ResponseSection({required this.section});

  @override
  Widget build(BuildContext context) {
    if (section.type == AskFptSectionType.subjectList ||
        section.type == AskFptSectionType.specializationList) {
      return Column(
        children: [
          for (final item in section.items)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 7),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 88,
                    child: Text(
                      item.label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(child: Text(item.value)),
                  if (item.detail case final detail?) ...[
                    const SizedBox(width: 8),
                    Text(detail, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
        ],
      );
    }
    if (section.type == AskFptSectionType.keyValue ||
        section.type == AskFptSectionType.assessmentList) {
      return Column(
        children: [
          for (final item in section.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item.label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(child: Text(item.value, textAlign: TextAlign.end)),
                  if (item.detail case final detail?) ...[
                    const SizedBox(width: 12),
                    Flexible(child: Text(detail)),
                  ],
                ],
              ),
            ),
        ],
      );
    }
    final bullet = section.type == AskFptSectionType.bulletList;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in section.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              '${bullet ? '• ' : ''}'
              '${item.label.isEmpty ? '' : '${item.label}: '}'
              '${item.value}',
            ),
          ),
      ],
    );
  }
}
