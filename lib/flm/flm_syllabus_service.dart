import 'dart:async';
import 'dart:convert';

import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import 'flm_session.dart';

class SyllabusMaterial {
  final String description;
  final String author;
  final String publisher;
  final String publishedDate;
  final String edition;
  final String isbn;
  final bool isMain;
  final bool isOnline;
  final String note;

  const SyllabusMaterial({
    required this.description,
    required this.author,
    required this.publisher,
    required this.publishedDate,
    required this.edition,
    required this.isbn,
    required this.isMain,
    required this.isOnline,
    required this.note,
  });

  factory SyllabusMaterial.fromJson(Map<String, dynamic> json) {
    bool parseBool(dynamic value) {
      return value?.toString().trim().toLowerCase() == 'true';
    }

    return SyllabusMaterial(
      description: json['description']?.toString().trim() ?? '',
      author: json['author']?.toString().trim() ?? '',
      publisher: json['publisher']?.toString().trim() ?? '',
      publishedDate: json['publishedDate']?.toString().trim() ?? '',
      edition: json['edition']?.toString().trim() ?? '',
      isbn: json['isbn']?.toString().trim() ?? '',
      isMain: parseBool(json['isMain']),
      isOnline: parseBool(json['isOnline']),
      note: json['note']?.toString().trim() ?? '',
    );
  }
}

class SyllabusLearningOutcome {
  final String name;
  final String details;

  const SyllabusLearningOutcome({required this.name, required this.details});

  factory SyllabusLearningOutcome.fromJson(Map<String, dynamic> json) {
    return SyllabusLearningOutcome(
      name: json['name']?.toString().trim() ?? '',
      details: json['details']?.toString().trim() ?? '',
    );
  }
}

class SyllabusAssessment {
  final String category;
  final String type;
  final String part;
  final String weight;
  final String completionCriteria;
  final String duration;
  final String clo;
  final String questionType;
  final String numberOfQuestions;
  final String knowledgeAndSkill;
  final String gradingGuide;
  final String note;

  const SyllabusAssessment({
    required this.category,
    required this.type,
    required this.part,
    required this.weight,
    required this.completionCriteria,
    required this.duration,
    required this.clo,
    required this.questionType,
    required this.numberOfQuestions,
    required this.knowledgeAndSkill,
    required this.gradingGuide,
    required this.note,
  });

  factory SyllabusAssessment.fromJson(Map<String, dynamic> json) {
    return SyllabusAssessment(
      category: json['category']?.toString().trim() ?? '',
      type: json['type']?.toString().trim() ?? '',
      part: json['part']?.toString().trim() ?? '',
      weight: json['weight']?.toString().trim() ?? '',
      completionCriteria: json['completionCriteria']?.toString().trim() ?? '',
      duration: json['duration']?.toString().trim() ?? '',
      clo: json['clo']?.toString().trim() ?? '',
      questionType: json['questionType']?.toString().trim() ?? '',
      numberOfQuestions: json['numberOfQuestions']?.toString().trim() ?? '',
      knowledgeAndSkill: json['knowledgeAndSkill']?.toString().trim() ?? '',
      gradingGuide: json['gradingGuide']?.toString().trim() ?? '',
      note: json['note']?.toString().trim() ?? '',
    );
  }
}

class SyllabusDetailResult {
  final String subjectCode;
  final String url;

  final String syllabusName;
  final String courseNameEnglish;

  final int? credits;
  final double? minimumPassMark;

  final String teachingMethod;
  final String timeAllocation;
  final String prerequisite;
  final String description;
  final String studentTasks;
  final String tools;

  final List<SyllabusMaterial> materials;
  final List<SyllabusLearningOutcome> outcomes;
  final List<SyllabusAssessment> assessments;

  const SyllabusDetailResult({
    required this.subjectCode,
    required this.url,
    required this.syllabusName,
    required this.courseNameEnglish,
    required this.credits,
    required this.minimumPassMark,
    required this.teachingMethod,
    required this.timeAllocation,
    required this.prerequisite,
    required this.description,
    required this.studentTasks,
    required this.tools,
    required this.materials,
    required this.outcomes,
    required this.assessments,
  });
}

class FlmSyllabusService {
  FlmSyllabusService({FlmSession? session})
    : _session = session ?? FlmSession.instance;

