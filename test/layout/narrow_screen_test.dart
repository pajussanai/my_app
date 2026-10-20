import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_app/models/chat_message.dart';
import 'package:my_app/models/chat_usage.dart';
import 'package:my_app/models/conversation.dart';

import '../helpers/fakes.dart';
import '../helpers/test_helpers.dart';

void main() {
  group('좁은 화면', () {
    void useNarrowScreen(WidgetTester tester) {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('로그인·회원가입·인증 안내 화면이 깨지지 않음', (tester) async {
      useNarrowScreen(tester);
      await pumpSignedOut(tester, FakeAuthService());
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('계정이 없으신가요? 회원가입'));
      await tester.pumpAndSettle();
      await tester.enterText(
        emailInput,
        'a-very-long-email-address@example.com',
      );
      await tester.enterText(passwordInput, 'secret123');
      await tester.enterText(confirmInput, 'secret123');
      await tester.ensureVisible(find.widgetWithText(FilledButton, '회원가입'));
      await tester.tap(find.widgetWithText(FilledButton, '회원가입'));
      await tester.pumpAndSettle();
      expect(find.text('이메일 인증이 필요합니다'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('긴 대화와 대화 목록 서랍(사용량 카드 포함)이 깨지지 않음', (tester) async {
      useNarrowScreen(tester);
      final created = DateTime(2026, 10, 20, 9);
      await pumpSignedIn(
        tester,
        chatRepository:
            FakeChatRepository(
                conversations: [
                  Conversation(
                    id: 'c',
                    title: '아주 긴 대화 제목 ' * 6,
                    createdAt: created,
                  ),
                ],
                messages: {
                  'c': [
                    for (var i = 0; i < 6; i++)
                      ChatMessage(
                        id: 'm$i',
                        conversationId: 'c',
                        role: i.isEven ? ChatRole.user : ChatRole.assistant,
                        content: '엄마아~ 아주 긴 이야기 $i ' * 8,
                        createdAt: created,
                      ),
                  ],
                },
              )
              ..usage = const ChatUsage(
                day: '2026-10-20',
                provider: 'gemini',
                model: 'gemini-3.5-flash-lite',
                aiConfigured: true,
                requestCount: 12345,
                inputTokens: 1234567,
                outputTokens: 765432,
                dailyLimit: 100000,
                remaining: 87655,
              ),
      );
      expect(tester.takeException(), isNull);

      await openConversationDrawer(tester);
      expect(find.byKey(const Key('usageCard')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.textContaining('아주 긴 대화 제목').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('아주 긴 이야기 5'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
