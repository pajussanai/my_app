import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'package:my_app/models/todo.dart';
import 'package:my_app/services/auth_service.dart';
import 'package:my_app/services/todo_repository.dart';

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
