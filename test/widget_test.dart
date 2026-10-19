import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, PostgrestException;

import 'package:my_app/core/errors.dart';
import 'package:my_app/main.dart';
import 'package:my_app/models/todo.dart';
import 'package:my_app/services/auth_service.dart';
import 'package:my_app/services/todo_repository.dart';
import 'package:my_app/core/config/supabase_config.dart';

const testUser = AppUser(id: 'user-1', email: 'me@example.com');

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

/// 서버 테이블 대신 메모리에 저장하는 저장소.
class FakeTodoRepository implements TodoRepository {
  FakeTodoRepository([List<Todo> initial = const []]) : rows = [...initial];

  /// 서버에 저장된 상태
  final List<Todo> rows;

  Object? fetchError;
  Object? addError;
  Object? updateError;
  Object? deleteError;

  /// true면 서버에는 반영한 뒤 응답만 실패한다(응답 유실 상황).
  bool applyBeforeError = false;

  /// 값이 있으면 완료될 때까지 응답을 미룬다.
  Completer<void>? gate;

  int fetchCount = 0;
  final updates = <Todo>[];
  final added = <Todo>[];

  Future<void> _respond() async {
    if (gate != null) await gate!.future;
  }

  @override
  Future<List<Todo>> fetchTodos() async {
    fetchCount++;
    await _respond();
    if (fetchError != null) throw fetchError!;
    return List.of(rows);
  }

  @override
  Future<Todo> addTodo(Todo todo) async {
    await _respond();
    added.add(todo);
    if (addError != null && !applyBeforeError) throw addError!;
    final saved = todo.copyWith(createdAt: DateTime.utc(2026));
    rows.add(saved);
    if (addError != null) throw addError!;
    return saved;
  }

  @override
  Future<List<Todo>> addTodos(List<Todo> todos) async {
    await _respond();
    added.addAll(todos);
    if (addError != null) throw addError!;
    rows.addAll(todos);
    return todos;
  }

  @override
  Future<Todo> updateTodo(Todo todo) async {
    await _respond();
    updates.add(todo);
    final index = rows.indexWhere((t) => t.id == todo.id);
    if (updateError != null && !applyBeforeError) throw updateError!;
    if (index == -1) throw const TodoNotFoundException();
    rows[index] = todo;
    if (updateError != null) throw updateError!;
    return todo;
  }

  @override
  Future<void> deleteTodo(String id) async {
    await _respond();
    if (deleteError != null) throw deleteError!;
    rows.removeWhere((t) => t.id == id);
  }
}

