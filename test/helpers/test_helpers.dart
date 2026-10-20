import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_app/main.dart';
import 'package:my_app/services/auth_service.dart';

import 'fakes.dart';

const testUser = AppUser(id: 'user-1', email: 'me@example.com');

final emailInput = find.byKey(const Key('emailInput'));
final passwordInput = find.byKey(const Key('passwordInput'));
final confirmInput = find.byKey(const Key('confirmInput'));

final chatInput = find.byKey(const Key('chatInput'));
final chatSendButton = find.byKey(const Key('chatSendButton'));

/// 좁은 화면에서 대화 목록 서랍을 연다.
Future<void> openConversationDrawer(WidgetTester tester) async {
  await tester.tap(find.byTooltip('대화 목록'));
  await tester.pumpAndSettle();
}

/// 이미 로그인된 상태(저장된 세션이 있는 상태)로 채팅 화면을 띄운다.
Future<FakeAuthService> pumpSignedIn(
  WidgetTester tester, {
  FakeChatRepository? chatRepository,
}) async {
  final auth = FakeAuthService(user: testUser);
  await tester.pumpWidget(
    MyApp(auth: auth, chatRepository: chatRepository ?? FakeChatRepository()),
  );
  await tester.pumpAndSettle();
  return auth;
}

Future<void> pumpSignedOut(WidgetTester tester, FakeAuthService auth) async {
  await tester.pumpWidget(
    MyApp(auth: auth, chatRepository: FakeChatRepository()),
  );
  await tester.pumpAndSettle();
}
