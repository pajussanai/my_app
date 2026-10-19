import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../models/todo.dart';
import '../../services/auth_service.dart';
import '../../services/legacy_local_todos.dart';
import '../../services/todo_repository.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/status_view.dart';
import 'widgets/edit_todo_dialog.dart';
import 'widgets/legacy_import_banner.dart';
import 'widgets/summary_card.dart';
import 'widgets/todo_card.dart';
import 'widgets/todo_filters.dart';
import 'widgets/todo_header.dart';
import 'widgets/todo_input_card.dart';

class TodoPage extends StatefulWidget {
  const TodoPage({
    super.key,
    required this.user,
    required this.auth,
    required this.repository,
  });

  final AppUser user;
  final AuthService auth;
  final TodoRepository repository;

  @override
  State<TodoPage> createState() => _TodoPageState();
}

enum _LoadState { loading, ready, error }

class _TodoPageState extends State<TodoPage> {
  List<Todo> _todos = [];
  _LoadState _loadState = _LoadState.loading;
  String? _loadError;
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  // 새 할 일에 적용할 옵션
  TodoCategory _newCategory = TodoCategory.other;
  TodoPriority _newPriority = TodoPriority.medium;
  DateTime? _newDueDate;

  // 목록 필터 (null이면 모든 카테고리)
  TodoStatusFilter _statusFilter = TodoStatusFilter.all;
  TodoCategory? _categoryFilter;

  // 서버 응답을 기다리는 중인 할 일(중복 요청을 막는다)
  final Set<String> _busyIds = {};
  bool _adding = false;
  bool _signingOut = false;

  // 서버 연결 전 버전이 이 기기에 남긴 할 일. id는 가져오기 재시도 시
  // 중복 저장을 막기 위해 미리 한 번만 만든다.
  List<Todo> _legacyTodos = [];
  bool _legacyHidden = false;
  bool _importing = false;

  int get _doneCount => _todos.where((todo) => todo.done).length;

  List<Todo> get _visibleTodos => _todos.where(_matchesFilters).toList();

