import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'package:my_app/models/chat_message.dart';
import 'package:my_app/models/chat_usage.dart';
import 'package:my_app/models/conversation.dart';
import 'package:my_app/services/auth_service.dart';
import 'package:my_app/services/chat_repository.dart';

/// 서버 대신 쓰는 인증 서비스.
class FakeAuthService implements AuthService {
  // 비공개 필드는 named 매개변수로 직접 받을 수 없어 초기화 목록을 쓴다.
  // ignore: prefer_initializing_formals
  FakeAuthService({AppUser? user}) : _user = user;

  AppUser? _user;
  final _changes = StreamController<AppUser?>.broadcast();
  final calls = <String>[];

  Object? signInError;
  Object? signUpError;
  SignUpOutcome signUpOutcome = SignUpOutcome.needsEmailConfirmation;

  void _setUser(AppUser? user) {
    _user = user;
    _changes.add(user);
  }

  @override
  AppUser? get currentUser => _user;

  @override
  Stream<AppUser?> get userChanges => _changes.stream;

  @override
  Future<void> signIn({required String email, required String password}) async {
    calls.add('signIn:$email');
    if (signInError != null) throw signInError!;
    _setUser(AppUser(id: 'user-1', email: email));
  }

  @override
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
  }) async {
    calls.add('signUp:$email');
    if (signUpError != null) throw signUpError!;
    if (signUpOutcome == SignUpOutcome.signedIn) {
      _setUser(AppUser(id: 'user-1', email: email));
    }
    return signUpOutcome;
  }

  @override
  Future<void> resendConfirmation(String email) async {
    calls.add('resend:$email');
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    _setUser(null);
  }
}

const permissionDenied = PostgrestException(message: 'denied', code: '42501');

/// 서버 대신 메모리에서 대화를 다루는 채팅 저장소.
///
/// [replies]가 있으면 테스트가 답변 이벤트를 직접 보낸다(스트리밍 확인용).
/// 없으면 '안녕'·'하세요' 두 조각으로 바로 답한다.
class FakeChatRepository implements ChatRepository {
  FakeChatRepository({
    List<Conversation> conversations = const [],
    Map<String, List<ChatMessage>> messages = const {},
    this.isDemo = false,
    this.savesConversations = true,
  }) : conversations = [...conversations],
       messages = {
         for (final e in messages.entries) e.key: [...e.value],
       };

  @override
  final bool isDemo;

  @override
  final bool savesConversations;

  final List<Conversation> conversations;
  final Map<String, List<ChatMessage>> messages;

  Object? fetchConversationsError;
  Object? fetchMessagesError;

  /// fetchUsage가 돌려줄 사용량과 오류, 호출 횟수
  ChatUsage? usage;
  Object? usageError;
  int usageFetches = 0;

  @override
  Future<ChatUsage?> fetchUsage() async {
    usageFetches++;
    final error = usageError;
    if (error != null) throw error;
    return usage;
  }

  Object? createError;
  Object? deleteError;

  /// 값이 있으면 다음 답변을 이 컨트롤러로 테스트가 직접 흘려보낸다.
  StreamController<ChatReplyEvent>? replies;

  /// 값이 있으면 다음 답변을 이 오류로 실패시킨다(한 번만).
  Object? replyError;

  /// replyError로 실패할 때 질문은 저장된 것으로 볼지
  bool replyErrorUserSaved = false;

  final sent = <String>[];
  final created = <String?>[];
  final deleted = <String>[];
  var _seq = 0;

  @override
  Future<List<Conversation>> fetchConversations() async {
    if (fetchConversationsError != null) throw fetchConversationsError!;
    return [...conversations]..sort((a, b) => b.sortTime.compareTo(a.sortTime));
  }

  @override
  Future<Conversation> createConversation({String? title}) async {
    created.add(title);
    if (createError != null) throw createError!;
    final c = Conversation(
      id: 'c${++_seq}',
      title: title,
      createdAt: DateTime(2026, 10, 20, 9, _seq),
    );
    conversations.add(c);
    messages[c.id] = [];
    return c;
  }

  @override
  Future<void> deleteConversation(String id) async {
    deleted.add(id);
    if (deleteError != null) throw deleteError!;
    conversations.removeWhere((c) => c.id == id);
    messages.remove(id);
  }

  @override
  Future<List<ChatMessage>> fetchMessages(String conversationId) async {
    if (fetchMessagesError != null) throw fetchMessagesError!;
    return [...?messages[conversationId]];
  }

  /// 서버가 저장했다고 가정한 질문·답변을 만든다.
  ChatReplyDone doneFor(String conversationId, String question, String answer) {
    final user = ChatMessage(
      id: 'm${++_seq}',
      conversationId: conversationId,
      role: ChatRole.user,
      content: question,
      createdAt: DateTime(2026, 10, 20, 10, _seq),
    );
    final assistant = ChatMessage(
      id: 'm${++_seq}',
      conversationId: conversationId,
      role: ChatRole.assistant,
      content: answer,
      createdAt: DateTime(2026, 10, 20, 10, _seq),
    );
    messages.putIfAbsent(conversationId, () => []).addAll([user, assistant]);
    return ChatReplyDone(userMessage: user, assistantMessage: assistant);
  }

  @override
  Stream<ChatReplyEvent> sendMessage({
    required String conversationId,
    required String text,
  }) {
    sent.add(text);
    final controlled = replies;
    if (controlled != null) {
      replies = null;
      return controlled.stream;
    }
    final error = replyError;
    if (error != null) {
      replyError = null;
      return Stream.value(
        ChatReplyFailed(error, userMessageSaved: replyErrorUserSaved),
      );
    }
    return Stream.fromIterable([
      const ChatReplyDelta('안녕'),
      const ChatReplyDelta('하세요'),
      doneFor(conversationId, text, '안녕하세요'),
    ]);
  }
}
