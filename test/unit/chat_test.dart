import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:supabase_flutter/supabase_flutter.dart'
    show
        FunctionException,
        FunctionsFetchException,
        FunctionsHttpException,
        PostgrestException,
        SupabaseClient;

import 'package:my_app/app/bootstrap.dart';
import 'package:my_app/core/config/supabase_config.dart';
import 'package:my_app/core/date_utils.dart';
import 'package:my_app/core/errors.dart';
import 'package:my_app/services/supabase_chat_repository.dart';
import 'package:my_app/features/chat/chat_controller.dart';
import 'package:my_app/features/chat/widgets/usage_card.dart';
import 'package:my_app/models/chat_usage.dart';
import 'package:my_app/models/chat_message.dart';
import 'package:my_app/models/conversation.dart';
import 'package:my_app/services/chat_repository.dart';
import 'package:my_app/services/local_chat_repository.dart';
import 'package:my_app/services/sse.dart';

import '../helpers/fakes.dart';

void main() {
  group('ChatController', () {
    test('첫 메시지로 대화를 만들고 제목을 붙인다', () async {
      final repo = FakeChatRepository();
      final c = ChatController(repo);
      await c.loadConversations();

      expect(await c.send('  안녕하세요, 반가워요  '), isTrue);
      await pumpEventQueue();

      expect(repo.created, ['안녕하세요, 반가워요']);
      expect(c.selectedId, 'c1');
      expect(c.conversations.single.id, 'c1');
      expect(c.messages.map((m) => m.content), ['안녕하세요, 반가워요', '안녕하세요']);
      expect(
        c.messages.every((m) => m.status == MessageStatus.complete),
        isTrue,
      );
      expect(c.sending, isFalse);
    });

    test('답변 중에는 다시 보내지 않는다', () async {
      final repo = FakeChatRepository()..replies = null;
      final c = ChatController(repo);
      await c.loadConversations();

      final first = c.send('하나');
      expect(c.sending, isTrue);
      expect(await c.send('둘'), isFalse);
      await first;
      await pumpEventQueue();
      expect(repo.sent, ['하나']);
    });

    test('대화를 만들지 못하면 false와 안내 문구', () async {
      final repo = FakeChatRepository()..createError = Exception('offline');
      final c = ChatController(repo);

      expect(await c.send('질문'), isFalse);
      expect(c.notice, contains('대화를 시작하지 못했습니다'));
      expect(c.sending, isFalse);
      expect(c.messages, isEmpty);
    });

    test('선택한 대화를 지우면 새 대화 상태로 돌아간다', () async {
      final repo = FakeChatRepository();
      final c = ChatController(repo);
      await c.send('지울 대화');
      await pumpEventQueue();

      await c.deleteConversation('c1');
      expect(c.selectedId, isNull);
      expect(c.messages, isEmpty);
      expect(c.conversations, isEmpty);
    });

    test('삭제가 실패하면 목록을 그대로 두고 안내한다', () async {
      final repo = FakeChatRepository()..deleteError = permissionDenied;
      final c = ChatController(repo);
      await c.send('남는 대화');
      await pumpEventQueue();

      await c.deleteConversation('c1');
      expect(c.conversations.single.id, 'c1');
      expect(c.notice, contains('대화를 삭제하지 못했습니다'));
    });

    test('답변을 받은 대화가 목록 맨 위로 올라간다', () async {
      final repo = FakeChatRepository(
        conversations: [
          Conversation(id: 'a', title: 'A', createdAt: DateTime(2026, 10, 1)),
          Conversation(id: 'b', title: 'B', createdAt: DateTime(2026, 10, 2)),
        ],
        messages: {'a': [], 'b': []},
      );
      final c = ChatController(repo);
      await c.loadConversations();
      expect(c.conversations.map((x) => x.id), ['b', 'a']);

      await c.selectConversation('a');
      await c.send('A에 질문');
      await pumpEventQueue();
      expect(c.conversations.map((x) => x.id), ['a', 'b']);
    });
  });

  group('LocalChatRepository (데모)', () {
    test('답변을 조각으로 보내고, 대화와 메시지를 기억한다', () async {
      final repo = LocalChatRepository(chunkDelay: Duration.zero);
      final conversation = await repo.createConversation(title: '데모');

      final events = await repo
          .sendMessage(conversationId: conversation.id, text: '안녕')
          .toList();

      final deltas = events
          .whereType<ChatReplyDelta>()
          .map((e) => e.text)
          .join();
      final done = events.last as ChatReplyDone;
      expect(deltas, LocalChatRepository.demoReplyFor('안녕'));
      expect(done.assistantMessage.content, deltas);
      expect(events.whereType<ChatReplyDelta>().length, greaterThan(1));

      final messages = await repo.fetchMessages(conversation.id);
      expect(messages.map((m) => m.role), [ChatRole.user, ChatRole.assistant]);
      expect((await repo.fetchConversations()).single.lastMessageAt, isNotNull);
      expect(repo.isDemo, isTrue);
    });

    test('없는 대화에 보내면 실패 이벤트', () async {
      final repo = LocalChatRepository(chunkDelay: Duration.zero);
      final events = await repo
          .sendMessage(conversationId: 'none', text: 'x')
          .toList();
      expect(events.single, isA<ChatReplyFailed>());
    });
  });

  group('대화 제목과 시각', () {
    test('첫 메시지로 만든 제목은 한 줄, 30자까지', () {
      expect(Conversation.titleFrom('  줄\n바꿈\t있는   제목 '), '줄 바꿈 있는 제목');
      expect(Conversation.titleFrom('가' * 40), '${'가' * 30}…');
    });

    test('제목이 없으면 새 대화로 표시', () {
      final c = Conversation(id: 'x', createdAt: DateTime(2026), title: '  ');
      expect(c.displayTitle, '새 대화');
    });

    test('목록 시각: 오늘은 시:분, 올해는 월·일', () {
      final now = DateTime(2026, 10, 20, 15);
      expect(formatListTime(DateTime(2026, 10, 20, 9, 5), now), '09:05');
      expect(formatListTime(DateTime(2026, 3, 2), now), '3월 2일');
      expect(formatListTime(DateTime(2025, 12, 31), now), '2025년 12월 31일');
    });

    test('서버 행을 읽는다', () {
      final m = ChatMessage.fromRow({
        'id': 'm',
        'conversation_id': 'c',
        'role': 'assistant',
        'content': '답',
        'status': 'streaming',
        'created_at': '2026-10-20T01:02:03Z',
      });
      expect(m.role, ChatRole.assistant);
      expect(m.status, MessageStatus.streaming);
      final c = Conversation.fromRow({
        'id': 'c',
        'title': null,
        'created_at': '2026-10-20T01:02:03Z',
        'last_message_at': null,
      });
      expect(c.displayTitle, '새 대화');
      expect(c.lastMessageAt, isNull);
    });
  });

  group('저장 실패 표시', () {
    test('질문까지 저장되지 않았으면 질문도 실패로 표시한다', () async {
      final repo = FakeChatRepository()..replyError = Exception('offline');
      final c = ChatController(repo);

      await c.send('저장 안 될 질문');
      await pumpEventQueue();

      expect(c.messages.map((m) => (m.role, m.status)), [
        (ChatRole.user, MessageStatus.error),
        (ChatRole.assistant, MessageStatus.error),
      ]);
      expect(c.canRetry, isTrue);
    });

    test('질문은 저장되고 답변만 실패했으면 질문은 그대로 둔다', () async {
      final repo = FakeChatRepository()
        ..replyError = Exception('timeout')
        ..replyErrorUserSaved = true;
      final c = ChatController(repo);

      await c.send('저장된 질문');
      await pumpEventQueue();

      expect(c.messages.first.status, MessageStatus.complete);
      expect(c.messages.last.status, MessageStatus.error);
    });
  });

  group('SupabaseChatRepository', () {
    Map<String, dynamic> row(
      String id,
      String role,
      String content,
      String at,
    ) => {
      'id': id,
      'conversation_id': 'c',
      'user_id': 'u',
      'role': role,
      'content': content,
      'status': 'complete',
      'created_at': at,
    };

    test('demo_send_message() 응답에서 질문과 답변을 꺼낸다 (순서와 무관)', () {
      final (user, assistant) = SupabaseChatRepository.parseExchange([
        row('a', 'assistant', '답변', '2026-10-20T01:00:00.000002Z'),
        row('q', 'user', '질문', '2026-10-20T01:00:00.000001Z'),
      ]);
      expect((user.id, user.content), ('q', '질문'));
      expect((assistant.id, assistant.content), ('a', '답변'));
    });

    test('응답 형식이 다르면 오류로 처리한다 (성공처럼 보이지 않게)', () {
      expect(
        () => SupabaseChatRepository.parseExchange(null),
        throwsFormatException,
      );
      expect(
        () => SupabaseChatRepository.parseExchange([]),
        throwsFormatException,
      );
      expect(
        () => SupabaseChatRepository.parseExchange([
          row('q', 'user', '질문', '2026-10-20T01:00:00Z'),
        ]),
        throwsFormatException,
      );
    });

    test('test 환경은 서버 저장소, production은 로컬 데모(null)', () {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'sb_publishable_test',
      );
      addTearDown(client.dispose);
      final repo = chatRepositoryFor('test', client);
      expect(repo, isA<SupabaseChatRepository>());
      expect(repo!.savesConversations, isTrue);
      expect(repo.isDemo, isFalse, reason: '기본은 AI 답변');
      expect(
        chatRepositoryFor('test', client, answers: 'demo')!.isDemo,
        isTrue,
      );
      expect(
        () => chatRepositoryFor('test', client, answers: 'fake'),
        throwsStateError,
      );
      expect(chatRepositoryFor('production', client), isNull);
    });

    test('서버 함수 오류 코드를 사용자 문구로 바꾼다', () {
      expect(
        describeError(const PostgrestException(message: 'x', code: 'P0002')),
        contains('대화를 찾을 수 없습니다'),
      );
      expect(
        describeError(const PostgrestException(message: 'x', code: '22023')),
        '메시지가 비어 있거나 너무 깁니다.',
      );
      expect(
        describeError(const PostgrestException(message: 'x', code: 'PGRST202')),
        '서버에 필요한 기능이 없습니다.',
      );
    });
  });

  group('SSE 파서', () {
    test('여러 조각에 걸친 줄·한글을 이어 붙이고 연결 유지 신호는 무시한다', () async {
      final bytes = utf8.encode(
        ': ping\n\nevent: delta\ndata: {"text":"안녕"}\n\n'
        'data: a\ndata: b\n\nevent: done\ndata: {}',
      );
      // 한글 중간에서 끊기도록 3바이트씩 나눠 보낸다.
      final chunks = [
        for (var i = 0; i < bytes.length; i += 3)
          bytes.sublist(i, i + 3 > bytes.length ? bytes.length : i + 3),
      ];
      final events = await parseSse(Stream.fromIterable(chunks)).toList();
      expect(events.map((e) => (e.event, e.data)), [
        ('delta', '{"text":"안녕"}'),
        ('message', 'a\nb'),
      ], reason: '빈 줄로 끝나지 않은 마지막 이벤트는 버린다');
    });
  });

  group('SupabaseChatRepository (AI 모드)', () {
    late SupabaseClient client;
    setUp(() {
      client = SupabaseClient(
        'https://example.supabase.co',
        'sb_publishable_x',
      );
    });
    tearDown(() => client.dispose());

    String sse(String event, Map<String, Object?> data) =>
        'event: $event\ndata: ${jsonEncode(data)}\n\n';

    Map<String, Object?> row(String id, String role, String content) => {
      'id': id,
      'conversation_id': 'c',
      'role': role,
      'content': content,
      'status': 'complete',
      'created_at': '2026-10-20T01:00:00Z',
    };

    SupabaseChatRepository repoWith(
      Future<Stream<List<int>>> Function(Map<String, Object?> body) invoker,
    ) => SupabaseChatRepository(client, invoker: invoker);

    Stream<List<int>> body(List<String> parts) =>
        Stream.fromIterable(parts.map(utf8.encode));

    test('서버가 보낸 조각을 그대로 전달하고 저장된 메시지로 끝난다', () async {
      Map<String, Object?>? sentBody;
      final repo = repoWith((b) async {
        sentBody = b;
        return body([
          ': ping\n\n',
          sse('delta', {'text': '안'}),
          sse('delta', {'text': '녕'}),
          sse('done', {
            'user_message': row('q', 'user', '질문'),
            'assistant_message': row('a', 'assistant', '안녕'),
          }),
        ]);
      });

      final events = await repo
          .sendMessage(conversationId: 'c', text: '질문')
          .toList();
      expect(sentBody, {'conversation_id': 'c', 'content': '질문'});
      expect(events.whereType<ChatReplyDelta>().map((e) => e.text), ['안', '녕']);
      final done = events.last as ChatReplyDone;
      expect((done.userMessage.id, done.assistantMessage.id), ('q', 'a'));
    });

    test('reset은 다시 시작 이벤트, error는 실패(저장 안 됨)로 바꾼다', () async {
      final repo = repoWith(
        (_) async => body([
          sse('delta', {'text': '버릴 글'}),
          sse('reset', {}),
          sse('error', {'code': 'save_failed'}),
        ]),
      );
      final events = await repo
          .sendMessage(conversationId: 'c', text: 'q')
          .toList();
      expect(events[1], isA<ChatReplyRestart>());
      final failed = events.last as ChatReplyFailed;
      expect((failed.error as ChatServiceException).code, 'save_failed');
      expect(failed.userMessageSaved, isFalse);
    });

    test('done 없이 끊기면 성공으로 보지 않는다', () async {
      final repo = repoWith(
        (_) async => body([
          sse('delta', {'text': '중간까지'}),
        ]),
      );
      final events = await repo
          .sendMessage(conversationId: 'c', text: 'q')
          .toList();
      expect(events.whereType<ChatReplyDone>(), isEmpty);
      expect(
        ((events.last as ChatReplyFailed).error as ChatServiceException).code,
        'incomplete',
      );
    });

    test('HTTP 오류 응답의 코드를 꺼낸다 (한도·미설정·로그인)', () async {
      Future<ChatServiceException> errorFor(FunctionException e) async {
        final repo = repoWith((_) async => throw e);
        final events = await repo
            .sendMessage(conversationId: 'c', text: 'q')
            .toList();
        return (events.single as ChatReplyFailed).error as ChatServiceException;
      }

      final limit = await errorFor(
        const FunctionsHttpException(
          status: 429,
          details: {'code': 'daily_limit_reached'},
        ),
      );
      expect((limit.code, limit.status), ('daily_limit_reached', 429));
      expect(
        (await errorFor(const FunctionsHttpException(status: 401))).code,
        'unauthorized',
      );
      expect(describeError(limit), contains('오늘 보낼 수 있는 메시지'));
      expect(
        describeError(const ChatServiceException('ai_not_configured')),
        contains('AI 서버가 아직 준비되지 않았습니다'),
      );
      expect(
        describeError(const ChatServiceException('ai_quota_exceeded')),
        contains('AI 무료 사용량을 모두 사용했습니다'),
      );
    });

    test('네트워크 오류는 네트워크 안내 문구', () async {
      final repo = repoWith(
        (_) async => throw const FunctionsFetchException(details: 'offline'),
      );
      final events = await repo
          .sendMessage(conversationId: 'c', text: 'q')
          .toList();
      expect(
        describeError((events.single as ChatReplyFailed).error),
        contains('네트워크'),
      );
    });
  });

  group('AI 사용량', () {
    Map<String, Object?> usageJson({int used = 12, int limit = 100}) => {
      'day': '2026-10-20',
      'provider': 'gemini',
      'model': 'gemini-3.5-flash-lite',
      'ai_configured': true,
      'request_count': used,
      'input_tokens': 3400,
      'output_tokens': 1200,
      'daily_limit': limit,
      'remaining': limit - used < 0 ? 0 : limit - used,
    };

    test('서버 응답을 읽는다', () {
      final u = ChatUsage.fromJson(usageJson());
      expect((u.requestCount, u.dailyLimit, u.remaining), (12, 100, 88));
      expect((u.inputTokens, u.outputTokens), (3400, 1200));
      expect(u.model, 'gemini-3.5-flash-lite');
      expect(() => ChatUsage.fromJson({}), throwsFormatException);
    });

    test('상태: 정상은 앱 기준, Google 초과·앱 한도·미설정은 막힘', () {
      final ok = ChatUsage.fromJson(usageJson());
      expect(usageStatusOf(ok).tone, UsageTone.ok);
      expect(usageStatusOf(ok).detail, contains('앱 기준'));
      expect(
        usageStatusOf(ok, limitCode: 'ai_quota_exceeded').label,
        'Google 무료 사용량 초과',
      );
      expect(
        usageStatusOf(ChatUsage.fromJson(usageJson(used: 100))).label,
        '앱 일일 한도 도달',
      );
      expect(
        usageStatusOf(ChatUsage.fromJson(usageJson(used: 95))).tone,
        UsageTone.warn,
      );
      final notConfigured = ChatUsage.fromJson({
        ...usageJson(),
        'ai_configured': false,
      });
      expect(usageStatusOf(notConfigured).label, 'AI 서버 준비 중');
    });

    test('저장소: GET 결과를 읽고, 오류는 코드로 바꾸고, 데모 모드는 null', () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'sb_publishable_x',
      );
      addTearDown(client.dispose);

      final repo = SupabaseChatRepository(
        client,
        usageLoader: () async => usageJson(),
      );
      expect((await repo.fetchUsage())!.remaining, 88);

      final denied = SupabaseChatRepository(
        client,
        usageLoader: () async => throw const FunctionsHttpException(
          status: 401,
          details: {'code': 'unauthorized'},
        ),
      );
      await expectLater(
        denied.fetchUsage(),
        throwsA(
          isA<ChatServiceException>().having(
            (e) => e.code,
            'code',
            'unauthorized',
          ),
        ),
      );

      final demo = SupabaseChatRepository(
        client,
        mode: ChatAnswerMode.demo,
        usageLoader: () async => fail('데모 모드는 서버에 묻지 않는다'),
      );
      expect(await demo.fetchUsage(), isNull);
    });

    test('컨트롤러: 제한 오류를 기억하고, 답변을 받으면 지우고, 끝날 때마다 사용량을 새로 고친다', () async {
      final repo = FakeChatRepository()
        ..usage = ChatUsage.fromJson(usageJson())
        ..replyError = const ChatServiceException('ai_quota_exceeded');
      final c = ChatController(repo);
      await c.loadConversations();
      await pumpEventQueue();
      expect(c.usage!.requestCount, 12);
      final before = repo.usageFetches;

      await c.send('질문');
      await pumpEventQueue();
      expect(c.limitCode, 'ai_quota_exceeded');
      expect(repo.usageFetches, greaterThan(before));
      expect(c.messages.last.errorMessage, contains('무료 사용량'));

      await c.retry();
      await pumpEventQueue();
      expect(c.limitCode, isNull, reason: '답변을 받았으면 제한이 풀린 것');
    });
  });

  group('ChatController 다시 시작', () {
    test('ChatReplyRestart를 받으면 앞의 글을 지우고 새 글만 남긴다', () async {
      final replies = StreamController<ChatReplyEvent>();
      addTearDown(replies.close);
      final repo = FakeChatRepository()..replies = replies;
      final c = ChatController(repo);
      await c.send('질문');
      replies.add(const ChatReplyDelta('버릴 '));
      await pumpEventQueue();
      expect(c.messages.last.content, '버릴 ');
      replies.add(const ChatReplyRestart());
      replies.add(const ChatReplyDelta('새 답'));
      await pumpEventQueue();
      expect(c.messages.last.content, '새 답');
      expect(c.messages.last.status, MessageStatus.streaming);
    });
  });

  group('Supabase 환경 설정', () {
    test('기본 환경은 테스트 프로젝트', () {
      expect(supabaseEnvironment, 'test');
      expect(supabaseUrl, 'https://dnqrwybyksnoyqtkuwlp.supabase.co');
      expect(supabaseUrl, isNot(contains('sdwkhsdkkorxpouvroue')));
    });

    test('알 수 없는 환경 이름은 거부한다', () {
      expect(() => checkSupabaseEnvironment('test'), returnsNormally);
      expect(() => checkSupabaseEnvironment('production'), returnsNormally);
      expect(() => checkSupabaseEnvironment('prod'), throwsStateError);
      expect(() => checkSupabaseEnvironment(''), throwsStateError);
    });
  });
}
