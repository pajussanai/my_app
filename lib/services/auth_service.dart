import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 로그인한 사용자 정보. 화면에 필요한 값만 담는다(토큰은 담지 않는다).
class AppUser {
  const AppUser({required this.id, this.email});

  final String id;
  final String? email;
}

enum SignUpOutcome {
  /// 이메일 인증 없이 바로 로그인됨
  signedIn,

  /// 인증 메일을 보냈고, 인증 후 로그인해야 함
  needsEmailConfirmation,
}

abstract class AuthService {
  AppUser? get currentUser;

  /// 로그인·로그아웃·세션 만료 시 바뀐 사용자를 알려 준다.
  Stream<AppUser?> get userChanges;

  Future<void> signIn({required String email, required String password});

  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
  });

  Future<void> resendConfirmation(String email);

  Future<void> signOut();
}

/// Supabase Auth(이메일·비밀번호) 구현.
///
/// 세션은 supabase_flutter가 저장하고(웹은 브라우저 localStorage) 자동 갱신하므로
/// 새로고침하거나 앱을 다시 열어도 로그인 상태가 유지된다.
class SupabaseAuthService implements AuthService {
  SupabaseAuthService(this._auth);

  final GoTrueClient _auth;

  static AppUser? _toAppUser(User? user) =>
      user == null ? null : AppUser(id: user.id, email: user.email);

  /// 인증 메일의 링크를 누르면 돌아올 주소. 웹에서는 지금 열린 앱 주소를 쓴다.
  /// 이 주소는 Supabase 대시보드의 Redirect URLs에 등록돼 있어야 한다.
  static String? get _redirectUrl =>
      kIsWeb ? '${Uri.base.origin}${Uri.base.path}' : null;

  @override
  AppUser? get currentUser => _toAppUser(_auth.currentUser);

  @override
  late final Stream<AppUser?> userChanges = _auth.onAuthStateChange
      .map((state) => _toAppUser(state.session?.user))
      .distinct((a, b) => a?.id == b?.id);

  @override
  Future<void> signIn({required String email, required String password}) =>
      _auth.signInWithPassword(email: email, password: password);

  @override
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
  }) async {
    final response = await _auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: _redirectUrl,
    );
    if (response.session != null) return SignUpOutcome.signedIn;
    // 이메일 인증이 켜져 있으면 이미 가입된 이메일에도 오류 대신
    // identities가 빈 사용자 정보가 온다. 이때는 인증 메일이 발송되지 않는다.
    if (response.user?.identities?.isEmpty ?? false) {
      throw const AuthException('이미 가입된 이메일입니다.', code: 'user_already_exists');
    }
    return SignUpOutcome.needsEmailConfirmation;
  }

  @override
  Future<void> resendConfirmation(String email) => _auth.resend(
    type: OtpType.signup,
    email: email,
    emailRedirectTo: _redirectUrl,
  );

  @override
  Future<void> signOut() => _auth.signOut();
}
