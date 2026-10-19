import 'dart:convert';

/// Supabase 연결 정보.
///
/// Flutter 웹에서는 코드에 들어간 값이 모두 브라우저로 내려가는 JavaScript에
/// 포함된다. 그래서 여기에는 공개해도 되는 publishable 키만 둔다. 데이터 보호는
/// 키를 숨기는 것이 아니라 로그인과 public.todos 테이블의 RLS 정책이 담당한다.
///
/// 다른 프로젝트에 연결하려면 빌드할 때 값을 바꿔 넣는다.
/// ```sh
/// flutter run -d chrome \
///   --dart-define=SUPABASE_URL=https://<project>.supabase.co \
///   --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
/// ```
const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://dnqrwybyksnoyqtkuwlp.supabase.co',
);

const supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: 'sb_publishable_umdnqlzxeDRMcO-Lskbg4Q_MX-YeM3V',
);

/// 클라이언트에 넣으면 안 되는 키(secret, service_role)가 설정됐는지 검사한다.
///
/// 이런 키는 RLS를 우회하므로, 실수로 들어가면 앱을 시작하지 않는다.
void checkSupabaseConfig({required String url, required String key}) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw StateError('Supabase URL이 올바르지 않습니다.');
  }
  if (key.isEmpty) {
    throw StateError('Supabase publishable 키가 설정되지 않았습니다.');
  }
  if (key.startsWith('sb_secret_')) {
    throw StateError('secret 키는 앱에 넣을 수 없습니다. publishable 키를 사용하세요.');
  }
  // 예전 형식(JWT) 키라면 role이 service_role인지 확인한다.
  final parts = key.split('.');
  if (parts.length == 3) {
    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      if (jsonDecode(payload) case {'role': 'service_role'}) {
        throw StateError('service_role 키는 앱에 넣을 수 없습니다. publishable 키를 사용하세요.');
      }
    } on FormatException {
      // JWT 형식이 아니면 검사하지 않는다.
    }
  }
}
