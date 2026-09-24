import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import '../models/curriculum_subject.dart';

class FlmDiscoverySnapshot {
  final String currentUrl;
  final bool loginDetected;
  final int rowsFound;
  final List<String> codes;
  final int? resultCount;

  const FlmDiscoverySnapshot({
    required this.currentUrl,
    required this.loginDetected,
    required this.rowsFound,
    required this.codes,
    required this.resultCount,
  });
}

class FlmSession {
  FlmSession._();

  static final FlmSession instance = FlmSession._();

  final WebviewController controller = WebviewController();

  bool _initialized = false;
  static bool _environmentInitialized = false;
  bool isAuthenticated = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    if (!_environmentInitialized) {
      final appData = Platform.environment['APPDATA'] ?? Directory.current.path;
      final profileDirectory = Directory(
        '$appData${Platform.pathSeparator}FPT Knowledge'
        '${Platform.pathSeparator}webview_profile',
      );
      await profileDirectory.create(recursive: true);
      await WebviewController.initializeEnvironment(
        userDataPath: profileDirectory.path,
      );
      _environmentInitialized = true;
    }

    await controller.initialize();

    _initialized = true;
  }

  Future<void> openLoginPage() async {
    await initialize();

    await _loadUrlAndWait('https://flm.fpt.edu.vn/Home');
  }

  Future<bool> checkLoginSuccess() async {
    try {
      final result = await controller.executeScript('''
document.body
  ? document.body.innerText
  : ""
''');

      final text = result?.toString().toLowerCase() ?? '';

      final loggedIn =
          text.contains("student's features") ||
          (text.contains('view curriculum') && text.contains('view syllabus'));

      if (loggedIn) {
        isAuthenticated = true;
      }

      return loggedIn;
    } catch (_) {
      return false;
    }
  }

  // --------------------------------------------------
  // LOGOUT / SWITCH ACCOUNT
  // --------------------------------------------------

  Future<void> logout() async {
    await initialize();

    // Remove authentication cookies from the current
    // temporary WebView profile.
    await controller.clearCookies();

    // Remove cached browser resources as well.
    await controller.clearCache();

    isAuthenticated = false;

    // Make sure an authenticated FLM page is no longer
    // displayed in the WebView.
    await controller.loadUrl('about:blank');

    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  // --------------------------------------------------
  // CURRICULUM SEARCH
  // --------------------------------------------------

  Future<void> openCurriculumSearch() async {
    await _loadUrlAndWait(
      'https://flm.fpt.edu.vn/gui/role/student/ListCurriculum',
    );
  }

  Future<void> searchCurriculum(String code) async {
    await openCurriculumSearch();

    final encodedCode = jsonEncode(code.trim());

    final script =
        '''
(() => {
  const selects = Array.from(
    document.querySelectorAll('select')
  );

  const searchType =
    selects.find(select =>
      Array.from(select.options).some(
        option =>
          option.text
            .trim()
            .toLowerCase() === 'code'
      )
    );

  if (!searchType) {
    throw new Error(
      'Curriculum search type dropdown not found'
    );
  }

  const codeOption =
    Array.from(searchType.options).find(
      option =>
        option.text
          .trim()
          .toLowerCase() === 'code'
    );

  if (!codeOption) {
    throw new Error(
      'Code search option not found'
    );
  }

  searchType.value =
    codeOption.value;

  searchType.dispatchEvent(
    new Event(
      'change',
      {
        bubbles: true
      }
    )
  );

  const textInputs =
    Array.from(
      document.querySelectorAll(
        'input[type="text"], input[type="search"]'
      )
    );

  const textInput =
    textInputs.find(
      input =>
        input.offsetParent !== null
    );

  if (!textInput) {
    throw new Error(
      'Curriculum code input not found'
    );
  }

  textInput.focus();

  textInput.value =
    $encodedCode;

  textInput.dispatchEvent(
    new Event(
      'input',
      {
        bubbles: true
      }
    )
  );

  textInput.dispatchEvent(
    new Event(
      'change',
      {
        bubbles: true
      }
    )
  );

  const buttons =
    Array.from(
      document.querySelectorAll(
        'button, input[type="submit"]'
      )
    );

  const searchButton =
    buttons.find(element => {
      const text =
        element.innerText ||
        element.value ||
        '';

      return text
        .trim()
        .toLowerCase() ===
        'search';
    });

  if (!searchButton) {
    throw new Error(
      'Curriculum Search button not found'
    );
  }

  searchButton.click();
})();
''';

    await _executeAndWaitForNavigation(script);
  }

  Future<FlmDiscoverySnapshot> inspectCurriculumPage() async {
    final result = await controller.executeScript(r'''
(() => {
  const clean = value => (value || '').replace(/\s+/g, ' ').trim();
  const normalized = value => clean(value).toLowerCase();
  const tables = Array.from(document.querySelectorAll('table'));
  const table = tables
    .map(element => {
      const firstRow = element.querySelector('thead tr, tr');
      const headers = Array.from(firstRow?.querySelectorAll('th, td') || [])
        .map(cell => normalized(cell.innerText));
      const headerScore = headers.reduce((value, header) => value +
        (header === 'code' || header.includes('curriculum code') ? 5 : 0) +
        (header.includes('curriculum') ? 2 : 0), 0);
      const rows = Array.from(element.querySelectorAll('tbody tr, tr'))
        .filter(row => row.querySelectorAll('td').length > 0);
      const candidateCounts = [];
      for (const row of rows) {
        Array.from(row.querySelectorAll('td')).forEach((cell, index) => {
          const value = clean(cell.innerText);
          if (/^[A-Za-z][A-Za-z0-9_-]{2,}(?:\s*,\s*[A-Za-z][A-Za-z0-9_-]{2,})*$/.test(value)) {
            candidateCounts[index] = (candidateCounts[index] || 0) + 1;
          }
        });
      }
      const inferredCodeIndex = candidateCounts.length === 0
        ? -1
        : candidateCounts.indexOf(Math.max(...candidateCounts));
      const inferredScore = inferredCodeIndex < 0
        ? 0
        : candidateCounts[inferredCodeIndex];
      return {
        element,
        headers,
        rows,
        inferredCodeIndex,
        score: headerScore * 1000 + inferredScore
      };
    })
    .sort((a, b) => b.score - a.score)[0];
  const codes = [];
  let rowsFound = 0;
  if (table && table.score > 0) {
    const headerCodeIndex = table.headers.findIndex(header =>
      header === 'code' || header.includes('curriculum code'));
    const codeIndex = headerCodeIndex >= 0
      ? headerCodeIndex
      : table.inferredCodeIndex;
    const rows = table.rows;
    rowsFound = rows.length;
    for (const row of rows) {
      const cells = Array.from(row.querySelectorAll('td'));
      const candidateCells = codeIndex >= 0 && codeIndex < cells.length
        ? [cells[codeIndex]]
        : cells;
      for (const cell of candidateCells) {
        const value = clean(cell.innerText);
        if (/^[A-Za-z][A-Za-z0-9_-]{2,}(?:\s*,\s*[A-Za-z][A-Za-z0-9_-]{2,})*$/.test(value)) {
          codes.push(value);
          break;
        }
      }
    }
  }
  const bodyText = clean(document.body ? document.body.innerText : '');
  const url = window.location.href;
  const visiblePassword = Array.from(
    document.querySelectorAll('input[type="password"]')
  ).some(input => input.offsetParent !== null);
  const authenticatedRoute = /\/gui\/role\/student\/ListCurriculum/i.test(url);
  const explicitLoginRoute = /\/(login|signin)(?:[/?#]|$)/i.test(url);
  const loginDetected = authenticatedRoute ||
    (!visiblePassword && !explicitLoginRoute && Boolean(table && table.score > 0));
  const countMatch = bodyText.match(
    /(?:total|showing\s+\d+\s+to\s+\d+\s+of)\D{0,20}(\d+)/i
  );
  return JSON.stringify({
    currentUrl: url,
    loginDetected,
    rowsFound,
    codes,
    resultCount: countMatch ? Number(countMatch[1]) : null
  });
})();
''');

    final decoded = _decodeMap(result);
    final codes = decoded['codes'] is List
        ? (decoded['codes'] as List)
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .toList()
        : <String>[];
    return FlmDiscoverySnapshot(
      currentUrl: decoded['currentUrl']?.toString() ?? await getCurrentUrl(),
      loginDetected: decoded['loginDetected'] == true,
      rowsFound: int.tryParse(decoded['rowsFound']?.toString() ?? '') ?? 0,
      codes: codes,
      resultCount: int.tryParse(decoded['resultCount']?.toString() ?? ''),
    );
  }

  Future<List<String>> getCurriculumCodes() async {
    return (await inspectCurriculumPage()).codes;
  }

  Future<List<String>> discoverCurriculumCodes({
    void Function(FlmDiscoverySnapshot value)? onDiagnostics,
  }) async {
    await openCurriculumSearch();

    final initial = await inspectCurriculumPage();
    onDiagnostics?.call(initial);
    if (!initial.loginDetected) {
      isAuthenticated = false;
      throw StateError(
        'FLM login is required for database extraction. '
        'Please log in, then retry.',
      );
    }
    final discovered = <String>{};
    Future<int> crawlCurrentResults() async {
      final pageSignatures = <String>{};
      final before = discovered.length;
      for (var page = 0; page < 500; page++) {
        final snapshot = await inspectCurriculumPage();
        if (!snapshot.loginDetected) {
          isAuthenticated = false;
          throw StateError(
            'FLM login is required for database extraction. '
            'Please log in, then retry.',
          );
        }
        isAuthenticated = true;
        for (final value in snapshot.codes) {
          for (final code in value.split(',')) {
            final normalized = code.trim().toUpperCase();
            if (normalized.isNotEmpty) discovered.add(normalized);
          }
        }
        onDiagnostics?.call(
          FlmDiscoverySnapshot(
            currentUrl: snapshot.currentUrl,
            loginDetected: true,
            rowsFound: snapshot.rowsFound,
            codes: discovered.toList(),
            resultCount: snapshot.resultCount,
          ),
        );

        final signature = '${snapshot.rowsFound}:${snapshot.codes.join('|')}';
        if (!pageSignatures.add(signature)) break;
        if (!await _clickNextCurriculumPage(signature)) break;
      }
      return discovered.length - before;
    }

    // Prove the known curriculum first. The collector also places it first in
    // the extraction order before expanding to every discovered curriculum.
    const knownTarget = 'BIT_SE_K18D_19A';
    await searchCurriculum(knownTarget);
    await crawlCurrentResults();
    if (!discovered.contains(knownTarget)) {
      throw StateError(
        'FLM did not return the required test curriculum $knownTarget. '
        'Check FLM page compatibility.',
      );
    }

    // FLM does not return a catalogue for an empty keyword. Curriculum codes
    // use "_" as their segment delimiter, so this query discovers the full
    // catalogue without hard-coding a program.
    await searchCurriculum('_');
    final broadCount = await crawlCurrentResults();

    // Compatibility fallback for an FLM deployment that treats "_" as a
    // wildcard or rejects it. Single-character partitions cover code prefixes
    // while the set removes overlaps.
    if (broadCount == 0) {
      const partitions = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      for (final query in partitions.split('')) {
        await searchCurriculum(query);
        await crawlCurrentResults();
      }
    }

    final result = discovered.toList()..sort();
    return result;
  }

  Future<bool> _clickNextCurriculumPage(String signature) async {
    final moved = await controller.executeScript('''
(() => {
  const direct = document.querySelector([
    'a[rel="next"]',
    'a[title*="next" i]',
    '.pagination li.next:not(.disabled) a',
    '.pagination li:not(.disabled) a[aria-label*="next" i]',
    '.paginate_button.next:not(.disabled)',
    '[data-dt-idx="next"]:not(.disabled)',
    '.k-pager-nav[aria-label*="next" i]:not(.k-disabled)',
    '.dx-next-button:not(.dx-state-disabled)',
    'li.PagedList-skipToNext:not(.disabled) a'
  ].join(','));
  if (direct) {
    direct.click();
    return true;
  }
  const links = Array.from(document.querySelectorAll(
    '.pagination a, .pagination button, .dataTables_paginate a, .dataTables_paginate button'
  ));
  const next = links.find(element => {
    const text = (element.innerText || element.getAttribute('aria-label') || '')
      .trim()
      .toLowerCase();
    const disabled = element.disabled ||
      element.getAttribute('aria-disabled') === 'true' ||
      element.classList.contains('disabled') ||
      element.parentElement?.classList.contains('disabled');
    return !disabled && (['next', '›', '»', '>'].includes(text) || text.includes('next'));
  });
  if (!next) return false;
  next.click();
  return true;
})()
''');

    if (!moved.toString().toLowerCase().contains('true')) return false;
    for (var wait = 0; wait < 20; wait++) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      try {
        final next = await inspectCurriculumPage();
        final nextSignature = '${next.rowsFound}:${next.codes.join('|')}';
        if (nextSignature != signature) {
          return true;
        }
      } catch (_) {
        // Full-page pagination briefly makes script execution unavailable.
      }
    }
    return false;
  }

  Future<void> openCurriculumByCode(String curriculumCode) async {
    final encodedCode = jsonEncode(curriculumCode.trim().toUpperCase());

    final script =
        '''
(() => {
  const wantedCode = $encodedCode;

  const rows = Array.from(
    document.querySelectorAll(
      'table tr'
    )
  );

  const row = rows.find(row => {
    const cells = Array.from(
      row.querySelectorAll('td')
    );

    return cells.some(cell =>
      (cell.innerText || '')
        .trim()
        .toUpperCase() ===
        wantedCode
    );
  });

  if (!row) {
    throw new Error(
      'Matched curriculum row not found: ' +
      wantedCode
    );
  }

  const exactCell =
    Array.from(
      row.querySelectorAll('td')
    ).find(cell =>
      (cell.innerText || '')
        .trim()
        .toUpperCase() ===
        wantedCode
    );

  if (!exactCell) {
    throw new Error(
      'Curriculum code cell not found'
    );
  }

  const cellLink =
    exactCell.querySelector('a');

  const rowLink =
    row.querySelector('a');

  const target =
    cellLink ||
    rowLink ||
    exactCell;

  target.click();
})();
''';

    await _executeAndWaitForNavigation(script);
  }

  // --------------------------------------------------
  // CURRICULUM SUBJECTS
  // --------------------------------------------------

  Future<List<CurriculumSubject>> getCurriculumSubjects() async {
    final result = await controller.executeScript('''
(() => {
  const tables = Array.from(
    document.querySelectorAll('table')
  );

  const subjectTable =
    tables.find(table => {
      const text =
        (table.innerText || '')
          .toLowerCase();

      return (
        text.includes('subject code') &&
        text.includes('subject name') &&
        text.includes('semester') &&
        text.includes('nocredit')
      );
    });

  if (!subjectTable) {
    throw new Error(
      'Curriculum subject table not found'
    );
  }

  const rows = Array.from(
    subjectTable.querySelectorAll('tr')
  );

  const subjects = [];

  for (const row of rows) {
    const cells = Array.from(
      row.querySelectorAll('td')
    );

    if (cells.length < 4) {
      continue;
    }

    const code =
      (cells[0].innerText || '')
        .trim();

    const name =
      (cells[1].innerText || '')
        .trim();

    const semester =
      (cells[2].innerText || '')
        .trim();

    const credits =
      (cells[3].innerText || '')
        .trim();

    const prerequisite =
      cells.length >= 5
        ? (cells[4].innerText || '')
            .trim()
        : '';

    if (!code || !name) {
      continue;
    }

    subjects.push({
      code,
      name,
      semester,
      credits,
      prerequisite
    });
  }

  return JSON.stringify(subjects);
})();
''');

    return _decodeSubjects(result);
  }

  Future<Map<String, dynamic>> getCurriculumMetadata() async {
    final result = await controller.executeScript('''
(() => {
  const clean = value => (value || '').replace(/\r/g, '').trim();
  const normalize = value => clean(value).replace(/:\$/, '').toLowerCase();
  const field = labels => {
    const wanted = labels.map(normalize);
    for (const row of Array.from(document.querySelectorAll('tr'))) {
      const cells = Array.from(row.querySelectorAll('th, td'));
      if (cells.length < 2) continue;
      if (wanted.includes(normalize(cells[0].innerText))) {
        return clean(cells.slice(1).map(cell => cell.innerText).join(' '));
      }
    }
    return '';
  };
  return JSON.stringify({
    name: field(['Curriculum Name', 'Name']),
    totalCredits: field(['Total Credits', 'Total Credit', 'NoCredit'])
  });
})()
''');

    return _decodeMap(result);
  }

  // --------------------------------------------------
  // PAGE HELPERS
  // --------------------------------------------------

  Future<String> getPageText() async {
    final result = await controller.executeScript('''
document.body
  ? document.body.innerText
  : ""
''');

    return result?.toString() ?? '';
  }

  Future<String> getCurrentUrl() async {
    final result = await controller.executeScript('window.location.href');

    if (result == null) {
      return '';
    }

    var value = result.toString();

    try {
      final decoded = jsonDecode(value);

      if (decoded is String) {
        value = decoded;
      }
    } catch (_) {}

    return value;
  }

  // --------------------------------------------------
  // JSON DECODING
  // --------------------------------------------------

  List<CurriculumSubject> _decodeSubjects(Object? result) {
    if (result == null) {
      return [];
    }

    dynamic decoded = result.toString();

    for (var i = 0; i < 2; i++) {
      if (decoded is! String) {
        break;
      }

      try {
        decoded = jsonDecode(decoded);
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
          (item) => CurriculumSubject.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Map<String, dynamic> _decodeMap(Object? result) {
    if (result == null) {
      return {};
    }

    dynamic decoded = result.toString();
    for (var i = 0; i < 2 && decoded is String; i++) {
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        break;
      }
    }

    return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
  }

  // --------------------------------------------------
  // NAVIGATION HELPERS
  // --------------------------------------------------

  Future<void> _loadUrlAndWait(String url) async {
    await initialize();

    final completer = Completer<void>();

    late final StreamSubscription<LoadingState> subscription;

    subscription = controller.loadingState.listen((state) {
      if (state == LoadingState.navigationCompleted && !completer.isCompleted) {
        completer.complete();
      }
    });

    try {
      await controller.loadUrl(url);

      await completer.future.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> _executeAndWaitForNavigation(String script) async {
    await initialize();

    final completer = Completer<void>();

    late final StreamSubscription<LoadingState> subscription;

    subscription = controller.loadingState.listen((state) {
      if (state == LoadingState.navigationCompleted && !completer.isCompleted) {
        completer.complete();
      }
    });

    try {
      await controller.executeScript(script);

      await completer.future.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      await Future<void>.delayed(const Duration(milliseconds: 800));
    } finally {
      await subscription.cancel();
    }
  }
}
