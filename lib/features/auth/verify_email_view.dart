import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../services/auth_service.dart';
import '../../widgets/error_box.dart';

/// 회원가입 후 이메일 인증을 안내하는 화면.
class VerifyEmailView extends StatefulWidget {
  const VerifyEmailView({
    super.key,
    required this.auth,
    required this.email,
    required this.onBack,
  });

  final AuthService auth;
  final String email;
  final VoidCallback onBack;

  @override
  State<VerifyEmailView> createState() => _VerifyEmailViewState();
}

class _VerifyEmailViewState extends State<VerifyEmailView> {
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
      logError('인증 메일 재발송 실패', e);
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
          color: AppColors.primary,
        ),
        const SizedBox(height: 16),
        const Text(
          '이메일 인증이 필요합니다',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textMain,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${widget.email} 주소로 인증 메일을 보냈습니다.\n'
          '메일의 링크를 눌러 인증을 마친 뒤 로그인해 주세요.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSub, height: 1.5),
        ),
        const SizedBox(height: 8),
        const Text(
          '메일이 보이지 않으면 스팸함을 확인해 주세요.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.textSub),
        ),
        if (_notice != null) ...[
          const SizedBox(height: 16),
          _noticeIsError
              ? ErrorBox(message: _notice!)
              : Text(
                  _notice!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.primary),
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
