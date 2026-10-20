import 'package:flutter/material.dart';

import '../app/theme.dart';

/// 아기 얼굴 동그라미. 아기(AI) 말풍선, 빈 화면, 로딩 화면에 함께 쓴다.
class BabyAvatar extends StatelessWidget {
  const BabyAvatar({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.babyBlue, AppColors.primaryLight],
        ),
        border: Border.all(color: Colors.white, width: size / 18),
        boxShadow: softShadow,
      ),
      child: Icon(
        Icons.child_care_rounded,
        size: size * 0.58,
        color: AppColors.primary,
      ),
    );
  }
}

/// 포근한 로딩 표시. 무엇을 기다리는지 [message]로 알려 준다.
class CozyLoading extends StatelessWidget {
  const CozyLoading({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 64,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  BabyAvatar(size: 48),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSub, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
