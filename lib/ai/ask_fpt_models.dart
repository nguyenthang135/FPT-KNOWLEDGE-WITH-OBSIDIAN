enum ActiveContextProvenance {
  none,
  studentIdResolved,
  explicitUseSelection,
  restoredExplicitProfile,
}

enum SpecializationProvenance {
  none,
  explicitUserSelection,
  restoredExplicitSelection,
}

enum AskFptResponseState {
  answered,
  needsStudentContext,
  clarification,
  offline,
  rateLimited,
  apiError,
  databaseUnavailable,
  outOfScope,
  notesSuccess,
  notesFailure,
}

enum AskFptSectionType {
  paragraph,
  bulletList,
  subjectList,
  keyValue,
  assessmentList,
  info,
  specializationList,
}

enum AskFptActionType {
  viewMyNotes,
  openObsidian,
  selectSpecialization,
  changeSpecialization,
  clearSpecialization,
}

class AskFptSectionItem {
  final String label;
  final String value;
  final String? detail;

  const AskFptSectionItem({
    required this.label,
    required this.value,
    this.detail,
  });

  Map<String, dynamic> toJson() => {
    'label': label,
    'value': value,
    if (detail != null) 'detail': detail,
  };

  factory AskFptSectionItem.fromJson(Map<String, dynamic> json) =>
      AskFptSectionItem(
        label: _clean(json['label']?.toString() ?? json['code']?.toString()),
        value: _clean(
          json['value']?.toString() ??
              json['name']?.toString() ??
              json['text']?.toString(),
        ),
        detail: _nullableClean(
          json['detail']?.toString() ??
              json['weight']?.toString() ??
              json['credits']?.toString(),
        ),
      );
}

class AskFptSection {
  final AskFptSectionType type;
  final String? heading;
  final List<AskFptSectionItem> items;

  const AskFptSection({
    required this.type,
    this.heading,
    this.items = const [],
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    if (heading != null) 'heading': heading,
    'items': items.map((item) => item.toJson()).toList(),
  };

  factory AskFptSection.fromJson(Map<String, dynamic> json) {
    final rawType = json['type']?.toString();
    final type = AskFptSectionType.values.where((item) {
      return item.name == rawType || _snakeCase(item.name) == rawType;
    }).firstOrNull;
    final rawItems = json['items'];
    final items = <AskFptSectionItem>[];
    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is Map) {
          items.add(AskFptSectionItem.fromJson(Map<String, dynamic>.from(raw)));
        } else {
          final text = _clean(raw?.toString());
          if (text.isNotEmpty) {
            items.add(AskFptSectionItem(label: '', value: text));
          }
        }
      }
    }
    final text = _clean(json['text']?.toString());
    if (text.isNotEmpty && items.isEmpty) {
      items.add(AskFptSectionItem(label: '', value: text));
    }
    return AskFptSection(
      type: type ?? AskFptSectionType.paragraph,
      heading: _nullableClean(json['heading']?.toString()),
      items: items,
    );
  }
}

class AskFptAction {
  final AskFptActionType type;
  final String label;
  final String value;

  const AskFptAction({
    required this.type,
    required this.label,
    required this.value,
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'label': label,
    'value': value,
  };

  factory AskFptAction.fromJson(Map<String, dynamic> json) => AskFptAction(
    type:
        AskFptActionType.values.where((item) {
          return item.name == json['type']?.toString();
        }).firstOrNull ??
        AskFptActionType.viewMyNotes,
    label: _clean(json['label']?.toString()),
    value: _clean(json['value']?.toString()),
  );
}

class AskFptContent {
  final String title;
  final String summary;
  final List<AskFptSection> sections;
  final List<AskFptAction> actions;