const permissionDenied = PostgrestException(message: 'denied', code: '42501');

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

  group('서버 데이터', () {
    testWidgets('불러오는 동안 로딩 표시 후 빈 목록 안내', (tester) async {
      final repo = FakeTodoRepository()..gate = Completer();
      await tester.pumpWidget(
        MyApp(
          auth: FakeAuthService(user: testUser),
          repository: repo,
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      repo.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('아직 할 일이 없습니다'), findsOneWidget);
      expect(statValue('진행률', '0%'), findsOneWidget);
    });

    testWidgets('불러오기 실패는 빈 목록과 구분하고 다시 시도할 수 있다', (tester) async {
      final repo = FakeTodoRepository([const Todo(id: '1', title: '서버 할 일')])
        ..fetchError = Exception('offline');
      await pumpSignedIn(tester, repository: repo);

      expect(find.textContaining('할 일을 불러오지 못했습니다'), findsOneWidget);
      expect(find.textContaining('네트워크 연결을 확인'), findsOneWidget);
      expect(find.textContaining('아직 할 일이 없습니다'), findsNothing);
      expect(todoInput, findsNothing);

      repo.fetchError = null;
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();
      expect(find.text('서버 할 일'), findsOneWidget);
    });

    testWidgets('서버에서 불러온 할 일과 완료 상태를 표시', (tester) async {
      await pumpSignedIn(
        tester,
        todos: [
          const Todo(id: '1', title: '운동하기', done: true),
          const Todo(id: '2', title: '책 읽기'),
        ],
      );

      expect(find.text('운동하기'), findsOneWidget);
      expect(find.text('책 읽기'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(statValue('전체', '2'), findsOneWidget);
      expect(statValue('완료', '1'), findsOneWidget);
      expect(statValue('진행률', '50%'), findsOneWidget);
    });

    testWidgets('카테고리·중요도·마감일을 선택해 추가하면 서버에 저장', (tester) async {
      final (_, repo) = await pumpSignedIn(tester);

      await tester.tap(find.byKey(const Key('categoryPicker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('업무').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('priorityPicker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('높음').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('dueDatePicker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      expect(find.text('마감 오늘'), findsOneWidget);

      await tester.enterText(todoInput, '회의 자료 준비');
      await tester.tap(find.text('추가'));
      await tester.pumpAndSettle();

      final saved = repo.rows.single;
      expect(saved.title, '회의 자료 준비');
      expect(saved.category, TodoCategory.work);
      expect(saved.priority, TodoPriority.high);
      expect(isoDate(saved.dueDate!), isoDate(DateTime.now()));
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
          r'[0-9a-f]{12}$',
        ).hasMatch(saved.id),
        isTrue,
      );

      expect(inCard(saved.id, find.text('업무')), findsOneWidget);
      expect(inCard(saved.id, find.text('높음')), findsOneWidget);
      expect(inCard(saved.id, find.text('마감 오늘')), findsOneWidget);

      // 입력창은 비우고, 마감일만 초기화하며 카테고리·중요도는 유지한다.
      expect(find.text('회의 자료 준비'), findsOneWidget);
      expect(find.text('마감일 선택'), findsOneWidget);
      expect(find.text('중요도 높음'), findsOneWidget);

      // 빈 입력은 추가되지 않는다.
      await tester.tap(find.text('추가'));
      await tester.pumpAndSettle();
      expect(repo.rows.length, 1);
    });

    testWidgets('추가 실패 시 화면에 반영하지 않고 입력값을 남긴다', (tester) async {
      final repo = FakeTodoRepository()..addError = permissionDenied;
      await pumpSignedIn(tester, repository: repo);

      await tester.enterText(todoInput, '보고서 작성');
      await tester.tap(find.text('추가'));
      await tester.pumpAndSettle();

      expect(find.textContaining('할 일을 추가하지 못했습니다'), findsOneWidget);
      expect(find.textContaining('아직 할 일이 없습니다'), findsOneWidget);
      expect(statValue('전체', '0'), findsOneWidget);
      final field = tester.widget<TextField>(todoInput);
      expect(field.controller!.text, '보고서 작성');
    });

    testWidgets('응답 대기 중에는 진행 표시를 하고 중복 요청을 막는다', (tester) async {
      final (_, repo) = await pumpSignedIn(
        tester,
        todos: [const Todo(id: '1', title: '우유 사기')],
      );

      repo.gate = Completer();
      await tester.tap(find.text('우유 사기'));
      await tester.pump();
      expect(
        inCard('1', find.byType(CircularProgressIndicator)),
        findsOneWidget,
      );
      // 응답 전에는 아직 완료로 표시하지 않는다.
      expect(find.byIcon(Icons.check_circle), findsNothing);

      await tester.tap(find.text('우유 사기'), warnIfMissed: false);
      await tester.pump();

      repo.gate!.complete();
      await tester.pumpAndSettle();
      expect(repo.updates.length, 1);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(repo.rows.single.done, isTrue);
    });

    testWidgets('완료 전환과 삭제가 서버에 반영된다', (tester) async {
      final (_, repo) = await pumpSignedIn(
        tester,
        todos: [const Todo(id: '1', title: '우유 사기')],
      );

      await tester.tap(find.text('우유 사기'));
      await tester.pumpAndSettle();
      expect(repo.rows.single.done, isTrue);
      final text = tester.widget<Text>(find.text('우유 사기'));
      expect(text.style?.decoration, TextDecoration.lineThrough);
      expect(statValue('진행률', '100%'), findsOneWidget);

      await tester.tap(find.text('우유 사기'));
      await tester.pumpAndSettle();
      expect(repo.rows.single.done, isFalse);
      expect(statValue('진행률', '0%'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(find.text('우유 사기'), findsNothing);
      expect(repo.rows, isEmpty);
    });

    testWidgets('완료 전환·삭제가 거부되면 화면은 그대로 둔다', (tester) async {
      final (_, repo) = await pumpSignedIn(
        tester,
        todos: [const Todo(id: '1', title: '우유 사기')],
      );
      repo
        ..updateError = permissionDenied
        ..deleteError = permissionDenied;

      await tester.tap(find.text('우유 사기'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.textContaining('완료 상태를 바꾸지 못했습니다'), findsOneWidget);
      expect(find.textContaining('권한이 없어'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(find.text('우유 사기'), findsOneWidget);
      expect(find.textContaining('할 일을 삭제하지 못했습니다'), findsOneWidget);
    });

    testWidgets('응답을 받지 못하면 서버 데이터로 다시 맞춘다', (tester) async {
      final (_, repo) = await pumpSignedIn(
        tester,
        todos: [const Todo(id: '1', title: '우유 사기')],
      );
      // 서버에는 반영됐지만 응답이 유실된 상황
      repo
        ..updateError = TimeoutException('no response')
        ..applyBeforeError = true;
      final fetchesBefore = repo.fetchCount;

      await tester.tap(find.text('우유 사기'));
      await tester.pumpAndSettle();

      expect(find.textContaining('네트워크 연결을 확인'), findsOneWidget);
      expect(repo.fetchCount, fetchesBefore + 1);
      expect(repo.rows.single.done, isTrue);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('할 일을 수정하면 서버에 반영된다', (tester) async {
      final (_, repo) = await pumpSignedIn(
        tester,
        todos: [
          const Todo(
            id: '1',
            title: '보고서',
            category: TodoCategory.work,
            dueDate: null,
          ),
        ],
      );

      // 취소하면 아무것도 보내지 않는다.
      await tester.tap(find.byTooltip('수정'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(repo.updates, isEmpty);

      await tester.tap(find.byTooltip('수정'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('editTitleInput')),
        '보고서 최종본',
      );
      await tester.tap(find.byKey(const Key('edit.categoryPicker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('개인').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit.priorityPicker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('낮음').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit.dueDatePicker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      final saved = repo.rows.single;
      expect(saved.title, '보고서 최종본');
      expect(saved.category, TodoCategory.personal);
      expect(saved.priority, TodoPriority.low);
      expect(isoDate(saved.dueDate!), isoDate(DateTime.now()));
      expect(inCard('1', find.text('보고서 최종본')), findsOneWidget);
      expect(inCard('1', find.text('개인')), findsOneWidget);
      expect(inCard('1', find.text('마감 오늘')), findsOneWidget);
    });

    testWidgets('수정 화면에서 마감일을 지울 수 있다', (tester) async {
      final (_, repo) = await pumpSignedIn(
        tester,
        todos: [Todo(id: '1', title: '보고서', dueDate: DateTime(2000))],
      );

      await tester.tap(find.byTooltip('수정'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit.clearDueDate')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(repo.rows.single.dueDate, isNull);
      expect(inCard('1', find.textContaining('기한 지남')), findsNothing);
    });

    testWidgets('수정 실패 시 이전 내용을 유지한다', (tester) async {
      final (_, repo) = await pumpSignedIn(
        tester,
        todos: [const Todo(id: '1', title: '보고서')],
      );
      repo.updateError = permissionDenied;

      await tester.tap(find.byTooltip('수정'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('editTitleInput')), '새 제목');
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(find.text('보고서'), findsOneWidget);
      expect(find.text('새 제목'), findsNothing);
      expect(find.textContaining('할 일을 수정하지 못했습니다'), findsOneWidget);
    });

    testWidgets('마감일이 지난 미완료 항목만 기한 지남으로 표시', (tester) async {
      await pumpSignedIn(
        tester,
        todos: [
          Todo(id: 'late', title: '지난 일', dueDate: DateTime(2000)),
          Todo(
            id: 'doneLate',
            title: '끝낸 일',
            done: true,
            dueDate: DateTime(2000),
          ),
          Todo(id: 'future', title: '다음 일', dueDate: DateTime(2999, 12, 31)),
          Todo(id: 'today', title: '오늘 일', dueDate: DateTime.now()),
        ],
      );

      expect(inCard('late', find.textContaining('기한 지남')), findsOneWidget);
      expect(inCard('doneLate', find.textContaining('기한 지남')), findsNothing);
      expect(inCard('future', find.textContaining('기한 지남')), findsNothing);
      expect(inCard('future', find.text('마감 2999년 12월 31일')), findsOneWidget);
      expect(inCard('today', find.text('마감 오늘')), findsOneWidget);
    });

    testWidgets('검색·상태·카테고리 필터를 함께 적용', (tester) async {
      await pumpSignedIn(
        tester,
        todos: const [
          Todo(id: '1', title: '보고서 작성', category: TodoCategory.work),
          Todo(
            id: '2',
            title: '보고서 검토',
            category: TodoCategory.work,
            done: true,
          ),
          Todo(id: '3', title: '헬스장 가기', category: TodoCategory.exercise),
          Todo(id: '4', title: '개인 보고서', category: TodoCategory.personal),
        ],
      );

      bool shown(String id) => find.byKey(ValueKey(id)).evaluate().isNotEmpty;
      List<String> visible() => ['1', '2', '3', '4'].where(shown).toList();

      expect(visible(), ['1', '2', '3', '4']);

      await tester.enterText(searchInput, '보고서');
      await tester.pumpAndSettle();
      expect(visible(), ['1', '2', '4']);

      await tester.tap(find.widgetWithText(ChoiceChip, '업무'));
      await tester.pumpAndSettle();
      expect(visible(), ['1', '2']);

      await tester.tap(find.widgetWithText(ChoiceChip, '진행 중'));
      await tester.pumpAndSettle();
      expect(visible(), ['1']);

      await tester.tap(find.widgetWithText(ChoiceChip, '완료'));
      await tester.pumpAndSettle();
      expect(visible(), ['2']);

      await tester.enterText(searchInput, '없는 제목');
      await tester.pumpAndSettle();
      expect(visible(), isEmpty);
      expect(find.textContaining('조건에 맞는 할 일이 없습니다'), findsOneWidget);

      await tester.tap(find.byTooltip('검색어 지우기'));
      await tester.tap(find.widgetWithText(ChoiceChip, '전체'));
      await tester.tap(find.widgetWithText(ChoiceChip, '모든 카테고리'));
      await tester.pumpAndSettle();
      expect(visible(), ['1', '2', '3', '4']);
      expect(statValue('전체', '4'), findsOneWidget);
    });

    testWidgets('필터에 가려지는 항목을 추가하면 안내한다', (tester) async {
      final (_, repo) = await pumpSignedIn(
        tester,
        todos: const [Todo(id: '1', title: '운동하기')],
      );

      await tester.tap(find.widgetWithText(ChoiceChip, '완료'));
      await tester.pumpAndSettle();

      await tester.enterText(todoInput, '새 할 일');
      await tester.tap(find.text('추가'));
      await tester.pumpAndSettle();

      expect(find.textContaining('현재 검색·필터 조건에 맞지 않아'), findsOneWidget);
      expect(repo.rows.length, 2);
    });
  });

  group('이전 로컬 데이터', () {
    void setLegacy(Object value) => SharedPreferences.setMockInitialValues({
      'todos': value is String ? value : jsonEncode(value),
    });

    testWidgets('자동으로 옮기지 않고, 가져오기를 누르면 서버에 저장', (tester) async {
      setLegacy([
        {'id': '1', 'title': '예전 할 일', 'done': true},
        {
          'id': '2',
          'title': '예전 업무',
          'category': 'work',
          'dueDate': '2026-12-01',
        },
      ]);
      final (_, repo) = await pumpSignedIn(tester);

      expect(find.byKey(const Key('legacyBanner')), findsOneWidget);
      expect(find.textContaining('2개'), findsOneWidget);
      expect(repo.added, isEmpty);

      await tester.tap(find.text('서버로 가져오기'));
      await tester.pumpAndSettle();

      expect(repo.rows.map((t) => t.title), ['예전 할 일', '예전 업무']);
      expect(repo.rows.first.done, isTrue);
      expect(repo.rows.last.category, TodoCategory.work);
      expect(repo.rows.last.dueDate, DateTime(2026, 12, 1));
      expect(repo.rows.map((t) => t.id).toSet(), isNot(contains('1')));
      expect(find.byKey(const Key('legacyBanner')), findsNothing);
      expect(find.text('예전 할 일'), findsOneWidget);
      expect(find.textContaining('2개를 서버로 가져왔습니다'), findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('todos'), isNull);
    });

    testWidgets('가져오기 실패 시 로컬 데이터를 지우지 않는다', (tester) async {
      setLegacy([
        {'id': '1', 'title': '예전 할 일'},
      ]);
      final repo = FakeTodoRepository()..addError = permissionDenied;
      await pumpSignedIn(tester, repository: repo);

      await tester.tap(find.text('서버로 가져오기'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('legacyBanner')), findsOneWidget);
      expect(find.textContaining('이전 할 일을 가져오지 못했습니다'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('todos'), isNotNull);
    });

    testWidgets('나중에를 누르면 안내를 숨기고 데이터는 남긴다', (tester) async {
      setLegacy([
        {'id': '1', 'title': '예전 할 일'},
      ]);
      await pumpSignedIn(tester);

      await tester.tap(find.text('나중에'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('legacyBanner')), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('todos'), isNotNull);
    });

    testWidgets('손상된 로컬 데이터는 안내하지 않는다', (tester) async {
      setLegacy('not json');
      await pumpSignedIn(tester);

      expect(find.byKey(const Key('legacyBanner')), findsNothing);
    });
  });

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

  group('데이터 변환과 설정', () {
    test('서버 행을 읽을 때 빈 값·알 수 없는 값은 기본값으로', () {
      final todo = Todo.fromRow({
        'id': 'a',
        'user_id': 'u',
        'title': '할 일',
        'category': null,
        'priority': 'unknown',
        'due_date': null,
        'is_completed': null,
        'created_at': '2026-10-19T01:02:03.000000+00:00',
      });
      expect(todo.category, TodoCategory.other);
      expect(todo.priority, TodoPriority.medium);
      expect(todo.dueDate, isNull);
      expect(todo.done, isFalse);
      expect(todo.createdAt, DateTime.utc(2026, 10, 19, 1, 2, 3));
    });

    test('한국어 값으로 저장된 카테고리·중요도도 읽는다', () {
      final todo = Todo.fromRow({
        'id': 'a',
        'title': '운동',
        'category': '운동',
        'priority': '높음',
        'due_date': '2026-10-25',
        'is_completed': true,
      });
      expect(todo.category, TodoCategory.exercise);
      expect(todo.priority, TodoPriority.high);
      expect(todo.dueDate, DateTime(2026, 10, 25));
      expect(todo.done, isTrue);
    });

    test('서버에 보내는 값', () {
      final todo = Todo(
        id: 'a',
        title: '보고서',
        category: TodoCategory.work,
        priority: TodoPriority.low,
        dueDate: DateTime(2026, 1, 5),
        done: true,
      );
      expect(todo.toRow(userId: 'u'), {
        'id': 'a',
        'user_id': 'u',
        'title': '보고서',
        'category': 'work',
        'priority': 'low',
        'due_date': '2026-01-05',
        'is_completed': true,
      });
      expect(const Todo(id: 'b', title: 't').toRow(), {
        'id': 'b',
        'title': 't',
        'category': 'other',
        'priority': 'medium',
        'due_date': null,
        'is_completed': false,
      });
    });

    test('newTodoId는 UUID v4 형식이고 매번 다르다', () {
      final pattern = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      final ids = {for (var i = 0; i < 100; i++) newTodoId()};
      expect(ids.length, 100);
      expect(ids.every(pattern.hasMatch), isTrue);
    });

    test('publishable 키만 허용하고 secret·service_role 키는 거부', () {
      const url = 'https://example.supabase.co';
      expect(
        () =>
            checkSupabaseConfig(url: supabaseUrl, key: supabasePublishableKey),
        returnsNormally,
      );
      expect(
        () => checkSupabaseConfig(url: url, key: 'sb_secret_abc'),
        throwsStateError,
      );
      String jwt(Map<String, dynamic> payload) =>
          'eyJhbGciOiJIUzI1NiJ9.'
          '${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}'
          '.sig';
      expect(
        () => checkSupabaseConfig(url: url, key: jwt({'role': 'service_role'})),
        throwsStateError,
      );
      expect(
        () => checkSupabaseConfig(url: url, key: jwt({'role': 'anon'})),
        returnsNormally,
      );
      expect(
        () => checkSupabaseConfig(
          url: 'http://example.com',
          key: 'sb_publishable_x',
        ),
        throwsStateError,
      );
      expect(supabasePublishableKey, startsWith('sb_publishable_'));
    });

    test('오류 문구에 서버 원문을 노출하지 않는다', () {
      expect(
        describeError(
          const AuthException(
            'Invalid login credentials',
            code: 'invalid_credentials',
          ),
        ),
        '이메일 또는 비밀번호가 올바르지 않습니다.',
      );
      expect(
        describeError(
          const PostgrestException(message: 'JWT expired', code: 'PGRST301'),
        ),
        '로그인이 만료되었습니다. 다시 로그인해 주세요.',
      );
      expect(describeError(permissionDenied), '권한이 없어 처리할 수 없습니다.');
      expect(describeError(TimeoutException('x')), contains('네트워크'));
    });
  });
}
