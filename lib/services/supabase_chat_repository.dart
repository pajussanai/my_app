import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/ids.dart';
import '../models/chat_message.dart';
import '../models/chat_usage.dart';
import '../models/conversation.dart';
import 'chat_repository.dart';
import 'sse.dart';

/// 답변을 누가 만드는지
enum ChatAnswerMode {
  /// Edge Function `chat`이 AI 답변을 스트리밍하고 서버에서 저장한다.
  ai,

  /// DB 함수 demo_send_message()가 정해진 데모 답변을 저장한다.
  demo,
}

/// Edge Function `chat`을 호출해 응답 본문(SSE 바이트)을 돌려준다.
/// 테스트에서 가짜 서버로 바꿔 끼울 수 있게 분리했다.
typedef ChatFunctionInvoker = Future<Stream<List<int>>> Function(
  Map<String, Object?> body,
);

/// Edge Function `chat`에 GET으로 오늘의 사용량(JSON)을 물어본다.
typedef ChatUsageLoader = Future<Object?> Function();

/// Supabase에 대화와 메시지를 저장하는 채팅 저장소(테스트 프로젝트용).
///
/// - 사용자 구분은 로그인 세션과 RLS(auth.uid() = user_id)가 한다.
///   앱은 user_id를 보내지 않는다(대화는 DB 기본값 auth.uid()로 저장된다).
/// - 메시지는 앱이 직접 쓸 수 없다. AI 모드에서는 Edge Function이,
///   데모 모드에서는 DB 함수 demo_send_message()가 질문과 답변을 함께 저장한다.
/// - 완료([ChatReplyDone])는 서버가 저장에 성공한 뒤에만 보낸다.
class SupabaseChatRepository implements ChatRepository {
  SupabaseChatRepository(
    this._client, {
    this.mode = ChatAnswerMode.ai,
    ChatFunctionInvoker? invoker,
    ChatUsageLoader? usageLoader,
    this.chunkDelay = const Duration(milliseconds: 20),
  }) : _invoke = invoker ?? _invokerFor(_client),
       _loadUsage = usageLoader ?? _usageLoaderFor(_client);

  final SupabaseClient _client;
  final ChatFunctionInvoker _invoke;
  final ChatUsageLoader _loadUsage;
  final ChatAnswerMode mode;

  /// 데모 답변을 화면에 조각 단위로 흘려보낼 때의 간격
  final Duration chunkDelay;

  static const _timeout = Duration(seconds: 15);

  /// 서버가 답변 스트림을 열 때까지 기다리는 시간
  static const _invokeTimeout = Duration(seconds: 30);

  /// 답변 도중 아무것도 오지 않을 때 기다리는 시간
  /// (서버는 15초마다 연결 유지 신호를 보낸다)
  static const _idleTimeout = Duration(seconds: 60);

  static const _conversationColumns = 'id, title, created_at, last_message_at';
  static const _messageColumns =
      'id, conversation_id, role, content, status, created_at';

  static ChatFunctionInvoker _invokerFor(SupabaseClient client) =>
      (body) async {
        final response = await client.functions.invoke('chat', body: body);
        final data = response.data;
        if (data is Stream<List<int>>) return data;
        throw const ChatServiceException('bad_response');
      };

  static ChatUsageLoader _usageLoaderFor(SupabaseClient client) =>
      () async =>
          (await client.functions.invoke('chat', method: HttpMethod.get)).data;

  @override
  bool get isDemo => mode == ChatAnswerMode.demo;

  @override
  bool get savesConversations => true;

  @override
  Future<List<Conversation>> fetchConversations() async {
    final rows = await _client
        .from('conversations')
        .select(_conversationColumns)
        .order('last_message_at', ascending: false, nullsFirst: false)
        .order('created_at', ascending: false)
        .timeout(_timeout);
    return rows.map(Conversation.fromRow).toList();
  }

  @override
  Future<Conversation> createConversation({String? title}) async {
    // id는 앱이 정해 같은 요청을 다시 보내도 중복으로 생기지 않게 한다.
    // user_id는 보내지 않는다: DB 기본값 auth.uid()가 쓰이고 RLS가 다시 확인한다.
    final row = await _client
        .from('conversations')
        .insert({'id': newUuid(), 'title': ?title})
        .select(_conversationColumns)
        .single()
        .timeout(_timeout);
    return Conversation.fromRow(row);
  }

  @override
  Future<void> deleteConversation(String id) async {
    // 메시지는 외래 키로 함께 지워진다. 이미 없으면 지울 것도 없으므로 성공으로 본다.
    await _client.from('conversations').delete().eq('id', id).timeout(_timeout);
  }

  @override
  Future<List<ChatMessage>> fetchMessages(String conversationId) async {
    final rows = await _client
        .from('messages')
        .select(_messageColumns)
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .order('id', ascending: true)
        .timeout(_timeout);
    return rows.map(ChatMessage.fromRow).toList();
  }

  /// 서버가 집계한 오늘의 사용량. AI는 호출하지 않는다(데모 모드는 null).
  @override
  Future<ChatUsage?> fetchUsage() async {
    if (mode == ChatAnswerMode.demo) return null;
    final Object? data;
    try {
      data = await _loadUsage().timeout(_timeout);
    } catch (e) {
      throw toChatError(e);
    }
    if (data is! Map<String, dynamic>) {
      throw const ChatServiceException('bad_response');
    }
    return ChatUsage.fromJson(data);
  }

