import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/date_utils.dart';
import '../../../widgets/baby_avatar.dart';
import '../chat_controller.dart';
import 'usage_card.dart';

/// 대화 목록 패널: 새 대화, 이전 대화, 오늘의 AI 사용량, 계정·로그아웃.
///
/// 넓은 화면에서는 왼쪽에 항상 보이고, 좁은 화면에서는 서랍(Drawer) 안에 들어간다.
class ConversationList extends StatelessWidget {
  const ConversationList({
    super.key,
    required this.controller,
    required this.email,
    required this.signingOut,
    required this.onSelect,
    required this.onNewChat,
    required this.onDelete,
    required this.onSignOut,
  });

  final ChatController controller;
  final String? email;
  final bool signingOut;
  final ValueChanged<String> onSelect;
  final VoidCallback onNewChat;
  final ValueChanged<String> onDelete;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    // ListTile의 선택 배경과 눌림 효과가 보이도록 ColoredBox 대신 Material을 쓴다.
    return Material(
      color: AppColors.surface,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 22, 20, 16),
              child: Row(
                children: [
                  BabyAvatar(size: 44),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '축복 챗봇',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textMain,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '엄마와 뱃속 아기의 이야기',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSub,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton.icon(
                key: const Key('newChatButton'),
                onPressed: controller.sending ? null : onNewChat,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('새 대화'),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildList(context)),
            UsageCard(controller: controller),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(
                email ?? '로그인됨',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: AppColors.textSub),
              ),
              trailing: IconButton(
                tooltip: '로그아웃',
                icon: const Icon(Icons.logout),
                onPressed: signingOut ? null : onSignOut,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    if (controller.loadingConversations) {
      return const CozyLoading(message: '대화 목록을 불러오고 있어요…');
    }
    final error = controller.conversationsError;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '대화 목록을 불러오지 못했습니다.\n$error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSub),
              ),
              TextButton(
                onPressed: controller.loadConversations,
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      );
    }
    final conversations = controller.conversations;
    if (conversations.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.favorite_border_rounded,
                color: AppColors.iconMuted,
                size: 32,
              ),
              SizedBox(height: 8),
              Text('아직 대화가 없어요.', style: TextStyle(color: AppColors.textSub)),
              SizedBox(height: 2),
              Text(
                '새 대화로 뱃속 아기에게 첫 인사를 건네 보세요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    final now = DateTime.now();
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: conversations.length,
      itemBuilder: (context, index) {
        final c = conversations[index];
        return ListTile(
          key: ValueKey('conversation-${c.id}'),
          selected: c.id == controller.selectedId,
          selectedTileColor: AppColors.primaryLight,
          title: Text(
            c.displayTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            formatListTime(c.sortTime, now),
            style: const TextStyle(fontSize: 12),
          ),
          onTap: controller.sending ? null : () => onSelect(c.id),
          trailing: IconButton(
            tooltip: '대화 삭제',
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            onPressed: controller.sending ? null : () => onDelete(c.id),
          ),
        );
      },
    );
  }
}
