import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// 할 일 화면 맨 위: 제목, 새로고침·로그아웃 버튼, 로그인한 계정.
class TodoHeader extends StatelessWidget {
  const TodoHeader({
    super.key,
    required this.email,
    required this.onRefresh,
    required this.onSignOut,
  });

  final String? email;

  /// null이면 버튼을 비활성화한다(불러오는 중, 로그아웃 중).
  final VoidCallback? onRefresh;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '오늘 할 일',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textMain,
                ),
              ),
            ),
            IconButton(
              tooltip: '새로고침',
              icon: const Icon(Icons.refresh),
              color: AppColors.textSub,
              onPressed: onRefresh,
            ),
            IconButton(
              tooltip: '로그아웃',
              icon: const Icon(Icons.logout),
              color: AppColors.textSub,
              onPressed: onSignOut,
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          '해야 할 일을 적고 하나씩 완료해 보세요.',
          style: TextStyle(fontSize: 14, color: AppColors.textSub),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(
              Icons.account_circle_outlined,
              size: 16,
              color: AppColors.textSub,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                email ?? '로그인됨',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: AppColors.textSub),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
