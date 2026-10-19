import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/todo_repository.dart';
import '../todos/todo_page.dart';
import 'auth_page.dart';

/// 로그인 상태에 따라 로그인 화면 또는 할 일 화면을 보여 준다.
///
/// 로그인하지 않은 사용자는 할 일 화면에 들어갈 수 없다.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.auth, required this.repository});

  final AuthService auth;
  final TodoRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppUser?>(
      stream: auth.userChanges,
      initialData: auth.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user == null) return AuthPage(auth: auth);
        // 계정이 바뀌면 이전 사용자의 화면 상태를 남기지 않는다.
        return TodoPage(
          key: ValueKey(user.id),
          user: user,
          auth: auth,
          repository: repository,
        );
      },
    );
  }
}
