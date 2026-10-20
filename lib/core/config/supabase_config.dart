import 'dart:convert';

/// Supabase 연결 정보.
///
/// Flutter 웹에서는 코드에 들어간 값이 모두 브라우저로 내려가는 JavaScript에
/// 포함된다. 그래서 여기에는 공개해도 되는 publishable 키만 둔다. 데이터 보호는
/// 키를 숨기는 것이 아니라 로그인과 테이블의 RLS 정책이 담당한다.
/// AI API 키 같은 비밀값은 여기에 두지 않는다(Edge Function 비밀값으로만 관리).
///
/// 환경은 두 가지다.
///   test(기본값): 개발·테스트 프로젝트 `dnqrwybyksnoyqtkuwlp`
///   production   : 본 프로젝트 `sdwkhsdkkorxpouvroue` (blessing-chatbot)
///
/// 본 프로젝트는 실수로 연결되지 않도록 키를 코드에 두지 않고 빌드할 때 넣는다.
/// ```sh
/// flutter build web \
///   --dart-define=SUPABASE_ENV=production \
///   --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
/// ```
/// URL이나 키를 직접 지정하면(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY) 환경 기본값보다 우선한다.
const supabaseEnvironment = String.fromEnvironment(
  'SUPABASE_ENV',
  defaultValue: 'test',
);

const _isProduction = supabaseEnvironment == 'production';

const _testUrl = 'https://dnqrwybyksnoyqtkuwlp.supabase.co';
const _testPublishableKey = 'sb_publishable_umdnqlzxeDRMcO-Lskbg4Q_MX-YeM3V';
const _productionUrl = 'https://sdwkhsdkkorxpouvroue.supabase.co';

const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: _isProduction ? _productionUrl : _testUrl,
);

/// production에서는 기본값이 비어 있어서, 키를 넣지 않고 빌드하면 앱이 시작되지 않는다.
const supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: _isProduction ? '' : _testPublishableKey,
);

/// SUPABASE_ENV에 알 수 없는 값(예: 오타 'prod')이 들어오면 앱을 시작하지 않는다.
void checkSupabaseEnvironment(String environment) {
  if (environment != 'test' && environment != 'production') {
    throw StateError(
      'SUPABASE_ENV는 test 또는 production이어야 합니다. (현재: $environment)',
    );
  }
}

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
