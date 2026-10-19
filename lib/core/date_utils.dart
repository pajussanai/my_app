/// 시각을 버리고 날짜(그날 0시)만 남긴다.
DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

/// 날짜를 서버(date 컬럼)에 보내는 'YYYY-MM-DD' 형식으로 바꾼다.
String toIsoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// 'YYYY-MM-DD' 같은 날짜 문자열을 읽는다. 문자열이 아니거나 형식이 틀리면 null.
DateTime? parseIsoDate(Object? value) {
  if (value is! String) return null;
  final parsed = DateTime.tryParse(value);
  return parsed == null ? null : dateOnly(parsed);
}

/// 마감일을 '오늘', '내일', '10월 25일'처럼 읽기 쉬운 문자열로 바꾼다.
String formatDueDate(DateTime due, DateTime today) {
  // 서머타임 영향을 받지 않도록 UTC 날짜끼리 비교한다.
  final days = DateTime.utc(
    due.year,
    due.month,
    due.day,
  ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  if (days == 0) return '오늘';
  if (days == 1) return '내일';
  if (days == -1) return '어제';
  return due.year == today.year
      ? '${due.month}월 ${due.day}일'
      : '${due.year}년 ${due.month}월 ${due.day}일';
}
