import 'package:flutter/foundation.dart';

import 'flm_session.dart';

class CurriculumSearchResult {
  final String query;
  final String matchedCode;
  final String baseCode;
  final String? intakeCode;
  final String? detectedCombo;
  final String explanation;
  final String? curriculumName;
  final bool isDirectMatch;

  const CurriculumSearchResult({
    required this.query,
    required this.matchedCode,
    required this.baseCode,
    this.intakeCode,
    this.detectedCombo,
    required this.explanation,
    this.curriculumName,
    this.isDirectMatch = false,
  });

  CurriculumMatchResult toMatchResult({List<String> candidates = const []}) {
    return CurriculumMatchResult(
      userCode: query,
      baseCode: baseCode,
      intakeCode: intakeCode,
      matchedCode: matchedCode,
      candidates: candidates,
      detectedCombo: detectedCombo,
      explanation: explanation,
    );
  }
}

class CurriculumMatchResult {
  final String userCode;
  final String baseCode;
  final String? intakeCode;
  final String matchedCode;
  final List<String> candidates;
  final String? detectedCombo;
  final String? explanation;

  const CurriculumMatchResult({
    required this.userCode,
    required this.baseCode,
    required this.intakeCode,
    required this.matchedCode,
    required this.candidates,
    this.detectedCombo,
    this.explanation,
  });
}

class CurriculumResolver {
  final FlmSession _session;

  static const List<String> defaultKnownCurricula = [
    'BIT_SE_K18D_19A',
    'BIT_SE_K17C_18A',
    'BIT_SE_K16C_17A',
    'BIT_IA_K18D_19A',
    'BIT_IA_K17C_18A',
    'BIT_GD_K18D_19A',
    'BIT_AI_K18D_19A',
    'BIT_IS_K18D_19A',
  ];

  static const Map<String, String> _programShortcuts = {
    'SE': 'BIT_SE',
    'SOFTWARE': 'BIT_SE',
    'IA': 'BIT_IA',
    'SECURITY': 'BIT_IA',
    'GD': 'BIT_GD',
    'DESIGN': 'BIT_GD',
    'AI': 'BIT_AI',
    'IS': 'BIT_IS',
    'CS': 'BIT_CS',
    'IT': 'BIT_IT',
  };

  static const Set<String> _knownCombos = {
    'JAVA',
    'NET',
    'DOTNET',
    '.NET',
    'AI',
    'NODEJS',
    'NODE',
    'REACT',
    'FLUTTER',
    'PYTHON',
    'SECURITY',
    'CLOUD',
    'DEVOPS',
    'JS',
  };

  CurriculumResolver({
    FlmSession? session,
  }) : _session = session ?? FlmSession.instance;

  /// Tìm kiếm danh sách các khung chương trình phù hợp với từ khóa của người dùng.
  /// Hỗ trợ tìm theo:
  /// - Mã đầy đủ: BIT_SE_K18D_19A
  /// - Mã sinh viên thường gọi: BIT_SE_JAVA_18D, BIT_SE_DOTNET_19A
  /// - Mã ngành viết tắt: SE, IA, BIT_SE, BIT_IA
  /// - Khóa học: 18D, K18D, 19A, K19
  /// - Chuyên ngành combo: Java, .NET
  /// - Từ khóa chung hoặc rỗng (lấy toàn bộ)
  Future<List<CurriculumSearchResult>> search(String input) async {
    final query = input.trim().toUpperCase();

    // 1. Phân tích truy vấn
    final parsed = _parseQuery(query);

    // 2. Tìm kiếm trên FLM
    List<String> flmCandidates = [];
    try {
      final searchTerm = parsed.baseCode.isNotEmpty ? parsed.baseCode : (query.isNotEmpty ? query : 'BIT');
      await _session.searchCurriculum(searchTerm);
      flmCandidates = await _session.getCurriculumCodes();
    } catch (e) {
      debugPrint('FLM search error or offline: $e');
    }

    // Kết hợp với danh sách khung mặc định nếu FLM chưa trả về dữ liệu
    final Set<String> candidatePool = {
      ...flmCandidates,
      if (flmCandidates.isEmpty) ...defaultKnownCurricula,
    };

    if (candidatePool.isEmpty) {
      return [];
    }

    // 3. Chấm điểm và lọc kết quả
    final results = <CurriculumSearchResult>[];

    for (final candidate in candidatePool) {
      final matchInfo = _evaluateCandidate(
        candidate: candidate,
        query: query,
        parsed: parsed,
      );

      if (matchInfo != null) {
        results.add(matchInfo);
      }
    }

    // 4. Sắp xếp kết quả theo độ khớp ưu tiên
    results.sort((a, b) {
      if (a.isDirectMatch && !b.isDirectMatch) return -1;
      if (!a.isDirectMatch && b.isDirectMatch) return 1;

      // Ưu tiên khớp cả ngành và khóa
      final aHasBoth = a.intakeCode != null && a.baseCode.isNotEmpty;
      final bHasBoth = b.intakeCode != null && b.baseCode.isNotEmpty;
      if (aHasBoth && !bHasBoth) return -1;
      if (!aHasBoth && bHasBoth) return 1;

      return a.matchedCode.compareTo(b.matchedCode);
    });

    return results;
  }