  const AskFptContent({
    this.title = '',
    this.summary = '',
    this.sections = const [],
    this.actions = const [],
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'summary': summary,
    'sections': sections.map((section) => section.toJson()).toList(),
    'actions': actions.map((action) => action.toJson()).toList(),
  };

  factory AskFptContent.fromJson(Map<String, dynamic> json) => AskFptContent(
    title: _clean(json['title']?.toString()),
    summary: _clean(json['summary']?.toString()),
    sections: (json['sections'] as List? ?? const [])
        .whereType<Map>()
        .map((raw) => AskFptSection.fromJson(Map<String, dynamic>.from(raw)))
        .toList(),
    actions: (json['actions'] as List? ?? const [])
        .whereType<Map>()
        .map((raw) => AskFptAction.fromJson(Map<String, dynamic>.from(raw)))
        .toList(),
  );

  factory AskFptContent.fromPlainText(String value) {
    final cleaned = _clean(value);
    final lines = cleaned
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return const AskFptContent();
    final bullets = lines
        .where((line) => line.startsWith('- ') || line.startsWith('• '))
        .map(
          (line) =>
              AskFptSectionItem(label: '', value: line.substring(2).trim()),
        )
        .toList();
    final paragraphs = lines
        .where((line) => !line.startsWith('- ') && !line.startsWith('• '))
        .toList();
    return AskFptContent(
      summary: paragraphs.isEmpty ? '' : paragraphs.first,
      sections: [
        if (paragraphs.length > 1)
          AskFptSection(
            type: AskFptSectionType.paragraph,
            items: [
              for (final paragraph in paragraphs.skip(1))
                AskFptSectionItem(label: '', value: paragraph),
            ],
          ),
        if (bullets.isNotEmpty)
          AskFptSection(type: AskFptSectionType.bulletList, items: bullets),
      ],
    );
  }

  String toPlainText() {
    final values = <String>[
      if (title.isNotEmpty) title,
      if (summary.isNotEmpty) summary,
      for (final section in sections) ...[
        ?section.heading,
        for (final item in section.items)
          [
            item.label,
            item.value,
            ?item.detail,
          ].where((part) => part.isNotEmpty).join(' — '),
      ],
    ];
    return values.join('\n').trim();
  }
}

class AskFptResponse {
  final String text;
  final AskFptResponseState state;
  final String? source;
  final Map<String, dynamic>? retrievedContext;
  final AskFptContent content;

  const AskFptResponse({
    required this.text,
    required this.state,
    this.source,
    this.retrievedContext,
    this.content = const AskFptContent(),
  });
}

class AskFptChatMessage {
  final bool user;
  final String text;
  final AskFptResponseState? state;
  final String? source;
  final AskFptContent? content;

  const AskFptChatMessage.user(this.text)
    : user = true,
      state = null,
      source = null,
      content = null;

  AskFptChatMessage.assistant(AskFptResponse response)
    : user = false,
      text = response.text,
      state = response.state,
      source = response.source,
      content = response.content;

  Map<String, dynamic> toJson() => {
    'user': user,
    'text': text,
    if (state != null) 'state': state!.name,
    if (source != null) 'source': source,
    if (content != null) 'content': content!.toJson(),
  };

  factory AskFptChatMessage.fromJson(Map<String, dynamic> json) {
    final isUser = json['user'] == true;
    final text = _clean(json['text']?.toString());
    if (isUser) return AskFptChatMessage.user(text);
    final stateName = json['state']?.toString();
    final state =
        AskFptResponseState.values.where((item) {
          return item.name == stateName;
        }).firstOrNull ??
        AskFptResponseState.answered;
    final rawContent = json['content'];
    return AskFptChatMessage.assistant(
      AskFptResponse(
        text: text,
        state: state,
        source: _nullableClean(json['source']?.toString()),
        content: rawContent is Map
            ? AskFptContent.fromJson(Map<String, dynamic>.from(rawContent))
            : AskFptContent.fromPlainText(text),
      ),
    );
  }
}

String _clean(String? value) {
  var text = value?.trim() ?? '';
  text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  text = text.replaceAll('**', '');
  text = text.replaceAll(RegExp(r'^-{3,}$', multiLine: true), '');
  text = text.replaceAll(
    RegExp(r'^\s*\|(?:\s*:?-+:?\s*\|)+\s*$', multiLine: true),
    '',
  );
  text = text.replaceAllMapped(
    RegExp(r'^\s*\|(.+)\|\s*$', multiLine: true),
    (match) =>
        match.group(1)!.split('|').map((part) => part.trim()).join(' — '),
  );
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return text.trim();
}

String? _nullableClean(String? value) {
  final text = _clean(value);
  return text.isEmpty ? null : text;
}

String _snakeCase(String value) => value.replaceAllMapped(
  RegExp(r'[A-Z]'),
  (match) => '_${match.group(0)!.toLowerCase()}',
);
