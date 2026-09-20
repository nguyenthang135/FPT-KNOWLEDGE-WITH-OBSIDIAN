import 'dart:async';
import 'dart:convert';

import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import 'flm_session.dart';

class ComboOption {
  final String name;
  final String detailUrl;

  const ComboOption({
    required this.name,
    required this.detailUrl,
  });

  factory ComboOption.fromJson(
    Map<String, dynamic> json,
  ) {
    return ComboOption(
      name: json['name']?.toString().trim() ?? '',
      detailUrl:
          json['detailUrl']?.toString().trim() ?? '',
    );
  }
}

class ComboSubject {
  final String code;
  final String name;
  final int semester;

  const ComboSubject({
    required this.code,
    required this.name,
    required this.semester,
  });

  factory ComboSubject.fromJson(
    Map<String, dynamic> json,
  ) {
    return ComboSubject(
      code: json['code']?.toString().trim() ?? '',
      name: json['name']?.toString().trim() ?? '',
      semester: int.tryParse(
            json['semester']?.toString() ?? '',
          ) ??
          0,
    );
  }
}

class SpecializationCombo {
  final String name;
  final String note;
  final String detailUrl;
  final List<ComboSubject> subjects;

  const SpecializationCombo({
    required this.name,
    required this.note,
    required this.detailUrl,
    required this.subjects,
  });
}

class FlmComboService {
  FlmComboService({
    FlmSession? session,
  }) : _session = session ?? FlmSession.instance;

  final FlmSession _session;

  Future<List<ComboOption>> loadAvailableCombos(
    String curriculumCode,
  ) async {
    // Always return to the correct curriculum first.
    await _session.searchCurriculum(
      curriculumCode,
    );

    await _session.openCurriculumByCode(
      curriculumCode,
    );

    // Find "View Combo".
    final result =
        await _session.controller.executeScript(
      '''
(() => {
  const elements = Array.from(
    document.querySelectorAll(
      'a, button, input[type="button"], input[type="submit"]'
    )
  );

  const target = elements.find(element => {
    const text =
      element.innerText ||
      element.value ||
      '';

    return text
      .trim()
      .toLowerCase() === 'view combo';
  });

  if (!target) {
    throw new Error(
      'View Combo was not found on curriculum page'
    );
  }

  const href =
    target.getAttribute
      ? target.getAttribute('href')
      : null;

  if (href) {
    return new URL(
      href,
      window.location.href
    ).href;
  }

  target.click();

  return 'CLICKED';
})();
''',
    );

    final action = _decodeJsString(result);

    if (action.startsWith('http')) {
      await _loadUrlAndWait(action);
    } else {
      await Future<void>.delayed(
        const Duration(milliseconds: 1000),
      );
    }

    // Extract combo detail links.
    final linksResult =
        await _session.controller.executeScript(
      '''
(() => {
  const anchors = Array.from(
    document.querySelectorAll('a[href]')
  );

  const found = [];
  const seen = new Set();

  for (const anchor of anchors) {
    const href =
      anchor.getAttribute('href') || '';

    if (!/\\/compo\\/detail\\//i.test(href)) {
      continue;
    }

    const url =
      new URL(
        href,
        window.location.href
      ).href;

    if (seen.has(url)) {
      continue;
    }

    seen.add(url);

    let name =
      (anchor.innerText || '')
        .trim();

    if (!name) {
      const row =
        anchor.closest('tr');

      if (row) {
        name =
          (row.innerText || '')
            .trim();
      }
    }

    found.push({
      name,
      detailUrl: url
    });
  }

  return JSON.stringify(found);
})();
''',
    );

    return _decodeOptions(linksResult);
  }

