import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/chat_repository.dart';
import '../../services/local_chat_repository.dart';
import '../chat/chat_shell.dart';
import 'auth_page.dart';

/// 로그인 상태에 따라 로그인 화면 또는 채팅 화면을 보여 준다.
///
/// 로그인하지 않은 사용자는 채팅 화면에 들어갈 수 없다.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.auth, this.chatRepository});

  final AuthService auth;

  /// 없으면 사용자마다 로컬 데모 저장소를 새로 만든다.
  final ChatRepository? chatRepository;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _demoOwnerId;
  ChatRepository? _demoRepository;

  /// 데모 저장소는 메모리에 대화를 두므로, 다른 계정이 이전 계정의 대화를 보지 않게
  /// 사용자가 바뀌면 새로 만든다.
  ChatRepository _chatRepositoryFor(String userId) {
    final given = widget.chatRepository;
    if (given != null) return given;
    if (_demoOwnerId != userId || _demoRepository == null) {
      _demoOwnerId = userId;
      _demoRepository = LocalChatRepository();
    }
    return _demoRepository!;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppUser?>(
      stream: widget.auth.userChanges,
      initialData: widget.auth.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user == null) return AuthPage(auth: widget.auth);
        // 계정이 바뀌면 이전 사용자의 화면 상태를 남기지 않는다.
        return ChatShell(
          key: ValueKey(user.id),
          user: user,
          auth: widget.auth,
          chatRepository: _chatRepositoryFor(user.id),
        );
      },
    );
  }
}
