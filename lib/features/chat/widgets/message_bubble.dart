import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../models/chat_message.dart';
import '../../../widgets/baby_avatar.dart';

/// 메시지 말풍선. 사용자는 오른쪽(연한 핑크), 아기(AI)는 왼쪽(흰색)에
/// 아기 얼굴과 함께 표시해 마주 보고 이야기하는 느낌을 준다.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.maxWidth,
    this.onRetry,
  });

  final ChatMessage message;
  final double maxWidth;

  /// 실패한 마지막 답변이면 다시 시도 버튼을 보여 준다.
  final VoidCallback? onRetry;

  static const _avatarSize = 34.0;
  static const _avatarGap = 8.0;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final failed = message.status == MessageStatus.error;
    const radius = Radius.circular(22);

    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        // 저장되지 않은 질문은 보낸 것처럼 보이지 않게 회색으로 표시한다.
        color: isUser
            ? (failed ? AppColors.textMuted : AppColors.userBubble)
            : AppColors.babyBubble,
        borderRadius: BorderRadius.only(
          topLeft: isUser ? radius : const Radius.circular(8),
          topRight: isUser ? const Radius.circular(8) : radius,
          bottomLeft: radius,
          bottomRight: radius,
        ),
        border: failed && !isUser
            ? Border.all(color: AppColors.danger.withValues(alpha: 0.35))
            : null,
        boxShadow: isUser ? null : softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.content.isNotEmpty)
            SelectableText(
              message.content,
              style: TextStyle(
                fontSize: 15,
                height: 1.55,
                color: isUser && failed ? Colors.white : AppColors.textMain,
              ),
            )
          else if (message.status == MessageStatus.streaming)
            const _Typing(),
          if (failed && isUser) ...[
            const SizedBox(height: 4),
            const Row(
              key: Key('notSentLabel'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 14, color: Colors.white),
                SizedBox(width: 4),
                Text(
                  '전송되지 않음',
                  style: TextStyle(fontSize: 12, color: Colors.white),
                ),
              ],
            ),
          ] else if (failed) ...[
            if (message.content.isNotEmpty) const SizedBox(height: 8),
            _ErrorLine(
              text: message.errorMessage ?? '답변을 받지 못했습니다.',
              onRetry: onRetry,
            ),
          ],
        ],
      ),
    );

    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: bubble,
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BabyAvatar(size: _avatarSize),
          const SizedBox(width: _avatarGap),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth - _avatarSize - _avatarGap,
              ),
              child: bubble,
            ),
          ),
        ],
      ),
    );
  }
}

/// 답변 첫 글자가 오기 전까지 보여 주는 표시: 통통 튀는 점 세 개와 안내 문구.
class _Typing extends StatefulWidget {
  const _Typing();

  @override
  State<_Typing> createState() => _TypingState();
}

class _TypingState extends State<_Typing> with SingleTickerProviderStateMixin {
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          AnimatedBuilder(
            animation: _bounce,
            builder: (context, child) {
              // 점마다 시작 시점을 조금씩 늦춰 물결처럼 튀게 한다.
              final t = (_bounce.value - i * 0.15) % 1.0;
              final lift = t < 0.4 ? (t < 0.2 ? t : 0.4 - t) * 20 : 0.0;
              return Transform.translate(
                offset: Offset(0, -lift),
                child: child,
              );
            },
            child: Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
        const SizedBox(width: 10),
        const Flexible(
          child: Text(
            '아기가 꼬물꼬물 대답을 생각하고 있어요…',
            style: TextStyle(fontSize: 14, color: AppColors.textSub),
          ),
        ),
      ],
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: AppColors.danger,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: AppColors.danger,
                ),
              ),
            ),
          ],
        ),
        if (onRetry != null)
          TextButton.icon(
            key: const Key('retryButton'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('다시 시도'),
          ),
      ],
    );
  }
}
