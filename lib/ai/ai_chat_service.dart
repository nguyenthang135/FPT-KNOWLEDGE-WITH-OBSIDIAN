import 'ai_chat_request.dart';
import 'ai_chat_response.dart';

abstract class AiChatService {
  Future<AiChatResponse> ask(AiChatRequest request);
}

class AiChatException implements Exception {
  final String message;

  const AiChatException(this.message);

  @override
  String toString() => message;
}
