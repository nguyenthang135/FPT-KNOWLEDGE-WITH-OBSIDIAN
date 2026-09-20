import 'dart:async';
import 'dart:convert';

import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import '../models/curriculum_subject.dart';

class FlmSession {
  FlmSession._();

  static final FlmSession instance =
      FlmSession._();

  final WebviewController controller =
      WebviewController();

  bool _initialized = false;
  bool isAuthenticated = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    await controller.initialize();

    _initialized = true;
  }

  Future<void> openLoginPage() async {
    await initialize();

    await _loadUrlAndWait(
      'https://flm.fpt.edu.vn/Home',
    );
  }

  Future<bool> checkLoginSuccess() async {
    try {
      final result =
          await controller.executeScript(
        '''
document.body
  ? document.body.innerText
  : ""
''',
      );

      final text =
          result
                  ?.toString()
                  .toLowerCase() ??
              '';

      final loggedIn =
          text.contains(
            "student's features",
          ) ||
          (
            text.contains(
              'view curriculum',
            ) &&
            text.contains(
              'view syllabus',
            )
          );

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
    await controller.loadUrl(
      'about:blank',
    );

    await Future<void>.delayed(
      const Duration(
        milliseconds: 350,
      ),
    );
  }

  // --------------------------------------------------
  // CURRICULUM SEARCH
  // --------------------------------------------------

  Future<void> openCurriculumSearch() async {
    await _loadUrlAndWait(
      'https://flm.fpt.edu.vn/gui/role/student/ListCurriculum',
    );
  }

  Future<void> searchCurriculum(
    String code,
  ) async {
    await openCurriculumSearch();

    final encodedCode =
        jsonEncode(
      code.trim(),
    );

    final script = '''
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

    await _executeAndWaitForNavigation(
      script,
    );
  }

  Future<List<String>>
      getCurriculumCodes() async {
    final result =
        await controller.executeScript(
      '''
(() => {
  const rows = Array.from(
    document.querySelectorAll(
      'table tr'
    )
  );

  const codes = [];

  for (const row of rows) {
    const cells = Array.from(
      row.querySelectorAll('td')
    );

    if (cells.length < 2) {
      continue;
    }

    const code =
      (cells[1].innerText || '')
        .trim();

    if (
      code &&
      /^[A-Za-z0-9_-]+(?:\\s*,\\s*[A-Za-z0-9_-]+)*\$/
        .test(code)
    ) {
      codes.push(code);
    }
  }

  return JSON.stringify(codes);
})();
''',
    );

    return _decodeStringList(
      result,
    );
  }

  Future<void> openCurriculumByCode(
    String curriculumCode,
  ) async {
    final encodedCode =
        jsonEncode(
      curriculumCode
          .trim()
          .toUpperCase(),
    );

    final script = '''
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

    await _executeAndWaitForNavigation(
      script,
    );
  }

  // --------------------------------------------------
  // CURRICULUM SUBJECTS
  // --------------------------------------------------

  Future<List<CurriculumSubject>>
      getCurriculumSubjects() async {
    final result =
        await controller.executeScript(
      '''
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
''',
    );

    return _decodeSubjects(
      result,
    );
  }

  // --------------------------------------------------
  // PAGE HELPERS
  // --------------------------------------------------

  Future<String> getPageText() async {
    final result =
        await controller.executeScript(
      '''
document.body
  ? document.body.innerText
  : ""
''',
    );

    return result?.toString() ?? '';
  }

  Future<String> getCurrentUrl() async {
    final result =
        await controller.executeScript(
      'window.location.href',
    );

    if (result == null) {
      return '';
    }

    var value =
        result.toString();

    try {
      final decoded =
          jsonDecode(value);

      if (decoded is String) {
        value = decoded;
      }
    } catch (_) {}

    return value;
  }

  // --------------------------------------------------
  // JSON DECODING
  // --------------------------------------------------

  List<CurriculumSubject>
      _decodeSubjects(
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
              CurriculumSubject.fromJson(
            Map<String, dynamic>.from(
              item,
            ),
          ),
        )
        .toList();
  }

  List<String> _decodeStringList(
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
        .map(
          (item) =>
              item.toString().trim(),
        )
        .where(
          (item) =>
              item.isNotEmpty,
        )
        .toSet()
        .toList();
  }

  // --------------------------------------------------
  // NAVIGATION HELPERS
  // --------------------------------------------------

  Future<void> _loadUrlAndWait(
    String url,
  ) async {
    await initialize();

    final completer =
        Completer<void>();

    late final StreamSubscription<
        LoadingState> subscription;

    subscription =
        controller.loadingState.listen(
      (state) {
        if (state ==
                LoadingState.navigationCompleted &&
            !completer.isCompleted) {
          completer.complete();
        }
      },
    );

    try {
      await controller.loadUrl(
        url,
      );

      await completer.future.timeout(
        const Duration(
          seconds: 15,
        ),
      );
    } on TimeoutException {
      await Future<void>.delayed(
        const Duration(
          milliseconds: 500,
        ),
      );
    } finally {
      await subscription.cancel();
    }
  }

  Future<void>
      _executeAndWaitForNavigation(
    String script,
  ) async {
    await initialize();

    final completer =
        Completer<void>();

    late final StreamSubscription<
        LoadingState> subscription;

    subscription =
        controller.loadingState.listen(
      (state) {
        if (state ==
                LoadingState.navigationCompleted &&
            !completer.isCompleted) {
          completer.complete();
        }
      },
    );

    try {
      await controller.executeScript(
        script,
      );

      await completer.future.timeout(
        const Duration(
          seconds: 10,
        ),
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