  /// Tương thích ngược: resolve trả về 1 kết quả tối ưu nhất
  Future<CurriculumMatchResult?> resolve(String input) async {
    final query = input.trim().toUpperCase();
    if (query.isEmpty) {
      throw ArgumentError('Curriculum code cannot be empty.');
    }

    final results = await search(query);
    if (results.isEmpty) {
      return null;
    }

    final best = results.first;
    return best.toMatchResult(
      candidates: results.map((r) => r.matchedCode).toList(),
    );
  }

  _ParsedQuery _parseQuery(String rawQuery) {
    if (rawQuery.isEmpty) {
      return const _ParsedQuery(
        raw: '',
        baseCode: '',
        intakeCode: null,
        detectedCombo: null,
      );
    }

    // Chuẩn hóa token: tách theo cả gạch dưới, gạch ngang, dấu cách
    final cleaned = rawQuery
        .replaceAll('-', '_')
        .replaceAll(',', '_')
        .replaceAll(RegExp(r'\s+'), '_');

    final parts = cleaned
        .split('_')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    String baseCode = '';
    String? intakeCode;
    String? detectedCombo;

    // Tìm combo chuyên ngành
    for (final part in parts) {
      final normalizedPart = part.replaceAll('.', '');
      if (_knownCombos.contains(normalizedPart) || _knownCombos.contains(part)) {
        detectedCombo = part;
        break;
      }
    }

    // Tìm khóa học (intake)
    for (final part in parts.reversed) {
      if (_isCohortToken(part)) {
        intakeCode = _normalizeCohortToken(part);
        break;
      }
    }

    // Tìm baseCode ngành học
    if (parts.length >= 2 && parts[0] == 'BIT') {
      baseCode = 'BIT_${parts[1]}';
    } else if (parts.isNotEmpty) {
      final first = parts[0];
      if (first.startsWith('BIT_')) {
        final subParts = first.split('_');
        baseCode = subParts.length >= 2 ? '${subParts[0]}_${subParts[1]}' : first;
      } else if (_programShortcuts.containsKey(first)) {
        baseCode = _programShortcuts[first]!;
      }
    }

    // Nếu người dùng chỉ gõ combo (vd: Java, .NET) mà chưa có baseCode, liên kết với ngành BIT_SE
    if (baseCode.isEmpty && detectedCombo != null) {
      baseCode = 'BIT_SE';
    }

    return _ParsedQuery(
      raw: rawQuery,
      baseCode: baseCode,
      intakeCode: intakeCode,
      detectedCombo: detectedCombo,
    );
  }

