import '../core/ids.dart';
import '../models/chat_message.dart';
import '../models/chat_usage.dart';
import '../models/conversation.dart';
import 'chat_repository.dart';

/// 서버(Edge Function) 연결 전에 쓰는 데모 저장소.
///
/// 대화는 메모리에만 있어서 새로고침하면 사라진다. AI를 호출하지 않고
/// 정해진 안내 문구를 조각 단위로 흘려보내 스트리밍 화면을 확인할 수 있게 한다.
class LocalChatRepository implements ChatRepository {
  LocalChatRepository({this.chunkDelay = const Duration(milliseconds: 30)});

  /// 답변 조각 사이 간격 (테스트에서는 0으로 줄 수 있다)
  final Duration chunkDelay;

  final List<Conversation> _conversations = [];
  final Map<String, List<ChatMessage>> _messages = {};

  @override
  bool get isDemo => true;

  @override
  bool get savesConversations => false;

  @override
  Future<ChatUsage?> fetchUsage() async => null;

  @override
  Future<List<Conversation>> fetchConversations() async {
    final sorted = [..._conversations]
      ..sort((a, b) => b.sortTime.compareTo(a.sortTime));
    return sorted;
  }

  @override
  Future<Conversation> createConversation({String? title}) async {
    final conversation = Conversation(
      id: newUuid(),
      title: title,
      createdAt: DateTime.now(),
    );
    _conversations.add(conversation);
    _messages[conversation.id] = [];
    return conversation;
  }

  @override
  Future<void> deleteConversation(String id) async {
    _conversations.removeWhere((c) => c.id == id);
    _messages.remove(id);
  }

  @override
  Future<List<ChatMessage>> fetchMessages(String conversationId) async =>
      List.of(_messages[conversationId] ?? const []);

  @override
  Stream<ChatReplyEvent> sendMessage({
    required String conversationId,
    required String text,
  }) async* {
    final messages = _messages[conversationId];
    if (messages == null) {
      yield ChatReplyFailed(StateError('대화를 찾을 수 없습니다.'));
      return;
    }

    final userMessage = ChatMessage(
      id: newUuid(),
      conversationId: conversationId,
      role: ChatRole.user,
      content: text,
      createdAt: DateTime.now(),
    );
    messages.add(userMessage);

    final reply = demoReplyFor(text);
    for (final chunk in _chunks(reply)) {
      if (chunkDelay > Duration.zero) await Future<void>.delayed(chunkDelay);
      yield ChatReplyDelta(chunk);
    }

    final assistantMessage = ChatMessage(
      id: newUuid(),
      conversationId: conversationId,
      role: ChatRole.assistant,
      content: reply,
      createdAt: DateTime.now(),
    );
    messages.add(assistantMessage);
    _touch(conversationId, assistantMessage.createdAt);

    yield ChatReplyDone(
      userMessage: userMessage,
      assistantMessage: assistantMessage,
    );
  }

  /// 데모 답변 문구
  static String demoReplyFor(String text) =>
      '아직 AI 서버가 연결되지 않아 데모 답변을 보여 드려요.\n'
      '보내신 메시지: "${text.trim()}"';

  void _touch(String conversationId, DateTime at) {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index != -1) {
      _conversations[index] = _conversations[index].copyWith(lastMessageAt: at);
    }
  }

  /// 몇 글자씩 나눠 스트리밍처럼 보이게 한다.
  static Iterable<String> _chunks(String text, {int size = 4}) sync* {
    for (var i = 0; i < text.length; i += size) {
      yield text.substring(i, i + size > text.length ? text.length : i + size);
    }
  }
}
