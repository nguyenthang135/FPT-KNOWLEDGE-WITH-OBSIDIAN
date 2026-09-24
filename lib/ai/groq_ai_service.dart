import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

enum GroqFailureKind {
  unavailable,
  unauthorized,
  socket,
  tls,
  unknown,
  rateLimited,
  timeout,
  server,
  invalidResponse,
}

enum GroqRequestStatus {
  idle,
  success,
  missingKey,
  timeout,
  unauthorized,
  rateLimited,
  socketError,
  tlsError,
  http5xx,
  httpError,
  parseError,
  unknownError,
}

class GroqDiagnostics {
  final bool keyDetected;
  final String model;
  final String endpointHost;
  final GroqRequestStatus lastStatus;
  final String? lastError;

  const GroqDiagnostics({
    required this.keyDetected,
    required this.model,
    required this.endpointHost,
    required this.lastStatus,
    required this.lastError,
  });
}

class GroqAnswer {
  final String? text;
  final Map<String, dynamic>? structured;
  final GroqFailureKind? failure;

  const GroqAnswer.success(this.text, {this.structured}) : failure = null;
  const GroqAnswer.failure(this.failure) : text = null, structured = null;

  bool get isSuccess => text != null;
}

class GroqHttpResponse {
  final int statusCode;
  final String body;

  const GroqHttpResponse(this.statusCode, this.body);
}

typedef GroqTransport =
    Future<GroqHttpResponse> Function(
      Uri uri,
      Map<String, String> headers,
      String body,
    );

class GroqAiService {
  static const defaultModel = 'openai/gpt-oss-20b';
  static const _defaultEndpoint =
      'https://api.groq.com/openai/v1/chat/completions';

  final String? apiKey;
  final String model;
  final String _endpoint;
  final GroqTransport _transport;
  final Duration timeout;
  GroqRequestStatus _lastStatus = GroqRequestStatus.idle;
  String? _lastError;

  GroqAiService({
    String? apiKey,
    String? model,
    @visibleForTesting String? endpoint,
    GroqTransport? transport,
    this.timeout = const Duration(seconds: 20),
  }) : apiKey = apiKey ?? Platform.environment['GROQ_API_KEY'],
       model = (model ?? Platform.environment['GROQ_MODEL'] ?? defaultModel)
           .trim(),
       _endpoint = endpoint ?? _defaultEndpoint,
       _transport = transport ?? _defaultTransport;

  bool get configured => apiKey?.trim().isNotEmpty == true;

  GroqDiagnostics get diagnostics => GroqDiagnostics(
    keyDetected: configured,
    model: model.isEmpty ? defaultModel : model,
    endpointHost: Uri.parse(_endpoint).host,
    lastStatus: _lastStatus,
    lastError: _lastError,
  );

  Future<GroqAnswer> answer({
    required String question,
    required Map<String, dynamic> context,
    required bool english,
  }) async {
    final key = apiKey?.trim() ?? '';
    if (key.isEmpty) {
      _record(GroqRequestStatus.missingKey, 'GROQ_API_KEY is not available.');
      return const GroqAnswer.failure(GroqFailureKind.unavailable);
    }
    final requestBody = jsonEncode({
      'model': model.isEmpty ? defaultModel : model,
      'temperature': 0.1,
      'max_tokens': 700,
      'messages': [
        {
          'role': 'system',
          'content':
              'You are Ask FPT, the student guide inside FPT Knowledge. '
              'Use only the academic context supplied by the application. '
              'Never invent curriculum, assessment, prerequisite, specialization, '
              'credit, semester, material, or academic-rule information. '
              'Prefer displayName and friendly specialization names over internal '
              'curriculum or specialization codes in normal prose. '
              'If context is insufficient, say the information is unavailable in '
              'the current FPT Knowledge database. Keep answers concise and direct. '
              'Return only valid JSON with this shape: '
              '{"title":"","summary":"","sections":['
              '{"type":"paragraph|bullet_list|subject_list|key_value|assessment_list|info",'
              '"heading":"","items":[{"label":"","value":"","detail":""}]}]}.'
              ' Do not return Markdown, HTML, tables, or widget/layout code. '
              '${english ? 'Answer in English.' : 'Answer in Vietnamese.'}',
        },
        {
          'role': 'user',
          'content': jsonEncode({'question': question, 'context': context}),
        },
      ],
    });

    return _complete(requestBody);
  }

