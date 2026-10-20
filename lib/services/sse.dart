import 'dart:convert';

/// 서버가 보낸 이벤트(Server-Sent Events) 하나
class SseEvent {
  const SseEvent(this.event, this.data);

  /// `event:` 줄의 값. 없으면 'message'.
  final String event;

  /// `data:` 줄들을 줄바꿈으로 이은 값
  final String data;
}

/// 바이트 스트림을 SSE 이벤트로 나눈다.
///
/// 빈 줄이 이벤트의 끝이다. `:`로 시작하는 줄(연결 유지 신호)은 무시한다.
/// 글자가 여러 조각에 걸쳐 와도 UTF-8로 올바르게 이어 붙인다.
Stream<SseEvent> parseSse(Stream<List<int>> bytes) async* {
  String? event;
  final data = <String>[];

  await for (final line
      in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (data.isNotEmpty) yield SseEvent(event ?? 'message', data.join('\n'));
      event = null;
      data.clear();
      continue;
    }
    if (line.startsWith(':')) continue;
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'event':
        event = value;
      case 'data':
        data.add(value);
    }
  }
  // 스트림이 빈 줄 없이 끝난 마지막 이벤트는 완성되지 않은 것이므로 버린다.
}
