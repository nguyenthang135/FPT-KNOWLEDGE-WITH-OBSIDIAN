import 'dart:convert';
import 'dart:io';

import 'ai_chat_request.dart';
import 'ai_chat_response.dart';
import 'ai_chat_service.dart';
import 'ai_prompt_builder.dart';

class GeminiAiChatService implements AiChatService {
  final String apiKey;
  final String model;
  final AiPromptBuilder _promptBuilder;

  GeminiAiChatService({
    required this.apiKey,
    this.model = 'gemini-3.8-flash',
    AiPromptBuilder? promptBuilder,
  }) : _promptBuilder = promptBuilder ?? const AiPromptBuilder();

  @override
  Future<AiChatResponse> ask(AiChatRequest request) async {
    if (apiKey.trim().isEmpty) {
      throw const AiChatException('Chưa cấu hình Gemini API key.');
    }

    final client = HttpClient();
    try {
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/'
        '$model:generateContent',
      );
      final httpRequest = await client.postUrl(uri);
      httpRequest.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json',
      );
      httpRequest.headers.set('x-goog-api-key', apiKey.trim());

      final payload = {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': _promptBuilder.buildPrompt(request)},
            ],
          },
        ],
        'generationConfig': {'temperature': 0.25, 'maxOutputTokens': 900},
      };

      httpRequest.write(jsonEncode(payload));
      final response = await httpRequest.close();
      final rawBody = await utf8.decoder.bind(response).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiChatException(
          'Gemini không thể trả lời (${response.statusCode}). '
          'Hãy kiểm tra API key, model và kết nối mạng.',
        );
      }

      final decoded = jsonDecode(rawBody);
      if (decoded is! Map) {
        throw const AiChatException('Gemini trả về dữ liệu không hợp lệ.');
      }

      final answer = _extractText(Map<String, dynamic>.from(decoded));
      if (answer.isEmpty) {
        throw const AiChatException(
          'Gemini chưa tạo được câu trả lời từ dữ liệu hiện có.',
        );
      }

      return AiChatResponse(
        answer: answer,
        sourceLabel: request.sourceLabel,
        isDemo: false,
      );
    } on SocketException {
      throw const AiChatException('Không có kết nối mạng để gọi Gemini.');
    } on FormatException {
      throw const AiChatException('Không thể đọc phản hồi từ Gemini.');
    } finally {
      client.close(force: true);
    }
  }

  String _extractText(Map<String, dynamic> response) {
    final candidates = response['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      return '';
    }

    final first = candidates.first;
    if (first is! Map) {
      return '';
    }

    final content = first['content'];
    if (content is! Map) {
      return '';
    }

    final parts = content['parts'];
    if (parts is! List) {
      return '';
    }

    return parts
        .whereType<Map>()
        .map((part) => part['text']?.toString() ?? '')
        .where((text) => text.trim().isNotEmpty)
        .join('\n')
        .trim();
  }
}