  final FlmSession _session;

  Future<SyllabusDetailResult> loadExactSyllabus(String subjectCode) async {
    final code = subjectCode.trim().toUpperCase();

    if (code.isEmpty) {
      throw ArgumentError('Subject code cannot be empty.');
    }

    await _openSyllabusSearch(code);
    await _openExactResult(code);

    return _extractSyllabus(code);
  }

  Future<void> _openSyllabusSearch(String subjectCode) async {
    final encoded = Uri.encodeQueryComponent(subjectCode);

    final url =
        'https://flm.fpt.edu.vn/gui/role/student/'
        'SyllabusManagement'
        '?searchOn=Code'
        '&keyword=$encoded';

    await _loadUrlAndWait(url);
  }

  Future<void> _openExactResult(String subjectCode) async {
    final encodedCode = jsonEncode(subjectCode);

    final script =
        '''
(() => {
  const wantedCode = $encodedCode;

  const rows = Array.from(
    document.querySelectorAll('table tr')
  );

  const row = rows.find(row => {
    const cells = Array.from(
      row.querySelectorAll('td')
    );

    return cells.some(cell =>
      (cell.innerText || '')
        .trim()
        .toUpperCase() === wantedCode
    );
  });

  if (!row) {
    throw new Error(
      'Exact syllabus not found: ' +
      wantedCode
    );
  }

  const codeCell = Array.from(
    row.querySelectorAll('td')
  ).find(cell =>
    (cell.innerText || '')
      .trim()
      .toUpperCase() === wantedCode
  );

  const target =
    (codeCell
      ? codeCell.querySelector('a')
      : null) ||
    row.querySelector('a');

  if (!target) {
    throw new Error(
      'Syllabus link not found'
    );
  }

  target.click();
})();
''';

    await _executeAndWaitForNavigation(script);
  }

