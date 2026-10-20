enum ChatRole {
  user,
  assistant;

  static ChatRole fromName(Object? name) =>
      name == 'assistant' ? ChatRole.assistant : ChatRole.user;
}

/// public.messages의 status와 같은 값.
enum MessageStatus {
  /// 답변을 받는 중
  streaming,
  complete,
  error;

  static MessageStatus fromName(Object? name) => values.firstWhere(
    (s) => s.name == name,
    orElse: () => MessageStatus.complete,
  );
}

/// 대화 메시지. public.messages 행 중 화면에 필요한 값만 담는다.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.status = MessageStatus.complete,
    this.errorMessage,
  });

  factory ChatMessage.fromRow(Map<String, dynamic> row) {
    return ChatMessage(
      id: row['id'] as String,
      conversationId: row['conversation_id'] as String,
      role: ChatRole.fromName(row['role']),
      content: row['content'] as String? ?? '',
      status: MessageStatus.fromName(row['status']),
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  final String id;
  final String conversationId;
  final ChatRole role;

  /// 화면에 보여 줄 텍스트
  final String content;
  final MessageStatus status;
  final DateTime createdAt;

  /// 실패했을 때 사용자에게 보여 줄 문구 (화면 전용, 서버에는 없음)
  final String? errorMessage;

  bool get isUser => role == ChatRole.user;

  ChatMessage copyWith({
    String? content,
    MessageStatus? status,
    String? errorMessage,
  }) => ChatMessage(
    id: id,
    conversationId: conversationId,
    role: role,
    content: content ?? this.content,
    createdAt: createdAt,
    status: status ?? this.status,
    errorMessage: errorMessage ?? this.errorMessage,
  );
}
