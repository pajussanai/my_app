import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_app/models/todo.dart';

import '../helpers/fakes.dart';
import '../helpers/test_helpers.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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
}