  Future<SyllabusDetailResult> _extractSyllabus(String subjectCode) async {
    final result = await _session.controller.executeScript('''
(() => {
  const clean = value =>
    (value || '')
      .replace(/\\r/g, '')
      .trim();

  const normalize = value =>
    clean(value)
      .replace(/:\$/, '')
      .toLowerCase();

  const tables = Array.from(
    document.querySelectorAll('table')
  );

  const field = label => {
    const wanted = normalize(label);

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

      const first =
        normalize(
          cells[0].innerText
        );

      if (first === wanted) {
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

  const findTable =
    requiredWords =>
      tables.find(table => {
        const text =
          normalize(
            table.innerText
          );

        return requiredWords.every(
          word =>
            text.includes(
              word.toLowerCase()
            )
        );
      });

  const materials = [];

  const materialTable =
    findTable([
      'material description',
      'author',
      'publisher',
      'is main material'
    ]);

  if (materialTable) {
    const rows = Array.from(
      materialTable.querySelectorAll('tr')
    );

    for (const row of rows.slice(1)) {
      const cells = Array.from(
        row.querySelectorAll('td')
      ).map(cell =>
        clean(cell.innerText)
      );

      if (cells.length < 2) {
        continue;
      }

      materials.push({
        description:
          cells[1] || '',
        author:
          cells[2] || '',
        publisher:
          cells[3] || '',
        publishedDate:
          cells[4] || '',
        edition:
          cells[5] || '',
        isbn:
          cells[6] || '',
        isMain:
          cells[7] || '',
        isOnline:
          cells[9] || '',
        note:
          cells[10] || ''
      });
    }
  }

  const outcomes = [];

  const outcomeTable =
    findTable([
      'clo name',
      'clo details'
    ]);

  if (outcomeTable) {
    const rows = Array.from(
      outcomeTable.querySelectorAll('tr')
    );

    for (const row of rows.slice(1)) {
      const cells = Array.from(
        row.querySelectorAll('td')
      ).map(cell =>
        clean(cell.innerText)
      );

      if (cells.length < 3) {
        continue;
      }

      outcomes.push({
        name:
          cells[1] || '',
        details:
          cells[2] || ''
      });
    }
  }

  const assessments = [];

  const assessmentTable =
    findTable([
      'category',
      'weight',
      'completion criteria',
      'grading guide'
    ]);

  if (assessmentTable) {
    const rows = Array.from(
      assessmentTable.querySelectorAll('tr')
    );

    for (const row of rows.slice(1)) {
      const cells = Array.from(
        row.querySelectorAll('td')
      ).map(cell =>
        clean(cell.innerText)
      );

      if (cells.length < 5) {
        continue;
      }

      assessments.push({
        category:
          cells[1] || '',
        type:
          cells[2] || '',
        part:
          cells[3] || '',
        weight:
          cells[4] || '',
        completionCriteria:
          cells[5] || '',
        duration:
          cells[6] || '',
        clo:
          cells[7] || '',
        questionType:
          cells[8] || '',
        numberOfQuestions:
          cells[9] || '',
        knowledgeAndSkill:
          cells[10] || '',
        gradingGuide:
          cells[11] || '',
        note:
          cells[12] || ''
      });
    }
  }

  return JSON.stringify({
    url:
      window.location.href,

    syllabusName:
      field('Syllabus Name'),

    courseNameEnglish:
      field('Course Name English'),

    credits:
      field('NoCredit'),

    teachingMethod:
      field('Learning-Teaching Method'),

    timeAllocation:
      field('Time Allocation'),

    prerequisite:
      field('Pre-Requisite'),

    description:
      field('Description'),

    studentTasks:
      field('StudentTasks'),

    tools:
      field('Tools'),

    minimumPassMark:
      field('MinAvgMarkToPass'),

    materials,
    outcomes,
    assessments
  });
})();
''');

    final data = _decodeMap(result);

    final materials = <SyllabusMaterial>[];

    final rawMaterials = data['materials'];

    if (rawMaterials is List) {
      for (final item in rawMaterials) {
        if (item is Map) {
          materials.add(
            SyllabusMaterial.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    final outcomes = <SyllabusLearningOutcome>[];

    final rawOutcomes = data['outcomes'];

    if (rawOutcomes is List) {
      for (final item in rawOutcomes) {
        if (item is Map) {
          outcomes.add(
            SyllabusLearningOutcome.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    final assessments = <SyllabusAssessment>[];

    final rawAssessments = data['assessments'];

    if (rawAssessments is List) {
      for (final item in rawAssessments) {
        if (item is Map) {
          assessments.add(
            SyllabusAssessment.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    return SyllabusDetailResult(
      subjectCode: subjectCode,

      url: data['url']?.toString() ?? '',

      syllabusName: data['syllabusName']?.toString() ?? '',

      courseNameEnglish: data['courseNameEnglish']?.toString() ?? '',

      credits: int.tryParse(data['credits']?.toString().trim() ?? ''),

      minimumPassMark: double.tryParse(
        data['minimumPassMark']?.toString().trim() ?? '',
      ),

      teachingMethod: data['teachingMethod']?.toString() ?? '',

      timeAllocation: data['timeAllocation']?.toString() ?? '',

      prerequisite: data['prerequisite']?.toString() ?? '',

      description: data['description']?.toString() ?? '',

      studentTasks: data['studentTasks']?.toString() ?? '',

      tools: data['tools']?.toString() ?? '',

      materials: materials,

      outcomes: outcomes,

      assessments: assessments,
    );
  }

  Map<String, dynamic> _decodeMap(Object? result) {
    if (result == null) {
      return {};
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

    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }

    return {};
  }

  Future<void> _loadUrlAndWait(String url) async {
    final completer = Completer<void>();

    late final StreamSubscription<LoadingState> subscription;

    subscription = _session.controller.loadingState.listen((state) {
      if (state == LoadingState.navigationCompleted && !completer.isCompleted) {
        completer.complete();
      }
    });

    try {
      await _session.controller.loadUrl(url);

      await completer.future.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      await Future<void>.delayed(const Duration(milliseconds: 800));
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> _executeAndWaitForNavigation(String script) async {
    final completer = Completer<void>();

    late final StreamSubscription<LoadingState> subscription;

    subscription = _session.controller.loadingState.listen((state) {
      if (state == LoadingState.navigationCompleted && !completer.isCompleted) {
        completer.complete();
      }
    });

    try {
      await _session.controller.executeScript(script);

      await completer.future.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      await Future<void>.delayed(const Duration(milliseconds: 800));
    } finally {
      await subscription.cancel();
    }
  }
}