  Future<GroqAnswer> plan({
    required String question,
    required Map<String, dynamic> knownContext,
    required bool english,
  }) async {
    final key = apiKey?.trim() ?? '';
    if (key.isEmpty) {
      _record(GroqRequestStatus.missingKey, 'GROQ_API_KEY is not available.');
      return const GroqAnswer.failure(GroqFailureKind.unavailable);
    }
    final requestBody = jsonEncode({
      'model': model.isEmpty ? defaultModel : model,
      'temperature': 0,
      'max_tokens': 450,
      'messages': [
        {
          'role': 'system',
          'content':
              'You are an intent planner for Ask FPT. Understand the request, '
              'but never provide or invent academic facts. Return only one JSON '
              'object with: domain (fpt_knowledge|other), intent '
              '(subject_overview|subject_assessment|subject_prerequisite|'
              'subject_materials|subject_outcomes|subject_credits|semester_subjects|'
              'curriculum_overview|personal_curriculum_subjects|'
              'list_specializations|compare_specialization_and_core|unclear), '
              'entities {subjectCodes:[], semester:null, specialization:null}, '
              'requires {curriculum:false, semester:false, specialization:false}, '
              'clarificationNeeded, clarificationQuestion, and retrievalTargets. '
              'Retrieval targets may only be subject, curriculum, semester, '
              'specialization, assessment, or materials. Ask only for genuinely '
              'missing context. ${english ? 'Use English' : 'Use Vietnamese'} for '
              'clarificationQuestion.',
        },
        {
          'role': 'user',
          'content': jsonEncode({
            'question': question,
            'knownContext': knownContext,
          }),
        },
      ],
    });
    return _complete(requestBody, allowPlainText: false);
  }

