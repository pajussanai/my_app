import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import 'package:my_app/main.dart';
import 'package:my_app/models/todo.dart';
import 'package:my_app/services/auth_service.dart';

import '../helpers/fakes.dart';
import '../helpers/test_helpers.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('인증', () {
    testWidgets('로그인하지 않으면 할 일 화면에 들어갈 수 없다', (tester) async {
      final repo = FakeTodoRepository([const Todo(id: '1', title: '비밀 할 일')]);
      await tester.pumpWidget(MyApp(auth: FakeAuthService(), repository: repo));
      await tester.pumpAndSettle();

      expect(emailInput, findsOneWidget);
      expect(find.widgetWithText(FilledButton, '로그인'), findsOneWidget);
      expect(todoInput, findsNothing);
      expect(find.text('비밀 할 일'), findsNothing);
      expect(repo.fetchCount, 0);
    });

    testWidgets('저장된 세션이 있으면 바로 할 일 화면을 보여 준다', (tester) async {
      await pumpSignedIn(tester);

      expect(todoInput, findsOneWidget);
      expect(find.text('me@example.com'), findsOneWidget);
    });

    testWidgets('로그인 성공 시 할 일 화면으로 이동', (tester) async {
      final auth = FakeAuthService();
      await pumpSignedOut(tester, auth);

      await tester.enterText(emailInput, ' me@example.com ');
      await tester.enterText(passwordInput, 'secret123');
      await tester.tap(find.widgetWithText(FilledButton, '로그인'));
      await tester.pumpAndSettle();

      expect(auth.calls, ['signIn:me@example.com']);
      expect(todoInput, findsOneWidget);
    });

    testWidgets('잘못된 비밀번호면 오류를 보여 주고 로그인 화면에 머문다', (tester) async {
      final auth = FakeAuthService()
        ..signInError = const AuthException(
          'Invalid login credentials',
          statusCode: '400',
          code: 'invalid_credentials',
        );
      await pumpSignedOut(tester, auth);

      await tester.enterText(emailInput, 'me@example.com');
      await tester.enterText(passwordInput, 'wrong');
      await tester.tap(find.widgetWithText(FilledButton, '로그인'));
      await tester.pumpAndSettle();

      expect(find.text('이메일 또는 비밀번호가 올바르지 않습니다.'), findsOneWidget);
      expect(todoInput, findsNothing);
    });

    testWidgets('입력값이 올바르지 않으면 요청하지 않는다', (tester) async {
      final auth = FakeAuthService();
      await pumpSignedOut(tester, auth);

      await tester.tap(find.text('계정이 없으신가요? 회원가입'));
      await tester.pumpAndSettle();

      await tester.enterText(emailInput, 'not-an-email');
      await tester.enterText(passwordInput, '123');
      await tester.enterText(confirmInput, '456');
      await tester.tap(find.widgetWithText(FilledButton, '회원가입'));
      await tester.pumpAndSettle();

      expect(find.text('올바른 이메일 형식이 아닙니다.'), findsOneWidget);
      expect(find.text('비밀번호는 6자 이상이어야 합니다.'), findsOneWidget);
      expect(find.text('비밀번호가 일치하지 않습니다.'), findsOneWidget);
      expect(auth.calls, isEmpty);
    });

    testWidgets('회원가입 후 이메일 인증 안내와 재발송', (tester) async {
      final auth = FakeAuthService();
      await pumpSignedOut(tester, auth);

      await tester.tap(find.text('계정이 없으신가요? 회원가입'));
      await tester.pumpAndSettle();
      await tester.enterText(emailInput, 'new@example.com');
      await tester.enterText(passwordInput, 'secret123');
      await tester.enterText(confirmInput, 'secret123');
      await tester.tap(find.widgetWithText(FilledButton, '회원가입'));
      await tester.pumpAndSettle();

      expect(find.text('이메일 인증이 필요합니다'), findsOneWidget);
      expect(find.textContaining('new@example.com'), findsOneWidget);
      expect(todoInput, findsNothing);

      await tester.tap(find.text('인증 메일 다시 보내기'));
      await tester.pumpAndSettle();
      expect(find.text('인증 메일을 다시 보냈습니다.'), findsOneWidget);
      expect(auth.calls.last, 'resend:new@example.com');

      await tester.tap(find.text('로그인 화면으로'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, '로그인'), findsOneWidget);
      // 비밀번호는 남겨 두지 않는다.
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: passwordInput,
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        isEmpty,
      );
    });

    testWidgets('인증 메일 없이 바로 로그인되는 설정이면 할 일 화면으로 이동', (tester) async {
      final auth = FakeAuthService()..signUpOutcome = SignUpOutcome.signedIn;
      await pumpSignedOut(tester, auth);

      await tester.tap(find.text('계정이 없으신가요? 회원가입'));
      await tester.pumpAndSettle();
      await tester.enterText(emailInput, 'new@example.com');
      await tester.enterText(passwordInput, 'secret123');
      await tester.enterText(confirmInput, 'secret123');
      await tester.tap(find.widgetWithText(FilledButton, '회원가입'));
      await tester.pumpAndSettle();

      expect(todoInput, findsOneWidget);
    });

    testWidgets('인증하지 않은 이메일로 로그인하면 인증 안내 화면', (tester) async {
      final auth = FakeAuthService()
        ..signInError = const AuthException(
          'Email not confirmed',
          statusCode: '400',
          code: 'email_not_confirmed',
        );
      await pumpSignedOut(tester, auth);

      await tester.enterText(emailInput, 'me@example.com');
      await tester.enterText(passwordInput, 'secret123');
      await tester.tap(find.widgetWithText(FilledButton, '로그인'));
      await tester.pumpAndSettle();

      expect(find.text('이메일 인증이 필요합니다'), findsOneWidget);
    });

    testWidgets('로그아웃하면 로그인 화면으로 돌아간다', (tester) async {
      final (auth, _) = await pumpSignedIn(
        tester,
        todos: [const Todo(id: '1', title: '할 일')],
      );

      await tester.tap(find.byTooltip('로그아웃'));
      await tester.pumpAndSettle();

      expect(auth.calls, ['signOut']);
      expect(emailInput, findsOneWidget);
      expect(find.text('할 일'), findsNothing);
    });
  });
}
