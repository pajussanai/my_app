import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';
import '../../widgets/baby_avatar.dart';
import '../../core/errors.dart';
import '../../services/auth_service.dart';
import '../../widgets/error_box.dart';
import 'verify_email_view.dart';

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
        // 성공하면 AuthGate가 채팅 화면으로 바꾼다.
        await widget.auth.signIn(email: email, password: password);
      }
    } on AuthException catch (e) {
      logError(_isSignUp ? '회원가입 실패' : '로그인 실패', e);
      if (!mounted) return;
      if (e.code == 'email_not_confirmed') {
        _showVerification(email);
      } else {
        setState(() => _error = describeError(e));
      }
    } catch (e) {
      logError(_isSignUp ? '회원가입 실패' : '로그인 실패', e);
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingEmail = _pendingEmail;

    return Scaffold(
      body: DecoratedBox(
        // 크림색에서 연한 핑크로 번지는 포근한 바탕
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.background, AppColors.primaryLight],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: softShadow,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
                    child: pendingEmail != null
                        ? VerifyEmailView(
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
            const Center(child: BabyAvatar(size: 76)),
            const SizedBox(height: 16),
            const Text(
              '축복 챗봇',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: AppColors.textMain,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _isSignUp ? '이메일로 새 계정을 만들어 주세요.' : '로그인하고 뱃속 아기와 이야기를 나눠 보세요 💕',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppColors.textSub),
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
                    color: AppColors.textSub,
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
              ErrorBox(message: _error!),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
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
    return appFieldDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppColors.textSub),
      fillColor: AppColors.background,
    );
  }
}