  @override
  Stream<ChatReplyEvent> sendMessage({
    required String conversationId,
    required String text,
  }) => switch (mode) {
    ChatAnswerMode.ai => _sendWithAi(conversationId, text),
    ChatAnswerMode.demo => _sendWithDemo(conversationId, text),
  };

  /// Edge Function의 실제 스트리밍 응답을 받은 그대로 화면에 넘긴다.
  ///
  /// 서버는 AI 답변이 끝난 뒤에 질문과 답변을 함께 저장하므로,
  /// done 전에 실패하면 질문도 저장되지 않은 것이다.
  Stream<ChatReplyEvent> _sendWithAi(
    String conversationId,
    String text,
  ) async* {
    final Stream<List<int>> body;
    try {
      body = await _invoke({'conversation_id': conversationId, 'content': text})
          .timeout(_invokeTimeout);
    } catch (e) {
      yield ChatReplyFailed(toChatError(e));
      return;
    }

    try {
      await for (final event in parseSse(body).timeout(_idleTimeout)) {
        switch (event.event) {
          case 'delta':
            final text = (jsonDecode(event.data) as Map)['text'];
            if (text is String && text.isNotEmpty) yield ChatReplyDelta(text);
          case 'reset':
            yield const ChatReplyRestart();
          case 'done':
            final data = jsonDecode(event.data) as Map;
            final (user, assistant) = parseExchange([
              data['user_message'],
              data['assistant_message'],
            ]);
            yield ChatReplyDone(userMessage: user, assistantMessage: assistant);
            return;
          case 'error':
            final code = (jsonDecode(event.data) as Map)['code'];
            yield ChatReplyFailed(
              ChatServiceException(code is String ? code : 'unknown'),
            );
            return;
        }
      }
      // done이나 error 없이 끝났다: 저장됐는지 알 수 없다.
      yield const ChatReplyFailed(ChatServiceException('incomplete'));
    } catch (e) {
      yield ChatReplyFailed(
        e is FormatException || e is TypeError
            ? const ChatServiceException('bad_response')
            : const ChatServiceException('incomplete'),
      );
    }
  }

  /// 함수 호출 오류를 앱의 오류로 바꾼다. 서버 원문은 버리고 코드만 남긴다.
  static Object toChatError(Object error) {
    if (error is FunctionsFetchException) return error; // 네트워크 오류
    if (error is FunctionException) {
      final details = error.details;
      final code = details is Map && details['code'] is String
          ? details['code'] as String
          : switch (error.status) {
              401 => 'unauthorized',
              _ => 'http_${error.status}',
            };
      return ChatServiceException(code, status: error.status);
    }
    if (error is TimeoutException) {
      return const ChatServiceException('incomplete');
    }
    return error;
  }

  Stream<ChatReplyEvent> _sendWithDemo(
    String conversationId,
    String text,
  ) async* {
    final (ChatMessage, ChatMessage) exchange;
    try {
      final rows = await _client
          .rpc(
            'demo_send_message',
            params: {'p_conversation_id': conversationId, 'p_content': text},
          )
          .timeout(_timeout);
      exchange = parseExchange(rows);
    } catch (e) {
      // 질문과 답변은 한 번에 저장되므로, 실패하면 질문도 저장되지 않은 것이다.
      // (응답만 못 받은 경우는 다음에 대화를 다시 불러오면 서버 상태로 맞춰진다.)
      yield ChatReplyFailed(e);
      return;
    }

    // 데모 답변은 이미 저장된 글을 나눠 보여 주는 것이다(실제 스트리밍 아님).
    final (userMessage, assistantMessage) = exchange;
    for (final chunk in _chunks(assistantMessage.content)) {
      if (chunkDelay > Duration.zero) await Future<void>.delayed(chunkDelay);
      yield ChatReplyDelta(chunk);
    }
    yield ChatReplyDone(
      userMessage: userMessage,
      assistantMessage: assistantMessage,
    );
  }

  /// 서버가 돌려준 행에서 질문과 답변을 꺼낸다.
  static (ChatMessage, ChatMessage) parseExchange(Object? rows) {
    if (rows is! List) {
      throw const FormatException('서버 응답 형식이 올바르지 않습니다.');
    }
    final messages = <ChatMessage>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) {
        throw const FormatException('서버 응답 형식이 올바르지 않습니다.');
      }
      messages.add(ChatMessage.fromRow(row));
    }
    ChatMessage? pick(ChatRole role) {
      for (final m in messages) {
        if (m.role == role) return m;
      }
      return null;
    }

    final user = pick(ChatRole.user);
    final assistant = pick(ChatRole.assistant);
    if (messages.length != 2 || user == null || assistant == null) {
      throw const FormatException('서버 응답 형식이 올바르지 않습니다.');
    }
    return (user, assistant);
  }

  static Iterable<String> _chunks(String text, {int size = 4}) sync* {
    for (var i = 0; i < text.length; i += size) {
      yield text.substring(i, i + size > text.length ? text.length : i + size);
    }
  }
}