  Future<SpecializationCombo> loadCombo(
    ComboOption option,
  ) async {
    await _loadUrlAndWait(
      option.detailUrl,
    );

    final result =
        await _session.controller.executeScript(
      '''
(() => {
  const clean = value =>
    (value || '')
      .replace(/\\r/g, '')
      .trim();

  const normalize = value =>
    clean(value)
      .replace(/:\$/, '')
      .toLowerCase();

  const field = label => {
    const wanted =
      normalize(label);

    const rows = Array.from(
      document.querySelectorAll('tr')
    );

    for (const row of rows) {
      const cells = Array.from(
        row.querySelectorAll(
          'th, td'
        )
      );

      if (cells.length < 2) {
        continue;
      }

      if (
        normalize(
          cells[0].innerText
        ) === wanted
      ) {
        return clean(
          cells
            .slice(1)
            .map(cell =>
              cell.innerText
            )
            .join(' ')
        );
      }
    }

    return '';
  };

  const tables = Array.from(
    document.querySelectorAll('table')
  );

  const subjectTable =
    tables.find(table => {
      const text =
        normalize(
          table.innerText
        );

      return (
        text.includes('subject code') &&
        text.includes('subject name') &&
        text.includes('semester')
      );
    });

  const subjects = [];

  if (subjectTable) {
    const rows = Array.from(
      subjectTable.querySelectorAll('tr')
    );

    for (const row of rows.slice(1)) {
      const cells = Array.from(
        row.querySelectorAll('td')
      ).map(cell =>
        clean(cell.innerText)
      );

      // FLM combo table:
      //
      // ID | Subject Code | Subject Name |
      // Semester | Note
      if (cells.length < 4) {
        continue;
      }

      const code =
        cells[1] || '';

      const name =
        cells[2] || '';

      const semester =
        cells[3] || '';

      if (!code) {
        continue;
      }

      subjects.push({
        code,
        name,
        semester
      });
    }
  }

  return JSON.stringify({
    name:
      field('Combo Name'),

    note:
      field('Note'),

    url:
      window.location.href,

    subjects
  });
})();
''',
    );

    final data =
        _decodeMap(result);

    final subjects =
        <ComboSubject>[];

    final rawSubjects =
        data['subjects'];

    if (rawSubjects is List) {
      for (final item in rawSubjects) {
        if (item is Map) {
          subjects.add(
            ComboSubject.fromJson(
              Map<String, dynamic>.from(
                item,
              ),
            ),
          );
        }
      }
    }

    return SpecializationCombo(
      name:
          data['name']?.toString().trim().isNotEmpty ==
                  true
              ? data['name'].toString().trim()
              : option.name,
      note:
          data['note']?.toString().trim() ?? '',
      detailUrl:
          option.detailUrl,
      subjects:
          subjects,
    );
  }

  String _decodeJsString(
    Object? result,
  ) {
    if (result == null) {
      return '';
    }

    final raw =
        result.toString();

    try {
      final decoded =
          jsonDecode(raw);

      if (decoded is String) {
        return decoded;
      }
    } catch (_) {}

    return raw;
  }

  List<ComboOption> _decodeOptions(
    Object? result,
  ) {
    if (result == null) {
      return [];
    }

    dynamic decoded =
        result.toString();

    for (var i = 0; i < 2; i++) {
      if (decoded is! String) {
        break;
      }

      try {
        decoded =
            jsonDecode(decoded);
      } catch (_) {
        break;
      }
    }

    if (decoded is! List) {
      return [];
    }

    return decoded
        .whereType<Map>()
        .map(
          (item) =>
              ComboOption.fromJson(
            Map<String, dynamic>.from(
              item,
            ),
          ),
        )
        .where(
          (option) =>
              option.detailUrl.isNotEmpty,
        )
        .toList();
  }

  Map<String, dynamic> _decodeMap(
    Object? result,
  ) {
    if (result == null) {
      return {};
    }

    dynamic decoded =
        result.toString();

    for (var i = 0; i < 2; i++) {
      if (decoded is! String) {
        break;
      }

      try {
        decoded =
            jsonDecode(decoded);
      } catch (_) {
        break;
      }
    }

    if (decoded is Map) {
      return Map<String, dynamic>.from(
        decoded,
      );
    }

    return {};
  }

  Future<void> _loadUrlAndWait(
    String url,
  ) async {
    final completer =
        Completer<void>();

    late final StreamSubscription<
        LoadingState> subscription;

    subscription =
        _session.controller.loadingState.listen(
      (state) {
        if (state ==
                LoadingState.navigationCompleted &&
            !completer.isCompleted) {
          completer.complete();
        }
      },
    );

    try {
      await _session.controller.loadUrl(
        url,
      );

      await completer.future.timeout(
        const Duration(seconds: 15),
      );
    } on TimeoutException {
      await Future<void>.delayed(
        const Duration(
          milliseconds: 800,
        ),
      );
    } finally {
      await subscription.cancel();
    }
  }
}