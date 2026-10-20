import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, PostgrestException;

import 'package:my_app/core/config/supabase_config.dart';
import 'package:my_app/core/errors.dart';
import 'package:my_app/core/ids.dart';

import '../helpers/fakes.dart';

void main() {
  group('id와 설정', () {
    test('newUuid는 UUID v4 형식이고 매번 다르다', () {
      final pattern = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      final ids = {for (var i = 0; i < 100; i++) newUuid()};
      expect(ids.length, 100);
      expect(ids.every(pattern.hasMatch), isTrue);
    });

    test('publishable 키만 허용하고 secret·service_role 키는 거부', () {
      const url = 'https://example.supabase.co';
      expect(
        () =>
            checkSupabaseConfig(url: supabaseUrl, key: supabasePublishableKey),
        returnsNormally,
      );
      expect(
        () => checkSupabaseConfig(url: url, key: 'sb_secret_abc'),
        throwsStateError,
      );
      String jwt(Map<String, dynamic> payload) =>
          'eyJhbGciOiJIUzI1NiJ9.'
          '${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}'
          '.sig';
      expect(
        () => checkSupabaseConfig(url: url, key: jwt({'role': 'service_role'})),
        throwsStateError,
      );
      expect(
        () => checkSupabaseConfig(url: url, key: jwt({'role': 'anon'})),
        returnsNormally,
      );
      expect(
        () => checkSupabaseConfig(
          url: 'http://example.com',
          key: 'sb_publishable_x',
        ),
        throwsStateError,
      );
      expect(supabasePublishableKey, startsWith('sb_publishable_'));
    });

    test('오류 문구에 서버 원문을 노출하지 않는다', () {
      expect(
        describeError(
          const AuthException(
            'Invalid login credentials',
            code: 'invalid_credentials',
          ),
        ),
        '이메일 또는 비밀번호가 올바르지 않습니다.',
      );
      expect(
        describeError(
          const PostgrestException(message: 'JWT expired', code: 'PGRST301'),
        ),
        '로그인이 만료되었습니다. 다시 로그인해 주세요.',
      );
      expect(describeError(permissionDenied), '권한이 없어 처리할 수 없습니다.');
      expect(describeError(TimeoutException('x')), contains('네트워크'));
    });
  });
}
