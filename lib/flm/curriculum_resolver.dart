import 'package:flutter/foundation.dart';

import 'flm_session.dart';

class CurriculumMatchResult {
  final String userCode;
  final String baseCode;
  final String? intakeCode;
  final String matchedCode;
  final List<String> candidates;

  const CurriculumMatchResult({
    required this.userCode,
    required this.baseCode,
    required this.intakeCode,
    required this.matchedCode,
    required this.candidates,
  });
}

class CurriculumResolver {
  final FlmSession _session;

  CurriculumResolver({FlmSession? session})
    : _session = session ?? FlmSession.instance;

  Future<CurriculumMatchResult?> resolve(String input) async {
    final userCode = input.trim().toUpperCase();

    if (userCode.isEmpty) {
      throw ArgumentError('Curriculum code cannot be empty.');
    }

    final parts = userCode
        .split('_')
        .where((part) => part.trim().isNotEmpty)
        .map((part) => part.trim().toUpperCase())
        .toList();

    if (parts.length < 2) {
      throw FormatException('Invalid curriculum code: $userCode');
    }

    // Example:
    //
    // BIT_SE_JAVA_19A
    // BIT_SE_JAVA_18D
    //
    // Both search FLM using:
    //
    // BIT_SE
    final baseCode = '${parts[0]}_${parts[1]}';

    // Find the user's cohort / intake token.
    //
    // Supported:
    //
    // 19A
    // 18D
    // K18D
    // K20A
    String? intakeCode;

    for (final part in parts.reversed) {
      if (_isCohortToken(part)) {
        intakeCode = _normalizeCohortToken(part);

        break;
      }
    }

    debugPrint('Resolver base code: $baseCode');

    debugPrint('Resolver cohort code: $intakeCode');

    // Search FLM by curriculum CODE only.
    await _session.searchCurriculum(baseCode);

    final candidates = await _session.getCurriculumCodes();

    debugPrint('FLM candidates: $candidates');

    if (candidates.isEmpty) {
      return null;
    }

    // --------------------------------------------------
    // 1. Exact curriculum code match wins immediately.
    // --------------------------------------------------

    for (final candidate in candidates) {
      if (_normalizeCode(candidate) == _normalizeCode(userCode)) {
        return CurriculumMatchResult(
          userCode: userCode,
          baseCode: baseCode,
          intakeCode: intakeCode,
          matchedCode: candidate,
          candidates: candidates,
        );
      }
    }

    // --------------------------------------------------
    // 2. Match using cohort tokens.
    //
    // Examples:
    //
    // User:
    // BIT_SE_JAVA_19A
    //
    // Candidate:
    // BIT_SE_K18D_19A
    //
    // MATCH because 19A exists.
    //
    //
    // User:
    // BIT_SE_JAVA_18D
    //
    // Candidate:
    // BIT_SE_K18D_19A
    //
    // MATCH because:
    //
    // 18D == K18D
    // --------------------------------------------------

    if (intakeCode != null) {
      final matches = candidates.where((candidate) {
        if (!_candidateMatchesBase(candidate, baseCode)) {
          return false;
        }

        final candidateTokens = _extractCandidateCohortTokens(candidate);

        return candidateTokens.contains(intakeCode);
      }).toList();

      debugPrint(
        'Cohort matches for $intakeCode: '
        '$matches',
      );

      if (matches.length == 1) {
        return CurriculumMatchResult(
          userCode: userCode,
          baseCode: baseCode,
          intakeCode: intakeCode,
          matchedCode: matches.first,
          candidates: candidates,
        );
      }

      // Never silently guess when more than one
      // curriculum matches the same cohort token.
      if (matches.length > 1) {
        debugPrint(
          'Ambiguous curriculum matches: '
          '$matches',
        );

        return null;
      }
    }

    return null;
  }

  bool _candidateMatchesBase(String candidate, String baseCode) {
    final normalizedCandidate = _normalizeCode(candidate);

    final normalizedBase = _normalizeCode(baseCode);

    return normalizedCandidate.startsWith(normalizedBase);
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

    // Matches:
    //
    // 18D
    // 19A
    // K18D
    // K19A
    return RegExp(r'^K?\d{2}[A-Z]$').hasMatch(token);
  }

  String _normalizeCohortToken(String value) {
    var token = value.trim().toUpperCase();

    // K18D -> 18D
    // K20A -> 20A
    //
    // 18D stays 18D
    // 19A stays 19A
    if (token.startsWith('K')) {
      token = token.substring(1);
    }

    return token;
  }

  String _normalizeCode(String value) {
    return value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  }
}
