part of 'main.dart';

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

/// 서버 연결 전 버전이 이 브라우저(기기)의 shared_preferences에 남긴 할 일.
///
/// 자동으로 서버에 올리지 않는다. 사용자가 가져오기를 선택했을 때만 사용한다.
class LegacyLocalTodos {
  static const _key = 'todos';

  Future<List<Todo>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => Todo.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // 형식이 깨진 데이터는 가져올 수 없으므로 없는 것으로 본다.
      debugPrint('이전 로컬 할 일 데이터를 읽을 수 없습니다: ${e.runtimeType}');
      return [];
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
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

/// 서버가 요청을 처리했는지 알 수 없는 오류인지 판단한다.
///
/// 네트워크 오류나 시간 초과는 서버에는 반영됐을 수 있으므로,
/// 화면을 서버 데이터로 다시 맞춰야 한다.
bool _isUncertainFailure(Object error) =>
    error is! PostgrestException && error is! AuthApiException;

/// 사용자에게 보여 줄 오류 문구. 서버 원문이나 토큰은 노출하지 않는다.
String describeError(Object error) {
  const network = '네트워크 연결을 확인하고 다시 시도해 주세요.';
  const relogin = '로그인이 만료되었습니다. 다시 로그인해 주세요.';

  if (error is TodoNotFoundException) {
    return '이미 삭제되었거나 접근할 수 없는 할 일입니다.';
  }
  if (error is AuthException) {
    if (error is AuthRetryableFetchException) return network;
    return switch (error.code) {
      'invalid_credentials' => '이메일 또는 비밀번호가 올바르지 않습니다.',
      'email_not_confirmed' => '이메일 인증이 아직 완료되지 않았습니다.',
      'user_already_exists' || 'email_exists' => '이미 가입된 이메일입니다.',
      'weak_password' => '비밀번호가 너무 약합니다. 더 길고 복잡하게 입력해 주세요.',
      'email_address_invalid' => '사용할 수 없는 이메일 주소입니다.',
      'over_email_send_rate_limit' ||
      'over_request_rate_limit' => '요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.',
      'signup_disabled' || 'email_provider_disabled' => '현재 회원가입을 할 수 없습니다.',
      'session_missing' ||
      'session_expired' ||
      'session_not_found' ||
      'refresh_token_not_found' ||
      'bad_jwt' => relogin,
      _ => '인증 중 문제가 발생했습니다. 잠시 후 다시 시도해 주세요.',
    };
  }
  if (error is PostgrestException) {
    return switch (error.code) {
      'PGRST301' || 'PGRST303' => relogin,
      '42501' => '권한이 없어 처리할 수 없습니다.',
      '23514' || '22P02' || '23502' => '서버에서 허용하지 않는 값이 있습니다.',
      '23505' => '이미 저장된 할 일입니다.',
      '42P01' || 'PGRST205' => '서버에서 todos 테이블을 찾을 수 없습니다.',
      _ => '서버에서 요청을 처리하지 못했습니다.',
    };
  }
  return network;
}

/// 디버깅용 로그. 비밀번호·토큰이 섞이지 않도록 오류 종류와 코드만 남긴다.
void _logError(String context, Object error) {
  final code = switch (error) {
    AuthException(:final code) => code,
    PostgrestException(:final code) => code,
    _ => null,
  };
  debugPrint('$context: ${error.runtimeType}${code == null ? '' : ' ($code)'}');
}
