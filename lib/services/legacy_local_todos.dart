import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/todo.dart';

/// 서버 연결 전 버전이 이 브라우저(기기)의 shared_preferences에 남긴 할 일.
///
/// 자동으로 서버에 올리지 않는다. 사용자가 가져오기를 선택했을 때만 사용한다.
class LegacyLocalTodos {
  static const _key = 'todos';

  Future<List<Todo>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => Todo.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // 형식이 깨진 데이터는 가져올 수 없으므로 없는 것으로 본다.
      debugPrint('이전 로컬 할 일 데이터를 읽을 수 없습니다: ${e.runtimeType}');
      return [];
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