  Future<GroqAnswer> _complete(
    String requestBody, {
    bool allowPlainText = true,
  }) async {
    final key = apiKey?.trim() ?? '';
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await _transport(Uri.parse(_endpoint), {
          HttpHeaders.authorizationHeader: 'Bearer $key',
          HttpHeaders.contentTypeHeader: 'application/json',
        }, requestBody).timeout(timeout);
        if (response.statusCode == 429) {
          if (attempt < 2) {
            await Future<void>.delayed(
              Duration(milliseconds: 350 * (attempt + 1)),
            );
            continue;
          }
          _record(GroqRequestStatus.rateLimited, 'HTTP 429');
          return const GroqAnswer.failure(GroqFailureKind.rateLimited);
        }
        if (response.statusCode == 401 || response.statusCode == 403) {
          _record(
            GroqRequestStatus.unauthorized,
            'HTTP ${response.statusCode}',
          );
          return const GroqAnswer.failure(GroqFailureKind.unauthorized);
        }
        if (response.statusCode >= 500) {
          if (attempt < 2) {
            await Future<void>.delayed(
              Duration(milliseconds: 350 * (attempt + 1)),
            );
            continue;
          }
          _record(GroqRequestStatus.http5xx, 'HTTP ${response.statusCode}');
          return const GroqAnswer.failure(GroqFailureKind.server);
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          _record(GroqRequestStatus.httpError, 'HTTP ${response.statusCode}');
          return const GroqAnswer.failure(GroqFailureKind.invalidResponse);
        }
        final decoded = jsonDecode(response.body);
        final choices = decoded is Map ? decoded['choices'] : null;
        final first = choices is List && choices.isNotEmpty
            ? choices.first
            : null;
        final content = first is Map ? first['message'] : null;
        final text = content is Map
            ? content['content']?.toString().trim()
            : null;
        if (text == null || text.isEmpty) {
          _record(
            GroqRequestStatus.parseError,
            'Response did not contain message content.',
          );
          return const GroqAnswer.failure(GroqFailureKind.invalidResponse);
        }
        final structured = _structuredJson(text);
        final safeText = structured == null
            ? _safePlainText(text, allowPlainText: allowPlainText)
            : text;
        if (structured == null && safeText == null) {
          _record(
            GroqRequestStatus.parseError,
            'Response was not safe structured or readable plain content.',
          );
          return const GroqAnswer.failure(GroqFailureKind.invalidResponse);
        }
        _record(GroqRequestStatus.success, null);
        return GroqAnswer.success(safeText ?? text, structured: structured);
      } on TimeoutException catch (error) {
        if (attempt == 2) {
          _record(GroqRequestStatus.timeout, error.message ?? 'Timed out.');
          return const GroqAnswer.failure(GroqFailureKind.timeout);
        }
      } on HandshakeException catch (error) {
        _record(GroqRequestStatus.tlsError, error.message);
        return const GroqAnswer.failure(GroqFailureKind.tls);
      } on SocketException catch (error) {
        final osCode = error.osError?.errorCode;
        _record(
          GroqRequestStatus.socketError,
          osCode == null ? error.message : '${error.message} (OS $osCode)',
        );
        return const GroqAnswer.failure(GroqFailureKind.socket);
      } on FormatException catch (error) {
        _record(GroqRequestStatus.parseError, error.message);
        return const GroqAnswer.failure(GroqFailureKind.invalidResponse);
      } catch (error, stackTrace) {
        final message = '${error.runtimeType}: ${error.toString()}';
        _record(GroqRequestStatus.unknownError, message);
        if (kDebugMode) {
          debugPrint(
            'Groq request failed: ${_sanitize(message, maxLength: null)}',
          );
          debugPrint(
            'Groq stack trace:\n'
            '${_sanitize(stackTrace.toString(), maxLength: null)}',
          );
        }
        return const GroqAnswer.failure(GroqFailureKind.unknown);
      }
    }
    _record(GroqRequestStatus.unknownError, 'Request loop ended unexpectedly.');
    return const GroqAnswer.failure(GroqFailureKind.unavailable);
  }

  void _record(GroqRequestStatus status, String? message) {
    _lastStatus = status;
    _lastError = _sanitize(message);
  }

  String? _sanitize(String? value, {int? maxLength = 180}) {
    var text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final key = apiKey?.trim() ?? '';
    if (key.isNotEmpty) text = text.replaceAll(key, '[redacted]');
    text = text.replaceAll(
      RegExp(r'Bearer\s+[^\s,;]+', caseSensitive: false),
      'Bearer [redacted]',
    );
    return maxLength != null && text.length > maxLength
        ? '${text.substring(0, maxLength)}…'
        : text;
  }

  static Future<GroqHttpResponse> _defaultTransport(
    Uri uri,
    Map<String, String> headers,
    String body,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);
      headers.forEach(request.headers.set);
      request.add(utf8.encode(body));
      final response = await request.close();
      return GroqHttpResponse(
        response.statusCode,
        await utf8.decoder.bind(response).join(),
      );
    } finally {
      client.close(force: true);
    }
  }

  static Map<String, dynamic>? _structuredJson(String value) {
    final raw = value.trim();
    final candidates = <String>[
      raw,
      raw
          .replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
          .replaceFirst(RegExp(r'\s*```$', multiLine: true), '')
          .trim(),
      raw
          .replaceFirst(
            RegExp(r'^\s*(?:json|response)\s*:\s*', caseSensitive: false),
            '',
          )
          .trim(),
      ?_balancedObject(raw),
    ];
    for (final candidate in candidates.toSet()) {
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        // Try the next safe extraction strategy.
      }
    }
    return null;
  }

  static String? _balancedObject(String value) {
    final start = value.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    var quoted = false;
    var escaped = false;
    for (var index = start; index < value.length; index++) {
      final char = value[index];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == r'\' && quoted) {
        escaped = true;
        continue;
      }
      if (char == '"') {
        quoted = !quoted;
        continue;
      }
      if (quoted) continue;
      if (char == '{') depth++;
      if (char == '}') {
        depth--;
        if (depth == 0) return value.substring(start, index + 1);
      }
    }
    return null;
  }

  static String? _safePlainText(String value, {required bool allowPlainText}) {
    if (!allowPlainText) return null;
    var text = value.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('{') ||
        text.startsWith('[') ||
        text.contains('"sections"') ||
        text.contains('"retrievalTargets"')) {
      return null;
    }
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
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return text.isEmpty ? null : text;
  }
}
