import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme.dart';
import '../../../models/chat_usage.dart';
import '../chat_controller.dart';

/// AI Studio에서 실제 Google 무료 한도·사용량을 볼 수 있는 곳
const aiStudioRateLimitUrl = 'https://aistudio.google.com/rate-limit';
const geminiRateLimitDocsUrl =
    'https://ai.google.dev/gemini-api/docs/rate-limits';
const geminiBillingDocsUrl = 'https://ai.google.dev/gemini-api/docs/billing';

enum UsageTone { ok, warn, blocked, unknown }

/// 사용량 상태 한 줄과 설명
class UsageStatus {
  const UsageStatus(this.label, this.detail, this.tone);

  final String label;
  final String detail;
  final UsageTone tone;
}

/// 앱 집계 사용량과 이번 접속에서 받은 제한 오류로 상태를 정한다.
///
/// Google 무료 잔여량은 알 수 없으므로, "정상"도 앱 기준이라고 밝힌다.
UsageStatus usageStatusOf(ChatUsage? usage, {String? limitCode}) {
  if (limitCode == 'ai_quota_exceeded') {
    return const UsageStatus(
      'Google 무료 사용량 초과',
      'Gemini가 무료 사용량 초과(또는 요청 제한)를 알려 왔어요. 유료로 전환하지 않고 멈춰요. '
          '잠시 후 또는 내일 다시 시도해 주세요.',
      UsageTone.blocked,
    );
  }
  if (usage == null) {
    return const UsageStatus('확인 중', '사용량을 아직 불러오지 못했어요.', UsageTone.unknown);
  }
  if (!usage.aiConfigured) {
    return const UsageStatus(
      'AI 서버 준비 중',
      '서버에 AI 키가 아직 등록되지 않았어요.',
      UsageTone.blocked,
    );
  }
  if (usage.appLimitReached || limitCode == 'daily_limit_reached') {
    return const UsageStatus(
      '앱 일일 한도 도달',
      '오늘 앱에서 정한 횟수를 모두 썼어요. 내일(한국 시간 0시) 다시 쓸 수 있어요.',
      UsageTone.blocked,
    );
  }
  if (limitCode == 'ai_rate_limited') {
    return const UsageStatus(
      '요청 제한 중',
      'AI 서버가 잠시 요청을 제한했어요. 조금 뒤 다시 시도해 주세요.',
      UsageTone.warn,
    );
  }
  if (usage.remaining * 10 <= usage.dailyLimit) {
    return const UsageStatus(
      '앱 한도가 얼마 남지 않았어요',
      '앱 기준으로 오늘 남은 횟수가 적어요.',
      UsageTone.warn,
    );
  }
  return const UsageStatus(
    '정상 이용 가능',
    '앱 기준으로 이용할 수 있어요. Google 무료 잔여량은 AI Studio에서 확인해 주세요.',
    UsageTone.ok,
  );
}

String _count(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

Color _toneColor(UsageTone tone) => switch (tone) {
  UsageTone.ok => const Color(0xFF4F9A7A),
  UsageTone.warn => const Color(0xFFC98A2E),
  UsageTone.blocked => AppColors.danger,
  UsageTone.unknown => AppColors.textSub,
};

/// 대화 목록 아래에 보이는 작은 사용량 카드. 누르면 자세한 내용을 보여 준다.
class UsageCard extends StatelessWidget {
  const UsageCard({super.key, required this.controller});

  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    final usage = controller.usage;
    // AI 서버를 쓰지 않는 데모 저장소에서는 보여 주지 않는다.
    if (usage == null && controller.usageError == null) {
      return const SizedBox.shrink();
    }
    final status = usageStatusOf(usage, limitCode: controller.limitCode);
    final color = _toneColor(status.tone);
    final progress = usage == null || usage.dailyLimit == 0
        ? 0.0
        : (usage.requestCount / usage.dailyLimit).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Material(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          key: const Key('usageCard'),
          borderRadius: BorderRadius.circular(18),
          onTap: () => showUsageDetails(context, controller),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.favorite_rounded,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        '오늘의 AI 사용량',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMain,
                        ),
                      ),
                    ),
                    Icon(Icons.circle, size: 8, color: color),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        status.label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: color),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  usage == null
                      ? controller.usageError ?? '불러오는 중…'
                      : '오늘 ${_count(usage.requestCount)}회 · '
                            '앱 한도 ${_count(usage.dailyLimit)}회 · '
                            '남은 ${_count(usage.remaining)}회',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSub,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    color: color,
                    backgroundColor: AppColors.track,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 사용량 자세히 보기. 앱 집계 값과 Google 무료 할당량을 구분해 보여 준다.
Future<void> showUsageDetails(BuildContext context, ChatController controller) {
  controller.loadUsage();
  return showDialog<void>(
    context: context,
    builder: (context) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final usage = controller.usage;
        final status = usageStatusOf(usage, limitCode: controller.limitCode);
        final color = _toneColor(status.tone);
        return AlertDialog(
          title: const Text('오늘의 AI 사용량'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                key: const Key('usageDetails'),
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '상태: ${status.label}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          status.detail,
                          style: const TextStyle(fontSize: 13, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (usage == null)
                    Text(
                      controller.usageError ?? '불러오는 중…',
                      style: const TextStyle(color: AppColors.textSub),
                    )
                  else ...[
                    const _SectionTitle('앱 자체 집계 (한국 시간 기준 오늘)'),
                    _Row('오늘 사용', '${_count(usage.requestCount)}회'),
                    _Row('앱 일일 한도', '${_count(usage.dailyLimit)}회'),
                    _Row('앱 기준 남은 횟수', '${_count(usage.remaining)}회'),
                    _Row('입력 토큰', _count(usage.inputTokens)),
                    _Row('출력 토큰', _count(usage.outputTokens)),
                    _Row('모델', usage.model),
                    _Row('기준 날짜', usage.day),
                  ],
                  const SizedBox(height: 14),
                  const _SectionTitle('Google Gemini 무료 할당량'),
                  const Text(
                    '앱 일일 한도와 Google 무료 할당량은 서로 다른 값이에요. '
                    'Gemini API는 무료 잔여량을 알려 주지 않아서 앱이 추측하지 않아요. '
                    '실제 무료 한도와 사용량은 AI Studio에서 확인해 주세요. '
                    '무료 사용량을 넘으면 유료로 바꾸지 않고 오류로 알려 드려요.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.55,
                      color: AppColors.textSub,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const _LinkRow('AI Studio 사용량', aiStudioRateLimitUrl),
                  const _LinkRow('요청 제한 문서', geminiRateLimitDocsUrl),
                  const _LinkRow('결제·무료 등급 문서', geminiBillingDocsUrl),
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: controller.loadUsage,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('새로 고침'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('닫기'),
            ),
          ],
        );
      },
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.textMain,
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: AppColors.textSub),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textMain,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 새 패키지 없이 링크를 전달하기 위해 주소를 보여 주고 복사할 수 있게 한다.
class _LinkRow extends StatelessWidget {
  const _LinkRow(this.label, this.url);

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12)),
              SelectableText(
                url,
                style: const TextStyle(fontSize: 12, color: AppColors.primary),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '주소 복사',
          icon: const Icon(Icons.copy_rounded, size: 18),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: url));
            ScaffoldMessenger.maybeOf(context)
                ?.showSnackBar(SnackBar(content: Text('$label 주소를 복사했어요.')));
          },
        ),
      ],
    );
  }
}
