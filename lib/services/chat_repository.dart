import '../models/chat_message.dart';
import '../models/chat_usage.dart';
import '../models/conversation.dart';

/// 대화방과 메시지를 다루는 저장소.
///
/// 화면은 이 인터페이스만 사용한다. 지금은 로컬 데모 구현을 쓰고,
/// Edge Function이 준비되면 같은 인터페이스의 서버 구현으로 바꾼다.
/// 실패하면 예외를 던지거나(목록·삭제), [ChatReplyFailed]를 보낸다(전송).
abstract class ChatRepository {
  /// 서버(AI) 연결 전 데모 응답이면 true. 화면에 안내 문구를 띄운다.
  bool get isDemo;

  /// 대화가 서버에 저장되어 새로고침 뒤에도 남으면 true.
  bool get savesConversations;

  /// 최근 대화가 먼저 오도록 정렬해서 돌려준다.
  Future<List<Conversation>> fetchConversations();

  Future<Conversation> createConversation({String? title});

  Future<void> deleteConversation(String id);

  /// 오래된 메시지가 먼저 오도록 정렬해서 돌려준다.
  Future<List<ChatMessage>> fetchMessages(String conversationId);

  /// 오늘의 AI 사용량(앱 집계). AI 서버를 쓰지 않는 저장소는 null.
  /// AI를 호출하지 않으므로 자주 불러도 비용이 들지 않는다.
  Future<ChatUsage?> fetchUsage();

  /// 사용자 메시지를 보내고 AI 답변을 조각 단위로 받는다.
  ///
  /// 순서: [ChatReplyDelta]·[ChatReplyRestart] 0번 이상 →
  /// [ChatReplyDone] 또는 [ChatReplyFailed] 1번.
  Stream<ChatReplyEvent> sendMessage({
    required String conversationId,
    required String text,
  });
}

sealed class ChatReplyEvent {
  const ChatReplyEvent();
}

/// 답변 글자 조각
class ChatReplyDelta extends ChatReplyEvent {
  const ChatReplyDelta(this.text);

  final String text;
}

/// 지금까지 받은 답변 글을 버리고 처음부터 다시 받는다.
/// (서버가 다른 AI 모델로 넘어가 답을 새로 쓰는 경우)
class ChatReplyRestart extends ChatReplyEvent {
  const ChatReplyRestart();
}

/// 답변 완료. 서버에 저장된 질문과 답변을 돌려준다.
class ChatReplyDone extends ChatReplyEvent {
  const ChatReplyDone({
    required this.userMessage,
    required this.assistantMessage,
  });

  final ChatMessage userMessage;
  final ChatMessage assistantMessage;
}

/// 답변 실패
class ChatReplyFailed extends ChatReplyEvent {
  const ChatReplyFailed(this.error, {this.userMessageSaved = false});

  final Object error;

  /// 질문은 저장됐고 답변만 실패했으면 true. false면 질문도 저장되지 않은 것이다.
  final bool userMessageSaved;
}

/// 채팅 서버(Edge Function)가 알려 준 오류.
///
/// [code]는 서버가 정한 짧은 오류 코드다(예: daily_limit_reached).
/// 서버 원문 메시지나 토큰은 담지 않는다.
class ChatServiceException implements Exception {
  const ChatServiceException(this.code, {this.status});

  final String code;

  /// HTTP 상태 코드. 답변 도중 실패했으면 null.
  final int? status;

  @override
  String toString() =>
      'ChatServiceException($code${status == null ? '' : ', $status'})';
}
