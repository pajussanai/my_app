import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_app/main.dart';
import 'package:my_app/models/todo.dart';

import '../helpers/fakes.dart';
import '../helpers/test_helpers.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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
}
