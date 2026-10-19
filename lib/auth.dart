part of 'main.dart';

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

/// 로그인 상태에 따라 로그인 화면 또는 할 일 화면을 보여 준다.
///
/// 로그인하지 않은 사용자는 할 일 화면에 들어갈 수 없다.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.auth, required this.repository});

  final AuthService auth;
  final TodoRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppUser?>(
      stream: auth.userChanges,
      initialData: auth.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user == null) return AuthPage(auth: auth);
        // 계정이 바뀌면 이전 사용자의 화면 상태를 남기지 않는다.
        return TodoPage(
          key: ValueKey(user.id),
          user: user,
          auth: auth,
          repository: repository,
        );
      },
    );
  }
}

enum _AuthMode { signIn, signUp }

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.auth});

  final AuthService auth;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  _AuthMode _mode = _AuthMode.signIn;
  bool _submitting = false;
  bool _obscurePassword = true;
  String? _error;

  /// 값이 있으면 이메일 인증 안내 화면을 보여 준다.
  String? _pendingEmail;

  bool get _isSignUp => _mode == _AuthMode.signUp;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _switchMode() {
    setState(() {
      _mode = _isSignUp ? _AuthMode.signIn : _AuthMode.signUp;
      _error = null;
      _confirmController.clear();
    });
  }

  void _showVerification(String email) {
    _passwordController.clear();
    _confirmController.clear();
    setState(() => _pendingEmail = email);
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (_isSignUp) {
        final outcome = await widget.auth.signUp(
          email: email,
          password: password,
        );
        if (outcome == SignUpOutcome.needsEmailConfirmation && mounted) {
          _showVerification(email);
        }
      } else {
        // 성공하면 AuthGate가 할 일 화면으로 바꾼다.
        await widget.auth.signIn(email: email, password: password);
      }
    } on AuthException catch (e) {
      _logError(_isSignUp ? '회원가입 실패' : '로그인 실패', e);
      if (!mounted) return;
      if (e.code == 'email_not_confirmed') {
        _showVerification(email);
      } else {
        setState(() => _error = describeError(e));
      }
    } catch (e) {
      _logError(_isSignUp ? '회원가입 실패' : '로그인 실패', e);
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingEmail = _pendingEmail;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 0,
                color: Colors.white,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: pendingEmail != null
                      ? _VerifyEmailView(
                          auth: widget.auth,
                          email: pendingEmail,
                          onBack: () => setState(() {
                            _pendingEmail = null;
                            _mode = _AuthMode.signIn;
                            _error = null;
                          }),
                        )
                      : _buildForm(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '오늘 할 일',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: _textMain,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _isSignUp ? '이메일로 새 계정을 만드세요.' : '로그인하고 할 일을 관리하세요.',
              style: const TextStyle(fontSize: 14, color: _textSub),
            ),
            const SizedBox(height: 24),
            TextFormField(
              key: const Key('emailInput'),
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              decoration: _authDecoration('이메일', Icons.mail_outline),
              validator: (value) {
                final email = value?.trim() ?? '';
                if (email.isEmpty) return '이메일을 입력하세요.';
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
                  return '올바른 이메일 형식이 아닙니다.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('passwordInput'),
              controller: _passwordController,
              obscureText: _obscurePassword,
              autofillHints: [
                _isSignUp ? AutofillHints.newPassword : AutofillHints.password,
              ],
              textInputAction: _isSignUp
                  ? TextInputAction.next
                  : TextInputAction.done,
              onFieldSubmitted: _isSignUp ? null : (_) => _submit(),
              decoration: _authDecoration('비밀번호', Icons.lock_outline).copyWith(
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? '비밀번호 보기' : '비밀번호 숨기기',
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: _textSub,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (value) {
                final password = value ?? '';
                if (password.isEmpty) return '비밀번호를 입력하세요.';
                if (_isSignUp && password.length < 6) {
                  return '비밀번호는 6자 이상이어야 합니다.';
                }
                return null;
              },
            ),
            if (_isSignUp) ...[
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('confirmInput'),
                controller: _confirmController,
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: _authDecoration('비밀번호 확인', Icons.lock_outline),
                validator: (value) => value != _passwordController.text
                    ? '비밀번호가 일치하지 않습니다.'
                    : null,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              _ErrorBox(message: _error!),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _submitting
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(_isSignUp ? '회원가입' : '로그인'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _submitting ? null : _switchMode,
              child: Text(_isSignUp ? '이미 계정이 있으신가요? 로그인' : '계정이 없으신가요? 회원가입'),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _authDecoration(String label, IconData icon) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: _textSub),
      filled: true,
      fillColor: _background,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: _primaryBlue, width: 1.5),
      ),
    );
  }
}

/// 회원가입 후 이메일 인증을 안내하는 화면.
class _VerifyEmailView extends StatefulWidget {
  const _VerifyEmailView({
    required this.auth,
    required this.email,
    required this.onBack,
  });

  final AuthService auth;
  final String email;
  final VoidCallback onBack;

  @override
  State<_VerifyEmailView> createState() => _VerifyEmailViewState();
}

class _VerifyEmailViewState extends State<_VerifyEmailView> {
  bool _sending = false;
  String? _notice;
  bool _noticeIsError = false;

  Future<void> _resend() async {
    setState(() {
      _sending = true;
      _notice = null;
    });
    try {
      await widget.auth.resendConfirmation(widget.email);
      if (mounted) {
        setState(() {
          _notice = '인증 메일을 다시 보냈습니다.';
          _noticeIsError = false;
        });
      }
    } catch (e) {
      _logError('인증 메일 재발송 실패', e);
      if (mounted) {
        setState(() {
          _notice = describeError(e);
          _noticeIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.mark_email_unread_outlined,
          size: 48,
          color: _primaryBlue,
        ),
        const SizedBox(height: 16),
        const Text(
          '이메일 인증이 필요합니다',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: _textMain,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${widget.email} 주소로 인증 메일을 보냈습니다.\n'
          '메일의 링크를 눌러 인증을 마친 뒤 로그인해 주세요.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _textSub, height: 1.5),
        ),
        const SizedBox(height: 8),
        const Text(
          '메일이 보이지 않으면 스팸함을 확인해 주세요.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: _textSub),
        ),
        if (_notice != null) ...[
          const SizedBox(height: 16),
          _noticeIsError
              ? _ErrorBox(message: _notice!)
              : Text(
                  _notice!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _primaryBlue),
                ),
        ],
        const SizedBox(height: 20),
        OutlinedButton(
          onPressed: _sending ? null : _resend,
          child: _sending
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('인증 메일 다시 보내기'),
        ),
        const SizedBox(height: 8),
        FilledButton(onPressed: widget.onBack, child: const Text('로그인 화면으로')),
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 18, color: _danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: const TextStyle(color: _danger)),
          ),
        ],
      ),
    );
  }
}