  CurriculumSearchResult? _evaluateCandidate({
    required String candidate,
    required String query,
    required _ParsedQuery parsed,
  }) {
    final normCandidate = _normalizeCode(candidate);
    final normQuery = _normalizeCode(query);

    // 1. Trùng khớp 100% mã khung
    if (normCandidate == normQuery) {
      return CurriculumSearchResult(
        query: query,
        matchedCode: candidate,
        baseCode: parsed.baseCode.isNotEmpty ? parsed.baseCode : _extractBaseCode(candidate),
        intakeCode: parsed.intakeCode,
        detectedCombo: parsed.detectedCombo,
        explanation: 'Khớp chính xác 100% mã khung chương trình.',
        isDirectMatch: true,
      );
    }

    // Tách candidate tokens
    final candidateBase = _extractBaseCode(candidate);
    final candidateTokens = _extractCandidateCohortTokens(candidate);

    final bool baseMatches = parsed.baseCode.isEmpty ||
        candidateBase == parsed.baseCode ||
        candidate.toUpperCase().contains(parsed.baseCode);

    final bool cohortMatches = parsed.intakeCode == null ||
        candidateTokens.contains(parsed.intakeCode) ||
        candidateTokens.any((t) => t.contains(parsed.intakeCode!) || parsed.intakeCode!.contains(t));

    // Nếu người dùng nhập chuỗi rỗng: match tất cả
    if (query.isEmpty) {
      return CurriculumSearchResult(
        query: query,
        matchedCode: candidate,
        baseCode: candidateBase,
        intakeCode: candidateTokens.isNotEmpty ? candidateTokens.first : null,
        detectedCombo: null,
        explanation: 'Khung chương trình chính thức trên hệ thống FLM.',
        isDirectMatch: false,
      );
    }

    // Nếu khớp cả ngành và khóa hoặc có combo chuyên ngành
    if (baseMatches && cohortMatches && (parsed.baseCode.isNotEmpty || parsed.intakeCode != null || parsed.detectedCombo != null)) {
      String explanation;
      if (parsed.detectedCombo != null) {
        explanation = 'Khung chuẩn trên FLM là $candidate (áp dụng cho khóa ${parsed.intakeCode ?? 'liên quan'}). Chuyên ngành nhận diện: ${parsed.detectedCombo}.';
      } else if (parsed.intakeCode != null) {
        explanation = 'Khớp khóa học ${parsed.intakeCode} trong khung đào tạo chính thức $candidate.';
      } else {
        explanation = 'Khung chương trình thuộc ngành $candidateBase.';
      }

      return CurriculumSearchResult(
        query: query,
        matchedCode: candidate,
        baseCode: candidateBase,
        intakeCode: parsed.intakeCode ?? (candidateTokens.isNotEmpty ? candidateTokens.first : null),
        detectedCombo: parsed.detectedCombo,
        explanation: explanation,
        isDirectMatch: true,
      );
    }

    // Kiểm tra tìm kiếm mờ (Query nằm trong Candidate)
    if (normCandidate.contains(normQuery) ||
        candidateTokens.any((token) => normQuery.contains(token)) ||
        normQuery.contains(candidateBase)) {
      return CurriculumSearchResult(
        query: query,
        matchedCode: candidate,
        baseCode: candidateBase,
        intakeCode: candidateTokens.isNotEmpty ? candidateTokens.first : null,
        detectedCombo: parsed.detectedCombo,
        explanation: 'Khung chương trình tương thích với từ khóa tìm kiếm.',
        isDirectMatch: false,
      );
    }

    return null;
  }

  String _extractBaseCode(String curriculumCode) {
    final parts = curriculumCode.toUpperCase().split('_');
    if (parts.length >= 2) {
      return '${parts[0]}_${parts[1]}';
    }
    return parts.first;
  }

  List<String> _extractCandidateCohortTokens(String curriculumCode) {
    final normalized = curriculumCode
        .toUpperCase()
        .replaceAll(',', '_')
        .replaceAll('-', '_');

    final parts = normalized
        .split('_')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty);

    final tokens = <String>[];
    for (final part in parts) {
      if (_isCohortToken(part)) {
        tokens.add(_normalizeCohortToken(part));
      }
    }
    return tokens;
  }

  bool _isCohortToken(String value) {
    final token = value.trim().toUpperCase();
    return RegExp(r'^K?\d{2}[A-Z]?$').hasMatch(token);
  }

  String _normalizeCohortToken(String value) {
    var token = value.trim().toUpperCase();
    if (token.startsWith('K')) {
      token = token.substring(1);
    }
    return token;
  }

  String _normalizeCode(String value) {
    return value
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[\s_\-,.]+'), '');
  }
}

class _ParsedQuery {
  final String raw;
  final String baseCode;
  final String? intakeCode;
  final String? detectedCombo;

  const _ParsedQuery({
    required this.raw,
    required this.baseCode,
    this.intakeCode,
    this.detectedCombo,
  });
}