  bool _matchesFilters(Todo todo) {
    final statusMatches = switch (_statusFilter) {
      TodoStatusFilter.all => true,
      TodoStatusFilter.active => !todo.done,
      TodoStatusFilter.done => todo.done,
    };
    final query = _searchController.text.trim().toLowerCase();
    return statusMatches &&
        (_categoryFilter == null || todo.category == _categoryFilter) &&
        (query.isEmpty || todo.title.toLowerCase().contains(query));
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _loadTodos();
    _checkLegacyTodos();
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTodos() async {
    if (_loadState != _LoadState.loading) {
      setState(() {
        _loadState = _LoadState.loading;
        _loadError = null;
      });
    }
    try {
      final loaded = await widget.repository.fetchTodos();
      if (!mounted) return;
      setState(() {
        _todos = loaded;
        _loadState = _LoadState.ready;
      });
    } catch (e) {
      logError('할 일 불러오기 실패', e);
      if (!mounted) return;
      setState(() {
        _loadState = _LoadState.error;
        _loadError = describeError(e);
      });
    }
  }

  /// 결과를 알 수 없는 실패 뒤에 화면을 서버 데이터로 다시 맞춘다.
  /// 실패하면 지금 화면을 그대로 둔다.
  Future<void> _resync() async {
    try {
      final loaded = await widget.repository.fetchTodos();
      if (mounted) setState(() => _todos = loaded);
    } catch (e) {
      logError('할 일 다시 맞추기 실패', e);
    }
  }

  Future<void> _checkLegacyTodos() async {
    try {
      final legacy = await LegacyLocalTodos().load();
      if (!mounted || legacy.isEmpty) return;
      setState(() {
        _legacyTodos = [
          for (final todo in legacy) todo.copyWith(id: newTodoId()),
        ];
      });
    } catch (e) {
      logError('이전 로컬 할 일 확인 실패', e);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 서버 요청이 성공했을 때만 [onSuccess]로 화면을 바꾼다.
  /// 실패하면 화면은 그대로 두고 오류를 알린다.
  Future<bool> _sync<T>(
    Future<T> Function() request, {
    required String failure,
    required void Function(T result) onSuccess,
  }) async {
    try {
      final result = await request();
      if (mounted) setState(() => onSuccess(result));
      return true;
    } catch (e) {
      logError(failure, e);
      if (!mounted) return false;
      _showMessage('$failure ${describeError(e)}');
      if (isUncertainFailure(e)) unawaited(_resync());
      return false;
    }
  }

  /// 같은 할 일에 요청이 겹치지 않도록 응답이 올 때까지 잠근다.
  Future<void> _whileBusy(String id, Future<void> Function() action) async {
    if (_busyIds.contains(id)) return;
    setState(() => _busyIds.add(id));
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
  }

  void _replaceTodo(Todo saved) {
    _todos = [for (final t in _todos) t.id == saved.id ? saved : t];
  }

  Future<void> _addTodo() async {
    final title = _controller.text.trim();
    if (title.isEmpty || _adding) return;
    final draft = Todo(
      id: newTodoId(),
      title: title,
      category: _newCategory,
      priority: _newPriority,
      dueDate: _newDueDate,
    );

    setState(() => _adding = true);
    final ok = await _sync(
      () => widget.repository.addTodo(draft),
      failure: '할 일을 추가하지 못했습니다.',
      onSuccess: (saved) {
        // 카테고리·중요도는 연속 입력을 위해 유지하고 마감일만 초기화한다.
        _todos = [..._todos, saved];
        _newDueDate = null;
      },
    );
    if (!mounted) return;
    setState(() => _adding = false);
    // 실패하면 입력한 제목을 남겨 다시 시도할 수 있게 한다.
    if (!ok) return;
    _controller.clear();
    if (!_matchesFilters(draft)) {
      _showMessage('추가한 할 일이 현재 검색·필터 조건에 맞지 않아 보이지 않습니다.');
    }
  }

  Future<void> _toggleTodo(Todo todo) => _whileBusy(
    todo.id,
    () => _sync(
      () => widget.repository.updateTodo(todo.copyWith(done: !todo.done)),
      failure: '완료 상태를 바꾸지 못했습니다.',
      onSuccess: _replaceTodo,
    ),
  );

  Future<void> _editTodo(Todo todo) async {
    final edited = await showDialog<Todo>(
      context: context,
      builder: (_) => EditTodoDialog(todo: todo),
    );
    if (edited == null || !mounted) return;
    await _whileBusy(
      todo.id,
      () => _sync(
        () => widget.repository.updateTodo(edited),
        failure: '할 일을 수정하지 못했습니다.',
        onSuccess: _replaceTodo,
      ),
    );
  }

  Future<void> _removeTodo(Todo todo) => _whileBusy(
    todo.id,
    () => _sync(
      () => widget.repository.deleteTodo(todo.id),
      failure: '할 일을 삭제하지 못했습니다.',
      onSuccess: (_) => _todos = _todos.where((t) => t.id != todo.id).toList(),
    ),
  );

  Future<void> _importLegacyTodos() async {
    if (_importing) return;
    final drafts = _legacyTodos;
    final base = DateTime.now().toUtc();
    setState(() => _importing = true);
    try {
      // 기존 순서를 유지하도록 생성 시각을 조금씩 다르게 준다.
      final saved = await widget.repository.addTodos([
        for (var i = 0; i < drafts.length; i++)
          drafts[i].copyWith(createdAt: base.add(Duration(milliseconds: i))),
      ]);
      await _finishImport(saved, drafts.length);
    } on PostgrestException catch (e) {
      // 같은 id가 이미 있으면, 응답을 못 받았던 이전 시도가 성공한 것이다.
      // 한 번에 추가하므로 일부만 저장되는 경우는 없다.
      if (e.code == '23505') {
        await _finishImport(null, drafts.length);
      } else {
        _failImport(e);
      }
    } catch (e) {
      _failImport(e);
      unawaited(_resync());
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _finishImport(List<Todo>? saved, int count) async {
    try {
      await LegacyLocalTodos().clear();
    } catch (e) {
      logError('이전 로컬 할 일 정리 실패', e);
    }
    if (!mounted) return;
    setState(() {
      if (saved != null) _todos = [..._todos, ...saved];
      _legacyTodos = [];
    });
    if (saved == null) unawaited(_resync());
    _showMessage('이전 할 일 $count개를 서버로 가져왔습니다.');
  }

  void _failImport(Object error) {
    logError('이전 할 일 가져오기 실패', error);
    if (mounted) {
      _showMessage('이전 할 일을 가져오지 못했습니다. ${describeError(error)}');
    }
  }

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      // 성공하면 AuthGate가 로그인 화면으로 바꾼다.
      await widget.auth.signOut();
    } catch (e) {
      logError('로그아웃 실패', e);
      if (mounted) _showMessage('로그아웃하지 못했습니다. ${describeError(e)}');
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: _buildContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          sliver: SliverToBoxAdapter(
            child: TodoHeader(
              email: widget.user.email,
              onRefresh: _loadState == _LoadState.loading ? null : _loadTodos,
              onSignOut: _signingOut ? null : _signOut,
            ),
          ),
        ),
        ...switch (_loadState) {
          _LoadState.loading => [
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
          _LoadState.error => [
            SliverFillRemaining(
              hasScrollBody: false,
              child: StatusView(
                icon: Icons.cloud_off_outlined,
                message: '할 일을 불러오지 못했습니다.\n$_loadError',
                actionLabel: '다시 시도',
                onAction: _loadTodos,
              ),
            ),
          ],
          _LoadState.ready => _buildReadySlivers(),
        },
      ],
    );
  }

  List<Widget> _buildReadySlivers() {
    final visible = _visibleTodos;

    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverList.list(
          children: [
            if (_legacyTodos.isNotEmpty && !_legacyHidden) ...[
              LegacyImportBanner(
                count: _legacyTodos.length,
                importing: _importing,
                onDismiss: () => setState(() => _legacyHidden = true),
                onImport: _importLegacyTodos,
              ),
              const SizedBox(height: 16),
            ],
            SummaryCard(
              key: const Key('summary'),
              total: _todos.length,
              done: _doneCount,
            ),
            const SizedBox(height: 16),
            TodoInputCard(
              controller: _controller,
              adding: _adding,
              onAdd: _addTodo,
              category: _newCategory,
              priority: _newPriority,
              dueDate: _newDueDate,
              onCategoryChanged: (c) => setState(() => _newCategory = c),
              onPriorityChanged: (p) => setState(() => _newPriority = p),
              onDueDateChanged: (d) => setState(() => _newDueDate = d),
            ),
            const SizedBox(height: 20),
            if (_todos.isNotEmpty) ...[
              TodoFilters(
                searchController: _searchController,
                statusFilter: _statusFilter,
                categoryFilter: _categoryFilter,
                onStatusChanged: (f) => setState(() => _statusFilter = f),
                onCategoryChanged: (c) => setState(() => _categoryFilter = c),
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
      if (_todos.isEmpty)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyView(
            icon: Icons.checklist_rounded,
            message: '아직 할 일이 없습니다.\n위 입력창에서 할 일을 추가해 보세요.',
          ),
        )
      else if (visible.isEmpty)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyView(
            icon: Icons.search_off,
            message: '조건에 맞는 할 일이 없습니다.\n검색어나 필터를 바꿔 보세요.',
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          sliver: SliverList.separated(
            itemCount: visible.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final todo = visible[index];
              return TodoCard(
                key: ValueKey(todo.id),
                todo: todo,
                busy: _busyIds.contains(todo.id),
                onToggle: () => _toggleTodo(todo),
                onEdit: () => _editTodo(todo),
                onDelete: () => _removeTodo(todo),
              );
            },
          ),
        ),
    ];
  }
}
