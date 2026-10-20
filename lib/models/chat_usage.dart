/// 오늘의 AI 사용량. 서버(Edge Function)가 usage_daily에서 집계한 **앱 기준** 값이다.
///
/// Google Gemini 무료 할당량의 잔여량이 아니다. Gemini API는 무료 잔여량을
/// 알려 주지 않으므로 앱은 그 값을 추측하지 않는다(AI Studio에서 확인).
class ChatUsage {
  const ChatUsage({
    required this.day,
    required this.provider,
    required this.model,
    required this.aiConfigured,
    required this.requestCount,
    required this.inputTokens,
    required this.outputTokens,
    required this.dailyLimit,
    required this.remaining,
  });

  /// 한국 시간 기준 날짜(YYYY-MM-DD)
  final String day;
  final String provider;
  final String model;

  /// 서버에 AI 키가 등록되어 있는지
  final bool aiConfigured;

  /// 오늘 AI에 보낸 요청 수(앱 집계)
  final int requestCount;
  final int inputTokens;
  final int outputTokens;

  /// 앱이 정한 하루 요청 한도
  final int dailyLimit;

  /// 앱 한도 기준 남은 요청 수
  final int remaining;

  bool get appLimitReached => remaining <= 0;

  factory ChatUsage.fromJson(Map<String, dynamic> json) {
    int count(String key) => (json[key] as num?)?.toInt() ?? 0;
    final day = json['day'];
    final model = json['model'];
    if (day is! String || model is! String) {
      throw const FormatException('사용량 응답 형식이 올바르지 않습니다.');
    }
    return ChatUsage(
      day: day,
      provider: json['provider'] as String? ?? '',
      model: model,
      aiConfigured: json['ai_configured'] == true,
      requestCount: count('request_count'),
      inputTokens: count('input_tokens'),
      outputTokens: count('output_tokens'),
      dailyLimit: count('daily_limit'),
      remaining: count('remaining'),
    );
  }
}
