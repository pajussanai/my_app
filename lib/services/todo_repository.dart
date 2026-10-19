import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/todo.dart';

/// 할 일을 서버에 저장하고 불러오는 저장소.
///
/// 모든 메서드는 서버가 성공 응답을 준 경우에만 값을 돌려주고,
/// 실패하면 예외를 던진다. 화면은 성공한 결과만 반영한다.
abstract class TodoRepository {
  Future<List<Todo>> fetchTodos();

  /// 저장된 행을 돌려준다. [todo]의 id를 그대로 사용한다.
  Future<Todo> addTodo(Todo todo);

  /// 여러 개를 한 번에 추가한다. 전부 성공하거나 전부 실패한다.
  Future<List<Todo>> addTodos(List<Todo> todos);

  /// 수정된 행을 돌려준다. 대상이 없으면 [TodoNotFoundException]을 던진다.
  Future<Todo> updateTodo(Todo todo);

  Future<void> deleteTodo(String id);
}

/// 수정하려는 할 일이 서버에 없거나 접근 권한이 없을 때.
class TodoNotFoundException implements Exception {
  const TodoNotFoundException();
}

/// Supabase public.todos 테이블을 사용하는 저장소.
///
/// 사용자별 접근 제한은 RLS 정책(auth.uid() = user_id)이 보장한다.
/// 여기서도 user_id 조건을 함께 걸어 의도를 분명히 한다.
class SupabaseTodoRepository implements TodoRepository {
  SupabaseTodoRepository(this._client);

  final SupabaseClient _client;

  static const _table = 'todos';
  static const _columns =
      'id, user_id, title, category, priority, due_date, is_completed, created_at';

  // 응답이 오지 않는 요청을 무한정 기다리지 않는다.
  static const _timeout = Duration(seconds: 15);

  String get _userId {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다.', code: 'session_missing');
    }
    return user.id;
  }

  @override
  Future<List<Todo>> fetchTodos() async {
    final rows = await _client
        .from(_table)
        .select(_columns)
        .eq('user_id', _userId)
        .order('created_at', ascending: true)
        .order('id', ascending: true)
        .timeout(_timeout);
    return rows.map(Todo.fromRow).toList();
  }

  @override
  Future<Todo> addTodo(Todo todo) async {
    final row = await _client
        .from(_table)
        .insert(todo.toRow(userId: _userId))
        .select(_columns)
        .single()
        .timeout(_timeout);
    return Todo.fromRow(row);
  }

  @override
  Future<List<Todo>> addTodos(List<Todo> todos) async {
    if (todos.isEmpty) return [];
    final userId = _userId;
    final rows = await _client
        .from(_table)
        .insert([for (final todo in todos) todo.toRow(userId: userId)])
        .select(_columns)
        .order('created_at', ascending: true)
        .timeout(_timeout);
    return rows.map(Todo.fromRow).toList();
  }

  @override
  Future<Todo> updateTodo(Todo todo) async {
    // id, user_id, created_at은 바꾸지 않는다.
    final row = await _client
        .from(_table)
        .update(todo.toRow()..removeWhere((key, _) => !_editable.contains(key)))
        .eq('id', todo.id)
        .eq('user_id', _userId)
        .select(_columns)
        .maybeSingle()
        .timeout(_timeout);
    if (row == null) throw const TodoNotFoundException();
    return Todo.fromRow(row);
  }

  static const _editable = {
    'title',
    'category',
    'priority',
    'due_date',
    'is_completed',
  };

  @override
  Future<void> deleteTodo(String id) async {
    // 이미 삭제된 항목이면 서버에서도 없는 상태이므로 성공으로 본다.
    await _client
        .from(_table)
        .delete()
        .eq('id', id)
        .eq('user_id', _userId)
        .timeout(_timeout);
  }
}

/// 서버에 보낼 할 일 id(UUID v4)를 만든다.
///
/// id를 앱에서 정하면 응답을 받지 못한 요청을 다시 보내도 중복으로 생기지 않는다.
String newTodoId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
