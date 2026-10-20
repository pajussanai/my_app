import 'package:flutter/material.dart';

import 'app/bootstrap.dart';
import 'app/theme.dart';
import 'features/auth/auth_gate.dart';
import 'services/auth_service.dart';
import 'services/chat_repository.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.auth, this.chatRepository});

  /// 테스트에서 인증·저장소를 바꿔 끼울 수 있도록 주입받는다.
  /// auth가 없으면 Supabase를 초기화해 사용한다.
  final AuthService? auth;

  /// 없으면 로컬 데모 채팅 저장소를 쓴다(AI 서버 연결 전).
  final ChatRepository? chatRepository;

  @override
  Widget build(BuildContext context) {
    final auth = this.auth;

    return MaterialApp(
      title: '축복 챗봇',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: auth != null
          ? AuthGate(auth: auth, chatRepository: chatRepository)
          : const SupabaseBootstrap(),
    );
  }
}
