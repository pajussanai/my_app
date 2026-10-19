import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_app/models/todo.dart';

import '../helpers/fakes.dart';
import '../helpers/test_helpers.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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

    testWidgets('할 일 화면과 수정 화면이 깨지지 않음', (tester) async {
      useNarrowScreen(tester);
      SharedPreferences.setMockInitialValues({
        'todos': jsonEncode([
          {'id': 'x', 'title': '예전 할 일'},
        ]),
      });
      await pumpSignedIn(
        tester,
        tallScreen: false,
        todos: [
          for (var i = 0; i < 8; i++)
            Todo(
              id: '$i',
              title: '아주 긴 할 일 제목 $i ' * 4,
              done: i.isEven,
              category: TodoCategory.exercise,
              priority: TodoPriority.high,
              dueDate: i < 4 ? DateTime(2000, 12, 31) : DateTime(2999, 12, 31),
            ),
        ],
      );
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(
        inCard('0', find.byTooltip('수정')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(inCard('0', find.byTooltip('수정')));
      await tester.pumpAndSettle();
      await tester.tap(inCard('0', find.byTooltip('수정')));
      await tester.pumpAndSettle();
      expect(find.text('할 일 수정'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
