import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_app/main.dart';
import 'package:my_app/models/todo.dart';
import 'package:my_app/services/auth_service.dart';

import 'fakes.dart';

const testUser = AppUser(id: 'user-1', email: 'me@example.com');

/// 요약 카드의 특정 항목(전체/완료/진행률) 값을 찾는다.
Finder statValue(String label, String value) => find.descendant(
  of: find
      .ancestor(
        of: find.descendant(
          of: find.byKey(const Key('summary')),
          matching: find.text(label),
        ),
        matching: find.byType(Column),
      )
      .first,
  matching: find.text(value),
);

final todoInput = find.byKey(const Key('todoInput'));
final searchInput = find.byKey(const Key('searchInput'));
final emailInput = find.byKey(const Key('emailInput'));
final passwordInput = find.byKey(const Key('passwordInput'));
final confirmInput = find.byKey(const Key('confirmInput'));

/// 특정 할 일 카드 안에서 위젯을 찾는다.
Finder inCard(String id, Finder finder) =>
    find.descendant(of: find.byKey(ValueKey(id)), matching: finder);

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// 목록은 지연 생성되므로, 여러 카드를 한 번에 확인할 때 화면 높이를 키운다.
void useTallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// 이미 로그인된 상태(저장된 세션이 있는 상태)로 앱을 띄운다.
Future<(FakeAuthService, FakeTodoRepository)> pumpSignedIn(
  WidgetTester tester, {
  List<Todo> todos = const [],
  FakeTodoRepository? repository,
  bool tallScreen = true,
}) async {
  if (tallScreen) useTallScreen(tester);
  final auth = FakeAuthService(user: testUser);
  final repo = repository ?? FakeTodoRepository(todos);
  await tester.pumpWidget(MyApp(auth: auth, repository: repo));
  await tester.pumpAndSettle();
  return (auth, repo);
}

Future<void> pumpSignedOut(WidgetTester tester, FakeAuthService auth) async {
  await tester.pumpWidget(MyApp(auth: auth, repository: FakeTodoRepository()));
  await tester.pumpAndSettle();
}
