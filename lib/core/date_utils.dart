/// 시각을 버리고 날짜(그날 0시)만 남긴다.
DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

/// 대화 목록용 시각: 오늘이면 '14:05', 올해면 '10월 19일', 그 외에는 '2025년 10월 19일'.
String formatListTime(DateTime time, DateTime now) {
  final local = time.toLocal();
  if (dateOnly(local) == dateOnly(now)) {
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
  return local.year == now.year
      ? '${local.month}월 ${local.day}일'
      : '${local.year}년 ${local.month}월 ${local.day}일';
}
