import 'dart:math';

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../widgets/baby_avatar.dart';
import '../../../widgets/status_view.dart';
import '../chat_controller.dart';
import 'message_bubble.dart';
import 'message_composer.dart';

/// 선택한 대화의 메시지 목록과 입력창.
class ChatView extends StatefulWidget {
  const ChatView({super.key, required this.controller});

  final ChatController controller;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _scroll = ScrollController();
  int _lastCount = 0;
  int _lastLength = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_followNewContent);
  }

  @override
  void didUpdateWidget(ChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_followNewContent);
      widget.controller.addListener(_followNewContent);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_followNewContent);
    _scroll.dispose();
    super.dispose();
  }

  /// 새 메시지나 답변 조각이 오면 맨 아래로 따라간다.
  void _followNewContent() {
    final messages = widget.controller.messages;
    final length = messages.isEmpty ? 0 : messages.last.content.length;
    if (messages.length == _lastCount && length == _lastLength) return;
    _lastCount = messages.length;
    _lastLength = length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Column(
        children: [
          if (controller.isDemo)
            Container(
              key: const Key('demoBanner'),
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.warningBackground,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                controller.savesConversations
                    ? '데모 모드: AI 서버 연결 전이라 정해진 답변만 보여 드려요. 대화는 저장됩니다.'
                    : '데모 모드: AI 서버 연결 전이라 정해진 답변만 보여 드려요. 대화는 새로고침하면 사라집니다.',
                style: const TextStyle(fontSize: 13, color: AppColors.textMain),
              ),
            ),
          Expanded(child: _buildBody(controller)),
          MessageComposer(sending: controller.sending, onSend: controller.send),
        ],
      ),
    );
  }

  Widget _buildBody(ChatController controller) {
    if (controller.loadingMessages) {
      return const CozyLoading(message: '아기랑 나눈 이야기를 불러오고 있어요…');
    }
    final error = controller.messagesError;
    if (error != null) {
      return StatusView(
        icon: Icons.cloud_off_outlined,
        message: '메시지를 불러오지 못했습니다.\n$error',
        actionLabel: '다시 시도',
        onAction: controller.reloadMessages,
      );
    }
    final messages = controller.messages;
    if (messages.isEmpty) {
      return _EmptyChat(
        onSuggestion: controller.sending ? null : controller.send,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final bubbleWidth = min(640.0, constraints.maxWidth * 0.85);
        return ListView.separated(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
          itemCount: messages.length,
          separatorBuilder: (_, _) => const SizedBox(height: 14),
          itemBuilder: (context, index) {
            final message = messages[index];
            final isLast = index == messages.length - 1;
            return MessageBubble(
              key: ValueKey(message.id),
              message: message,
              maxWidth: bubbleWidth,
              onRetry: isLast && controller.canRetry ? controller.retry : null,
            );
          },
        );
      },
    );
  }
}

/// 대화가 없을 때 보여 주는 환영 화면. 첫 이야기를 바로 고를 수 있게 한다.
class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.onSuggestion});

  /// 추천 문장을 누르면 바로 보낸다. 답변을 받는 중이면 null.
  final ValueChanged<String>? onSuggestion;

  static const suggestions = [
    '아가야, 엄마 오늘 이야기 들려줄게',
    '아기는 지금 뭐 하고 있어?',
    '우리 아기 사랑해 💕',
  ];

  @override
  Widget build(BuildContext context) {
    final onSuggestion = this.onSuggestion;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BabyAvatar(size: 96),
              const SizedBox(height: 20),
              const Text(
                '엄마아~ 오늘은 나한테 무슨 이야기 해줄 거야? 💕',
                key: Key('welcomeMessage'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMain,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '오늘 있었던 일, 마음, 궁금한 것 무엇이든 말해 주세요.\n아기가 귀 기울여 들을게요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSub, height: 1.6),
              ),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final text in suggestions)
                    ActionChip(
                      label: Text(text),
                      onPressed: onSuggestion == null
                          ? null
                          : () => onSuggestion(text),
                      backgroundColor: AppColors.surface,
                      side: const BorderSide(color: AppColors.primaryLight),
                      shape: const StadiumBorder(),
                      labelStyle: const TextStyle(color: AppColors.textMain),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
