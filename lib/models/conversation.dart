/// 대화방. public.conversations 행과 같은 모양이다.
class Conversation {
  const Conversation({
    required this.id,
    required this.createdAt,
    this.title,
    this.lastMessageAt,
  });

  factory Conversation.fromRow(Map<String, dynamic> row) {
    return Conversation(
      id: row['id'] as String,
      title: row['title'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      lastMessageAt: DateTime.tryParse(row['last_message_at'] as String? ?? ''),
    );
  }

  final String id;

  /// 아직 제목이 없으면 null.
  final String? title;
  final DateTime createdAt;

  /// 마지막 메시지 시각. 메시지가 없으면 null.
  final DateTime? lastMessageAt;

  String get displayTitle {
    final title = this.title?.trim();
    return title == null || title.isEmpty ? '새 대화' : title;
  }

  /// 목록 정렬 기준: 마지막 메시지 시각, 없으면 만든 시각.
  DateTime get sortTime => lastMessageAt ?? createdAt;

  Conversation copyWith({String? title, DateTime? lastMessageAt}) =>
      Conversation(
        id: id,
        createdAt: createdAt,
        title: title ?? this.title,
        lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      );

  /// 첫 메시지로 대화 제목을 만든다. 줄바꿈은 공백으로 바꾸고 30자까지 쓴다.
  static String titleFrom(String text) {
    final oneLine = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return oneLine.length <= 30 ? oneLine : '${oneLine.substring(0, 30)}…';
  }
}
