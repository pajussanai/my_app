import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../services/auth_service.dart';
import '../../services/chat_repository.dart';
import 'chat_controller.dart';
import 'widgets/chat_view.dart';
import 'widgets/conversation_list.dart';

/// 로그인 후 첫 화면. 넓은 화면은 목록+대화를 나란히, 좁은 화면은 서랍 메뉴로 보여 준다.
class ChatShell extends StatefulWidget {
  const ChatShell({
    super.key,
    required this.user,
    required this.auth,
    required this.chatRepository,
  });

  final AppUser user;
  final AuthService auth;
  final ChatRepository chatRepository;

  /// 이 너비 이상이면 대화 목록을 옆에 항상 보여 준다.
  static const wideLayoutWidth = 840.0;

  @override
  State<ChatShell> createState() => _ChatShellState();
}

class _ChatShellState extends State<ChatShell> {
  late final ChatController _chat = ChatController(widget.chatRepository);
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _chat.addListener(_showNotice);
    _chat.loadConversations();
  }

  @override
  void dispose() {
    _chat.removeListener(_showNotice);
    _chat.dispose();
    super.dispose();
  }

  void _showNotice() {
    final notice = _chat.notice;
    if (notice == null || !mounted) return;
    _chat.clearNotice();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(notice)));
  }

  /// 좁은 화면에서 서랍이 열려 있으면 닫는다.
  void _closeDrawer() {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  void _select(String id) {
    _closeDrawer();
    _chat.selectConversation(id);
  }

  void _newChat() {
    _closeDrawer();
    _chat.startNewConversation();
  }

  Future<void> _delete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('대화를 삭제할까요?'),
        content: const Text('대화 내용이 모두 지워지며 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _chat.deleteConversation(id);
  }

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      // 성공하면 AuthGate가 로그인 화면으로 바꾼다.
      await widget.auth.signOut();
    } catch (e) {
      logError('로그아웃 실패', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그아웃하지 못했습니다. ${describeError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  ConversationList _list() => ConversationList(
    controller: _chat,
    email: widget.user.email,
    signingOut: _signingOut,
    onSelect: _select,
    onNewChat: _newChat,
    onDelete: _delete,
    onSignOut: _signOut,
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= ChatShell.wideLayoutWidth) {
          return Scaffold(
            key: _scaffoldKey,
            body: SafeArea(
              child: Row(
                children: [
                  SizedBox(width: 300, child: _list()),
                  const VerticalDivider(width: 1, color: AppColors.track),
                  Expanded(child: ChatView(controller: _chat)),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          key: _scaffoldKey,
          appBar: AppBar(
            backgroundColor: AppColors.surface,
            leading: IconButton(
              tooltip: '대화 목록',
              icon: const Icon(Icons.menu_rounded),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
            title: ListenableBuilder(
              listenable: _chat,
              builder: (context, _) => Text(
                _chat.title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 17),
              ),
            ),
            actions: [
              ListenableBuilder(
                listenable: _chat,
                builder: (context, _) => IconButton(
                  tooltip: '새 대화',
                  icon: const Icon(Icons.add_comment_rounded),
                  onPressed: _chat.sending ? null : _newChat,
                ),
              ),
            ],
          ),
          drawer: Drawer(
            backgroundColor: AppColors.surface,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
            ),
            child: SafeArea(child: _list()),
          ),
          body: ChatView(controller: _chat),
        );
      },
    );
  }
}
