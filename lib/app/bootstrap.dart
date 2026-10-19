import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';
import '../core/errors.dart';
import '../features/auth/auth_gate.dart';
import '../services/auth_service.dart';
import '../services/todo_repository.dart';
import '../widgets/status_view.dart';

/// Supabase 초기화가 끝난 뒤에 로그인/할 일 화면을 보여 준다.
class SupabaseBootstrap extends StatefulWidget {
  const SupabaseBootstrap({super.key});

  @override
  State<SupabaseBootstrap> createState() => _SupabaseBootstrapState();
}

class _SupabaseBootstrapState extends State<SupabaseBootstrap> {
  late Future<(AuthService, TodoRepository)> _ready = _initialize();

  Future<(AuthService, TodoRepository)> _initialize() async {
    checkSupabaseConfig(url: supabaseUrl, key: supabasePublishableKey);
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
      // 디버그 로그에는 세션(토큰)과 요청 헤더가 출력되므로 끈다.
      debug: false,
    );
    final client = Supabase.instance.client;
    return (SupabaseAuthService(client.auth), SupabaseTodoRepository(client));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final (auth, repository) = snapshot.data!;
          return AuthGate(auth: auth, repository: repository);
        }
        if (snapshot.hasError) {
          logError('Supabase 초기화 실패', snapshot.error!);
          final error = snapshot.error;
          return Scaffold(
            body: SafeArea(
              child: StatusView(
                icon: Icons.cloud_off_outlined,
                message: error is StateError
                    ? '앱 설정 오류: ${error.message}'
                    : '서버에 연결할 준비를 하지 못했습니다.\n잠시 후 다시 시도해 주세요.',
                actionLabel: '다시 시도',
                onAction: () => setState(() => _ready = _initialize()),
              ),
            ),
          );
        }
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}
