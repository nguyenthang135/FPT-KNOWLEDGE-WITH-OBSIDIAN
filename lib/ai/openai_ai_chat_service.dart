import 'dart:convert';
import 'dart:io';

import 'ai_chat_request.dart';
import 'ai_chat_response.dart';
import 'ai_chat_service.dart';
import 'ai_prompt_builder.dart';

class OpenAiChatService implements AiChatService {
  final String apiKey;
  final String model;
  final AiPromptBuilder _promptBuilder;

  OpenAiChatService({
    required this.apiKey,
    required this.model,
    AiPromptBuilder? promptBuilder,
  }) : _promptBuilder = promptBuilder ?? const AiPromptBuilder();

  @override
  Future<AiChatResponse> ask(AiChatRequest request) async {
    if (apiKey.trim().isEmpty) {
      throw const AiChatException('Chưa cấu hình OpenAI API key.');
    }
    if (model.trim().isEmpty) {
      throw const AiChatException('Chưa cấu hình OpenAI model.');
    }

    final client = HttpClient();
    try {
      final httpRequest = await client.postUrl(
        Uri.parse('https://api.openai.com/v1/responses'),
      );
      httpRequest.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json',
      );
      httpRequest.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${apiKey.trim()}',
      );

      final payload = {
        'model': model.trim(),
        'input': _promptBuilder.buildPrompt(request),
        'max_output_tokens': 2048,
      };
      httpRequest.add(utf8.encode(jsonEncode(payload)));

      final response = await httpRequest.close();
      final rawBody = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiChatException(
          'OpenAI không thể trả lời (${response.statusCode}). '
          'Hãy kiểm tra API key, model, billing và kết nối mạng.',
        );
      }

      final decoded = jsonDecode(rawBody);
      if (decoded is! Map) {
        throw const AiChatException('OpenAI trả về dữ liệu không hợp lệ.');
      }
      final answer = _extractText(Map<String, dynamic>.from(decoded));
      if (answer.isEmpty) {
        throw const AiChatException(
          'OpenAI chưa tạo được câu trả lời từ dữ liệu hiện có.',
        );
      }

      return AiChatResponse(
        answer: answer,
        sourceLabel: request.sourceLabel,
        isDemo: false,
      );
    } on AiChatException {
      rethrow;
    } on SocketException {
      throw const AiChatException('Không có kết nối mạng để gọi OpenAI.');
    } on HandshakeException {
      throw const AiChatException(
        'Không thể tạo kết nối bảo mật tới OpenAI. '
        'Hãy kiểm tra ngày giờ Windows và kết nối mạng.',
      );
    } on HttpException {
      throw const AiChatException(
        'Kết nối tới OpenAI bị gián đoạn. Hãy thử lại sau ít phút.',
      );
    } on FormatException {
      throw const AiChatException('Không thể đọc phản hồi từ OpenAI.');
    } catch (error, stackTrace) {
      stderr.writeln(
        'OpenAI request failed (${error.runtimeType}).\n$stackTrace',
      );
      throw AiChatException(
        'Không thể gửi yêu cầu tới OpenAI (${error.runtimeType}). '
        'Hãy thử lại hoặc kiểm tra API key.',
      );
    } finally {
      client.close(force: true);
    }
  }

  String _extractText(Map<String, dynamic> response) {
    final directText = response['output_text'];
    if (directText is String && directText.trim().isNotEmpty) {
      return directText.trim();
    }

    final output = response['output'];
    if (output is! List) {
      return '';
    }

    final textParts = <String>[];
    for (final item in output.whereType<Map>()) {
      final content = item['content'];
      if (content is! List) {
        continue;
      }
      for (final part in content.whereType<Map>()) {
        if (part['type'] != 'output_text') {
          continue;
        }
        final text = part['text']?.toString().trim() ?? '';
        if (text.isNotEmpty) {
          textParts.add(text);
        }
      }
    }
    return textParts.join('\n').trim();
  }
}
