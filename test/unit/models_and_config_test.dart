import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, PostgrestException;

import 'package:my_app/core/config/supabase_config.dart';
import 'package:my_app/core/errors.dart';
import 'package:my_app/models/todo.dart';
import 'package:my_app/services/todo_repository.dart';

import '../helpers/fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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
