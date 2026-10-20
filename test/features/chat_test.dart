import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_app/main.dart';
import 'package:my_app/models/chat_message.dart';
import 'package:my_app/models/chat_usage.dart';
import 'package:my_app/models/conversation.dart';
import 'package:my_app/features/chat/widgets/message_bubble.dart';
import 'package:my_app/services/chat_repository.dart';
import 'package:my_app/widgets/baby_avatar.dart';

import '../helpers/fakes.dart';
import '../helpers/test_helpers.dart';

/// 로그인한 상태로 채팅 화면을 띄운다.
Future<FakeChatRepository> pumpChat(
  WidgetTester tester, {
  FakeChatRepository? chat,
  Size size = const Size(800, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = chat ?? FakeChatRepository();
  await tester.pumpWidget(
    MyApp(
      auth: FakeAuthService(user: testUser),
      chatRepository: repo,
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

/// 말풍선 안의 글자만 찾는다(상단 제목에도 첫 질문이 보이기 때문).
Finder inBubbles(String text) =>
    find.descendant(of: find.byType(MessageBubble), matching: find.text(text));

Future<void> sendText(WidgetTester tester, String text) async {
  await tester.enterText(chatInput, text);
  await tester.pump();
  await tester.tap(chatSendButton);
  await tester.pump();
}

void main() {
  group('채팅 화면', () {
    testWidgets('로그인 후 첫 화면은 빈 새 대화', (tester) async {
      await pumpChat(tester);

      expect(chatInput, findsOneWidget);
      expect(find.byKey(const Key('welcomeMessage')), findsOneWidget);
      expect(find.text('새 대화'), findsOneWidget); // 상단 제목
      expect(find.byKey(const Key('demoBanner')), findsNothing);
    });

    testWidgets('환영 화면의 추천 문장을 누르면 바로 보내고, 아기 얼굴은 답변 옆에만 있다', (tester) async {
      final repo = await pumpChat(tester);

      await tester.tap(find.text('아기는 지금 뭐 하고 있어?'));
      await tester.pumpAndSettle();

      expect(repo.sent, ['아기는 지금 뭐 하고 있어?']);
      expect(find.byKey(const Key('welcomeMessage')), findsNothing);
      final avatars = find.descendant(
        of: find.byType(MessageBubble),
        matching: find.byType(BabyAvatar),
      );
      expect(avatars, findsOneWidget, reason: '질문 1개 + 답변 1개 중 답변에만');
    });

    testWidgets('사용량 카드: 앱 집계 값을 보여 주고, 자세히 보기에서 Google 할당량과 구분한다', (
      tester,
    ) async {
      final repo = FakeChatRepository()
        ..usage = const ChatUsage(
          day: '2026-10-20',
          provider: 'gemini',
          model: 'gemini-3.5-flash-lite',
          aiConfigured: true,
          requestCount: 12,
          inputTokens: 3400,
          outputTokens: 1200,
          dailyLimit: 100,
          remaining: 88,
        );
      await pumpChat(tester, chat: repo, size: const Size(1200, 1000));

      expect(find.text('오늘 12회 · 앱 한도 100회 · 남은 88회'), findsOneWidget);
      expect(find.text('정상 이용 가능'), findsOneWidget);

      await tester.tap(find.byKey(const Key('usageCard')));
      await tester.pumpAndSettle();
      final details = find.byKey(const Key('usageDetails'));
      Finder inDetails(String text) =>
          find.descendant(of: details, matching: find.text(text));
      expect(inDetails('앱 자체 집계 (한국 시간 기준 오늘)'), findsOneWidget);
      expect(inDetails('88회'), findsOneWidget);
      expect(inDetails('3,400'), findsOneWidget);
      expect(inDetails('gemini-3.5-flash-lite'), findsOneWidget);
      expect(inDetails('Google Gemini 무료 할당량'), findsOneWidget);
      expect(
        inDetails('https://aistudio.google.com/rate-limit'),
        findsOneWidget,
      );
    });

    testWidgets('AI 서버를 쓰지 않는 저장소에서는 사용량 카드를 숨긴다', (tester) async {
      await pumpChat(tester, size: const Size(1200, 1000));
      expect(find.byKey(const Key('usageCard')), findsNothing);
    });

    testWidgets('빈 메시지는 보낼 수 없다', (tester) async {
      final repo = await pumpChat(tester);

      expect(tester.widget<InkWell>(chatSendButton).onTap, isNull);
      await tester.enterText(chatInput, '   ');
      await tester.pump();
      expect(tester.widget<InkWell>(chatSendButton).onTap, isNull);
      expect(repo.sent, isEmpty);
    });

    testWidgets('보내면 질문이 바로 보이고 답변이 조각 단위로 이어서 보인다', (tester) async {
      final repo = FakeChatRepository()..replies = StreamController();
      final replies = repo.replies!;
      await pumpChat(tester, chat: repo);

      await sendText(tester, '오늘 날씨 어때?');

      // 질문은 바로, 답변은 작성 중 표시
      expect(inBubbles('오늘 날씨 어때?'), findsOneWidget);
      expect(find.text('아기가 꼬물꼬물 대답을 생각하고 있어요…'), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: chatInput,
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        isEmpty,
      );
      expect(repo.created, ['오늘 날씨 어때?']);
      // 답변 중에는 또 보낼 수 없다
      await tester.enterText(chatInput, '하나 더');
      await tester.pump();
      expect(tester.widget<InkWell>(chatSendButton).onTap, isNull);

      replies.add(const ChatReplyDelta('맑고 '));
      await tester.pump();
      expect(find.text('맑고 '), findsOneWidget);

      replies.add(const ChatReplyDelta('따뜻해요.'));
      await tester.pump();
      expect(find.text('맑고 따뜻해요.'), findsOneWidget);

      replies.add(repo.doneFor('c1', '오늘 날씨 어때?', '맑고 따뜻해요.'));
      await replies.close();
      await tester.pumpAndSettle();

      expect(find.text('맑고 따뜻해요.'), findsOneWidget);
      expect(find.text('아기가 꼬물꼬물 대답을 생각하고 있어요…'), findsNothing);
      expect(tester.widget<InkWell>(chatSendButton).onTap, isNotNull);
      // 상단 제목이 첫 질문으로 바뀌고, 목록에도 생긴다
      expect(find.widgetWithText(AppBar, '오늘 날씨 어때?'), findsOneWidget);
      await openConversationDrawer(tester);
      expect(find.byKey(const ValueKey('conversation-c1')), findsOneWidget);
    });

    testWidgets('같은 대화에서 이어서 보내면 새 대화를 만들지 않는다', (tester) async {
      final repo = await pumpChat(tester);

      await sendText(tester, '첫 질문');
      await tester.pumpAndSettle();
      await sendText(tester, '두 번째 질문');
      await tester.pumpAndSettle();

      expect(repo.created, ['첫 질문']);
      expect(repo.sent, ['첫 질문', '두 번째 질문']);
      expect(find.text('안녕하세요'), findsNWidgets(2));
    });

    testWidgets('답변이 실패하면 오류와 다시 시도를 보여 주고, 다시 시도할 수 있다', (tester) async {
      final repo = FakeChatRepository()..replyError = Exception('offline');
      await pumpChat(tester, chat: repo);

      await sendText(tester, '안녕?');
      await tester.pumpAndSettle();

      expect(find.textContaining('답변을 받지 못했습니다'), findsOneWidget);
      expect(find.textContaining('네트워크 연결을 확인'), findsOneWidget);

      await tester.tap(find.byKey(const Key('retryButton')));
      await tester.pumpAndSettle();

      expect(repo.sent, ['안녕?', '안녕?']);
      expect(find.textContaining('답변을 받지 못했습니다'), findsNothing);
      expect(find.text('안녕하세요'), findsOneWidget);
      expect(inBubbles('안녕?'), findsOneWidget); // 질문이 중복으로 남지 않는다
    });

    testWidgets('대화를 만들지 못하면 입력 내용을 남기고 안내한다', (tester) async {
      final repo = FakeChatRepository()..createError = permissionDenied;
      await pumpChat(tester, chat: repo);

      await sendText(tester, '남겨 둘 질문');
      await tester.pumpAndSettle();

      expect(find.textContaining('대화를 시작하지 못했습니다'), findsOneWidget);
      expect(repo.sent, isEmpty);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: chatInput,
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        '남겨 둘 질문',
      );
    });

    testWidgets('이전 대화를 고르면 메시지를 불러온다', (tester) async {
      final repo = FakeChatRepository(
        conversations: [
          Conversation(
            id: 'old',
            title: '여행 계획',
            createdAt: DateTime(2026, 10, 1),
          ),
        ],
        messages: {
          'old': [
            ChatMessage(
              id: 'q',
              conversationId: 'old',
              role: ChatRole.user,
              content: '제주도 일정 짜 줘',
              createdAt: DateTime(2026, 10, 1, 9),
            ),
            ChatMessage(
              id: 'a',
              conversationId: 'old',
              role: ChatRole.assistant,
              content: '첫째 날은 동쪽부터…',
              createdAt: DateTime(2026, 10, 1, 9, 1),
            ),
          ],
        },
      );
      await pumpChat(tester, chat: repo);

      await openConversationDrawer(tester);
      await tester.tap(find.text('여행 계획'));
      await tester.pumpAndSettle();

      expect(find.text('제주도 일정 짜 줘'), findsOneWidget);
      expect(find.text('첫째 날은 동쪽부터…'), findsOneWidget);
      expect(find.widgetWithText(AppBar, '여행 계획'), findsOneWidget);

      // 새 대화로 돌아가기
      await tester.tap(find.byTooltip('새 대화'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('welcomeMessage')), findsOneWidget);
    });

    testWidgets('메시지를 불러오지 못하면 다시 시도할 수 있다', (tester) async {
      final repo = FakeChatRepository(
        conversations: [
          Conversation(
            id: 'old',
            title: '여행 계획',
            createdAt: DateTime(2026, 10, 1),
          ),
        ],
        messages: {
          'old': [
            ChatMessage(
              id: 'q',
              conversationId: 'old',
              role: ChatRole.user,
              content: '저장된 질문',
              createdAt: DateTime(2026, 10, 1, 9),
            ),
          ],
        },
      )..fetchMessagesError = Exception('offline');
      await pumpChat(tester, chat: repo);

      await openConversationDrawer(tester);
      await tester.tap(find.text('여행 계획'));
      await tester.pumpAndSettle();
      expect(find.textContaining('메시지를 불러오지 못했습니다'), findsOneWidget);

      repo.fetchMessagesError = null;
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();
      expect(find.text('저장된 질문'), findsOneWidget);
    });

    testWidgets('대화 삭제는 확인 후에만 지운다', (tester) async {
      final repo = FakeChatRepository(
        conversations: [
          Conversation(
            id: 'old',
            title: '지울 대화',
            createdAt: DateTime(2026, 10, 1),
          ),
        ],
      );
      await pumpChat(tester, chat: repo);
      await openConversationDrawer(tester);

      await tester.tap(find.byTooltip('대화 삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(repo.deleted, isEmpty);
      expect(find.text('지울 대화'), findsOneWidget);

      await tester.tap(find.byTooltip('대화 삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '삭제'));
      await tester.pumpAndSettle();
      expect(repo.deleted, ['old']);
      expect(find.text('지울 대화'), findsNothing);
      expect(find.text('아직 대화가 없어요.'), findsOneWidget);
    });

    testWidgets('할 일(이전 기능) 메뉴는 더 이상 없다', (tester) async {
      await pumpChat(tester, size: const Size(1200, 1000));
      expect(find.byKey(const Key('openTodos')), findsNothing);
      expect(find.textContaining('할 일'), findsNothing);
    });

    testWidgets('데모 저장소면 데모 안내를 보여 준다 (저장 여부에 따라 문구가 다름)', (tester) async {
      await pumpChat(tester, chat: FakeChatRepository(isDemo: true));
      expect(find.byKey(const Key('demoBanner')), findsOneWidget);
      expect(find.textContaining('대화는 저장됩니다'), findsOneWidget);
    });

    testWidgets('저장하지 않는 데모 저장소면 새로고침 시 사라진다고 안내한다', (tester) async {
      await pumpChat(
        tester,
        chat: FakeChatRepository(isDemo: true, savesConversations: false),
      );
      expect(find.textContaining('새로고침하면 사라집니다'), findsOneWidget);
    });

    testWidgets('저장되지 않은 질문은 "전송되지 않음"으로 표시하고, 다시 시도하면 사라진다', (tester) async {
      final repo = FakeChatRepository()..replyError = permissionDenied;
      await pumpChat(tester, chat: repo);

      await sendText(tester, '실패할 질문');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notSentLabel')), findsOneWidget);
      expect(find.textContaining('답변을 받지 못했습니다'), findsOneWidget);

      await tester.tap(find.byKey(const Key('retryButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notSentLabel')), findsNothing);
      expect(inBubbles('실패할 질문'), findsOneWidget);
      expect(find.text('안녕하세요'), findsOneWidget);
    });

    testWidgets('채팅에서 로그아웃하면 로그인 화면으로 돌아간다', (tester) async {
      await pumpChat(tester);

      await openConversationDrawer(tester);
      await tester.tap(find.byTooltip('로그아웃'));
      await tester.pumpAndSettle();

      expect(emailInput, findsOneWidget);
      expect(chatInput, findsNothing);
    });
  });

  group('키보드 입력', () {
    final desktop = TargetPlatformVariant.only(TargetPlatform.windows);
    final phone = TargetPlatformVariant.only(TargetPlatform.android);

    String inputText(WidgetTester tester) => tester
        .widget<EditableText>(
          find.descendant(of: chatInput, matching: find.byType(EditableText)),
        )
        .controller
        .text;

    Future<void> pressShiftEnter(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
    }

    testWidgets('데스크톱: Enter로 보내고 입력창을 비운다', (tester) async {
      final repo = await pumpChat(tester);

      await tester.enterText(chatInput, '엔터로 보내기');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(repo.sent, ['엔터로 보내기']);
      expect(inputText(tester), isEmpty);
      expect(inBubbles('엔터로 보내기'), findsOneWidget);
    }, variant: desktop);

    testWidgets('데스크톱: 숫자 키패드 Enter도 보낸다', (tester) async {
      final repo = await pumpChat(tester);

      await tester.enterText(chatInput, '키패드');
      // 테스트 도구의 Windows 키 시뮬레이터에는 키패드 Enter 코드가 없어 웹 방식으로 보낸다.
      await tester.sendKeyEvent(
        LogicalKeyboardKey.numpadEnter,
        platform: 'web',
      );
      await tester.pumpAndSettle();

      expect(repo.sent, ['키패드']);
    }, variant: desktop);

    Future<void> pressCtrlEnter(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    TextSelection inputSelection(WidgetTester tester) => tester
        .widget<EditableText>(
          find.descendant(of: chatInput, matching: find.byType(EditableText)),
        )
        .controller
        .selection;

    testWidgets('데스크톱: Ctrl+Enter는 줄바꿈을 넣고 보내지 않는다', (tester) async {
      final repo = await pumpChat(tester);

      await tester.enterText(chatInput, '첫 줄');
      await pressCtrlEnter(tester);

      expect(repo.sent, isEmpty);
      expect(inputText(tester), '첫 줄\n');
      expect(inputSelection(tester), const TextSelection.collapsed(offset: 4));

      // 이어서 Enter를 누르면 두 줄이 그대로 전송된다.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '첫 줄\n둘째 줄',
          selection: TextSelection.collapsed(offset: 8),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(repo.sent, ['첫 줄\n둘째 줄']);
    }, variant: desktop);

    testWidgets('데스크톱: Ctrl+Enter는 커서 자리에 넣고, 선택한 글자는 바꾼다', (tester) async {
      await pumpChat(tester);
      await tester.tap(chatInput);
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '앞뒤',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      await tester.pump();
      await pressCtrlEnter(tester);
      expect(inputText(tester), '앞\n뒤');
      expect(inputSelection(tester), const TextSelection.collapsed(offset: 2));

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '가나다',
          selection: TextSelection(baseOffset: 1, extentOffset: 2),
        ),
      );
      await tester.pump();
      await pressCtrlEnter(tester);
      expect(inputText(tester), '가\n다');
    }, variant: desktop);

    testWidgets('데스크톱: 한글 조합 중 Ctrl+Enter는 글자 확정을 입력기에 맡긴다', (tester) async {
      final repo = await pumpChat(tester);
      await tester.tap(chatInput);
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '안녕',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 1, end: 2),
        ),
      );
      await tester.pump();
      await pressCtrlEnter(tester);
      // 조합 중에는 앱이 글자를 바꾸지 않는다(글자 중복·손실 방지).
      expect(inputText(tester), '안녕');
      expect(repo.sent, isEmpty);

      // 입력기가 글자를 확정한 뒤의 Ctrl+Enter는 줄바꿈을 넣는다.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '안녕',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.pump();
      await pressCtrlEnter(tester);
      expect(inputText(tester), '안녕\n');
      expect(repo.sent, isEmpty);
    }, variant: desktop);

    testWidgets('데스크톱: Shift+Enter는 보내지 않는다 (줄바꿈)', (tester) async {
      final repo = await pumpChat(tester);

      await tester.enterText(chatInput, '첫 줄');
      await pressShiftEnter(tester);

      expect(repo.sent, isEmpty);
      expect(inputText(tester), '첫 줄');
    }, variant: desktop);

    testWidgets('데스크톱: 비어 있거나 공백뿐이면 Enter로 보내지 않는다', (tester) async {
      final repo = await pumpChat(tester);

      await tester.tap(chatInput);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.enterText(chatInput, '   ');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(repo.sent, isEmpty);
      expect(repo.created, isEmpty);
    }, variant: desktop);

    testWidgets('데스크톱: 답변을 받는 중에는 Enter로 다시 보내지 않는다', (tester) async {
      final repo = FakeChatRepository()..replies = StreamController();
      final replies = repo.replies!;
      await pumpChat(tester, chat: repo);

      await tester.enterText(chatInput, '첫 질문');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.enterText(chatInput, '두 번째');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(repo.sent, ['첫 질문']);
      expect(inputText(tester), '두 번째'); // 입력한 내용은 남아 있다

      replies.add(repo.doneFor('c1', '첫 질문', '답'));
      await replies.close();
      await tester.pumpAndSettle();
    }, variant: desktop);

    testWidgets('데스크톱: 한글 조합 중 Enter는 보내지 않는다', (tester) async {
      final repo = await pumpChat(tester);

      await tester.tap(chatInput);
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '안',
          selection: TextSelection.collapsed(offset: 1),
          composing: TextRange(start: 0, end: 1),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(repo.sent, isEmpty);

      // 조합이 끝난 뒤의 Enter는 보낸다.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '안녕',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(repo.sent, ['안녕']);
    }, variant: desktop);

    /// 입력기(IME)가 보내는 입력 상태 변경을 흉내 낸다.
    Future<void> imeUpdate(
      WidgetTester tester,
      String text, {
      TextRange composing = TextRange.empty,
    }) async {
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
          composing: composing,
        ),
      );
      await tester.pump();
    }

    testWidgets(
      '데스크톱: 한글 조합 중 Enter → 입력기가 줄바꿈을 넣어도 마지막 글자까지 보낸다 (Chrome에서 발견한 문제)',
      (tester) async {
        final repo = await pumpChat(tester);
        await tester.tap(chatInput);
        await tester.pump();

        // '녕'을 조합하는 중에 Enter
        await imeUpdate(
          tester,
          '안녕',
          composing: const TextRange(start: 1, end: 2),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(repo.sent, isEmpty);

        // 입력기가 '녕'을 확정하고 줄바꿈을 넣는다(브라우저 기본 동작)
        await imeUpdate(tester, '안녕\n');
        await tester.pumpAndSettle();

        expect(repo.sent, ['안녕']);
        expect(inputText(tester), isEmpty);
        expect(inBubbles('안녕'), findsOneWidget);

        // 브라우저가 Enter 키 이벤트를 한 번 더 보내도 두 번 보내지 않는다
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(repo.sent, ['안녕']);
      },
      variant: desktop,
    );

    testWidgets('데스크톱: Shift를 누른 채 들어온 줄바꿈은 그대로 둔다', (tester) async {
      final repo = await pumpChat(tester);
      await tester.tap(chatInput);
      await tester.pump();
      await imeUpdate(tester, '첫 줄');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await imeUpdate(tester, '첫 줄\n');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(repo.sent, isEmpty);
      expect(inputText(tester), '첫 줄\n');
    }, variant: desktop);

    testWidgets('데스크톱: 비어 있을 때 들어온 줄바꿈은 지우기만 한다', (tester) async {
      final repo = await pumpChat(tester);
      await tester.tap(chatInput);
      await tester.pump();

      await imeUpdate(tester, '\n');
      await tester.pumpAndSettle();

      expect(repo.sent, isEmpty);
      expect(inputText(tester), isEmpty);
    }, variant: desktop);

    testWidgets('데스크톱: 답변 중에 들어온 줄바꿈은 지우고 보내지 않는다', (tester) async {
      final repo = FakeChatRepository()..replies = StreamController();
      final replies = repo.replies!;
      await pumpChat(tester, chat: repo);

      await sendText(tester, '첫 질문');
      // 보내기 버튼을 터치로 누르면 입력창 포커스가 빠지므로 다시 입력창을 누른다.
      await tester.tap(chatInput);
      await tester.pump();
      await imeUpdate(tester, '두 번째');
      await imeUpdate(tester, '두 번째\n');
      await tester.pump();

      expect(repo.sent, ['첫 질문']);
      expect(inputText(tester), '두 번째');

      replies.add(repo.doneFor('c1', '첫 질문', '답'));
      await replies.close();
      await tester.pumpAndSettle();
    }, variant: desktop);

    testWidgets('데스크톱: 여러 줄 붙여넣기는 보내지 않는다', (tester) async {
      final repo = await pumpChat(tester);
      await tester.tap(chatInput);
      await tester.pump();
      await imeUpdate(tester, '목록:');

      await imeUpdate(tester, '목록:\n- 하나\n- 둘\n');
      await tester.pump();

      expect(repo.sent, isEmpty);
      expect(inputText(tester), '목록:\n- 하나\n- 둘\n');
    }, variant: desktop);

    testWidgets('휴대폰: 키보드가 넣은 줄바꿈은 그대로 둔다', (tester) async {
      final repo = await pumpChat(tester);
      await tester.tap(chatInput);
      await tester.pump();
      await imeUpdate(tester, '한 줄');

      await imeUpdate(tester, '한 줄\n');
      await tester.pump();

      expect(repo.sent, isEmpty);
      expect(inputText(tester), '한 줄\n');
    }, variant: phone);

    testWidgets('휴대폰: Enter는 보내지 않고 보내기 버튼으로만 보낸다', (tester) async {
      final repo = await pumpChat(tester);

      await tester.enterText(chatInput, '모바일 입력');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(repo.sent, isEmpty);
      expect(inputText(tester), '모바일 입력');

      await tester.tap(chatSendButton);
      await tester.pumpAndSettle();
      expect(repo.sent, ['모바일 입력']);
    }, variant: phone);

    testWidgets(
      '입력 안내 문구는 데스크톱에서만 Shift+Enter를 알려 준다',
      (tester) async {
        await pumpChat(tester);
        final isDesktop = defaultTargetPlatform == TargetPlatform.windows;
        expect(
          find.text('뱃속 아기에게 말을 걸어 보세요 (Shift+Enter·Ctrl+Enter 줄바꿈)'),
          isDesktop ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('뱃속 아기에게 말을 걸어 보세요'),
          isDesktop ? findsNothing : findsOneWidget,
        );
      },
      variant: TargetPlatformVariant(const {
        TargetPlatform.windows,
        TargetPlatform.android,
      }),
    );
  });

  group('채팅 화면 크기', () {
    testWidgets('넓은 화면에서는 목록과 대화가 나란히 보인다', (tester) async {
      await pumpChat(tester, size: const Size(1280, 800));

      expect(find.byKey(const Key('newChatButton')), findsOneWidget);
      expect(find.byTooltip('대화 목록'), findsNothing);
      expect(chatInput, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('좁은 화면에서 긴 대화도 깨지지 않는다', (tester) async {
      final longText = '아주 긴 문장입니다. ' * 40;
      final repo = FakeChatRepository(
        conversations: [
          Conversation(
            id: 'old',
            title: '긴 제목 ' * 10,
            createdAt: DateTime(2026, 10, 1),
          ),
        ],
        messages: {
          'old': [
            for (var i = 0; i < 6; i++)
              ChatMessage(
                id: 'm$i',
                conversationId: 'old',
                role: i.isEven ? ChatRole.user : ChatRole.assistant,
                content: longText,
                createdAt: DateTime(2026, 10, 1, 9, i),
              ),
          ],
        },
      );
      await pumpChat(tester, chat: repo, size: const Size(320, 480));

      await openConversationDrawer(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('conversation-old')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(chatInput, findsOneWidget);
    });
  });
}
