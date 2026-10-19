import 'package:flutter/material.dart';

import '../app/theme.dart';

/// 불러오기 실패처럼 다시 시도 버튼이 필요한 상태를 보여 준다.
class StatusView extends StatelessWidget {
  const StatusView({
    super.key,
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.iconMuted),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSub, height: 1.5),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
