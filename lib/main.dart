import 'package:flutter/material.dart';

import 'app/bootstrap.dart';
import 'app/theme.dart';
import 'features/auth/auth_gate.dart';
import 'services/auth_service.dart';
import 'services/todo_repository.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.auth, this.repository});

  /// 테스트에서 인증·저장소를 바꿔 끼울 수 있도록 주입받는다.
  /// 둘 다 없으면 Supabase를 초기화해 사용한다.
  final AuthService? auth;
  final TodoRepository? repository;

  @override
  Widget build(BuildContext context) {
    final auth = this.auth;
    final repository = this.repository;

    return MaterialApp(
      title: '오늘 할 일',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: auth != null && repository != null
          ? AuthGate(auth: auth, repository: repository)
          : const SupabaseBootstrap(),
    );
  }
}
