import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';
import '../core/errors.dart';
import '../features/auth/auth_gate.dart';
import '../services/auth_service.dart';
import '../services/chat_repository.dart';
import '../services/supabase_chat_repository.dart';
import '../widgets/baby_avatar.dart';
import '../widgets/status_view.dart';

/// Supabase 초기화가 끝난 뒤에 로그인/채팅 화면을 보여 준다.
class SupabaseBootstrap extends StatefulWidget {
  const SupabaseBootstrap({super.key});

  @override
  State<SupabaseBootstrap> createState() => _SupabaseBootstrapState();
}

/// 환경별 채팅 저장소.
///
/// test·production 모두 해당 Supabase 프로젝트의 채팅 스키마와
/// Edge Function `chat`을 써서 대화를 서버에 저장한다.
///
/// 답변 방식은 빌드 옵션으로 고른다(기본 ai).
///   --dart-define=CHAT_ANSWERS=demo  → AI 대신 DB 데모 답변(테스트 프로젝트 전용)
ChatRepository chatRepositoryFor(
  String environment,
  SupabaseClient client, {
  String answers = chatAnswers,
}) {
  final mode = chatAnswerModeFrom(answers);
  // 데모 답변 함수(demo_send_message)는 테스트 프로젝트에만 있다.
  if (environment == 'production' && mode == ChatAnswerMode.demo) {
    throw StateError('본 프로젝트는 CHAT_ANSWERS=ai로만 빌드할 수 있습니다.');
  }
  return SupabaseChatRepository(client, mode: mode);
}

const chatAnswers = String.fromEnvironment('CHAT_ANSWERS', defaultValue: 'ai');

ChatAnswerMode chatAnswerModeFrom(String value) => switch (value) {
  'ai' => ChatAnswerMode.ai,
  'demo' => ChatAnswerMode.demo,
  _ => throw StateError('CHAT_ANSWERS는 ai 또는 demo여야 합니다.'),
};

class _SupabaseBootstrapState extends State<SupabaseBootstrap> {
  late Future<(AuthService, ChatRepository?)> _ready = _initialize();

  Future<(AuthService, ChatRepository?)> _initialize() async {
    checkSupabaseEnvironment(supabaseEnvironment);
    checkSupabaseConfig(url: supabaseUrl, key: supabasePublishableKey);
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
      // 디버그 로그에는 세션(토큰)과 요청 헤더가 출력되므로 끈다.
      debug: false,
    );
    final client = Supabase.instance.client;
    return (
      SupabaseAuthService(client.auth),
      chatRepositoryFor(supabaseEnvironment, client),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final (auth, chatRepository) = snapshot.data!;
          return AuthGate(auth: auth, chatRepository: chatRepository);
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
        return const Scaffold(body: CozyLoading(message: '축복 챗봇을 준비하고 있어요…'));
      },
    );
  }
}
