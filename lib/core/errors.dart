import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/chat_repository.dart';

/// 서버가 요청을 처리했는지 알 수 없는 오류인지 판단한다.
///
/// 네트워크 오류나 시간 초과는 서버에는 반영됐을 수 있으므로,
/// 화면을 서버 데이터로 다시 맞춰야 한다.
bool isUncertainFailure(Object error) =>
    error is! PostgrestException && error is! AuthApiException;

/// 사용자에게 보여 줄 오류 문구. 서버 원문이나 토큰은 노출하지 않는다.
String describeError(Object error) {
  const network = '네트워크 연결을 확인하고 다시 시도해 주세요.';
  const relogin = '로그인이 만료되었습니다. 다시 로그인해 주세요.';

  if (error is AuthException) {
    if (error is AuthRetryableFetchException) return network;
    return switch (error.code) {
      'invalid_credentials' => '이메일 또는 비밀번호가 올바르지 않습니다.',
      'email_not_confirmed' => '이메일 인증이 아직 완료되지 않았습니다.',
      'user_already_exists' || 'email_exists' => '이미 가입된 이메일입니다.',
      'weak_password' => '비밀번호가 너무 약합니다. 더 길고 복잡하게 입력해 주세요.',
      'email_address_invalid' => '사용할 수 없는 이메일 주소입니다.',
      'over_email_send_rate_limit' ||
      'over_request_rate_limit' => '요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.',
      'signup_disabled' || 'email_provider_disabled' => '현재 회원가입을 할 수 없습니다.',
      'session_missing' ||
      'session_expired' ||
      'session_not_found' ||
      'refresh_token_not_found' ||
      'bad_jwt' => relogin,
      _ => '인증 중 문제가 발생했습니다. 잠시 후 다시 시도해 주세요.',
    };
  }
  if (error is ChatServiceException) {
    return switch (error.code) {
      'unauthorized' => relogin,
      'invalid_request' => '메시지가 비어 있거나 너무 깁니다.',
      'conversation_not_found' => '대화를 찾을 수 없습니다. 목록을 새로고침해 주세요.',
      'daily_limit_reached' => '오늘 보낼 수 있는 메시지를 모두 사용했습니다. 내일 다시 이용해 주세요.',
      'ai_not_configured' => 'AI 서버가 아직 준비되지 않았습니다. 잠시 후 다시 시도해 주세요.',
      'ai_quota_exceeded' => 'AI 무료 사용량을 모두 사용했습니다. 잠시 후 또는 내일 다시 시도해 주세요.',
      'ai_rate_limited' || 'ai_overloaded' => 'AI 서버가 바쁩니다. 잠시 후 다시 시도해 주세요.',
      'ai_unreachable' => 'AI 서버에 연결하지 못했습니다. 잠시 후 다시 시도해 주세요.',
      'timeout' => '답변이 너무 오래 걸려 중단했습니다. 다시 시도해 주세요.',
      'refused' => '이 요청에는 답변할 수 없습니다. 질문을 바꿔 다시 시도해 주세요.',
      'empty_reply' => '빈 답변을 받아 저장하지 않았습니다. 다시 시도해 주세요.',
      'save_failed' => '답변을 저장하지 못했습니다. 다시 시도해 주세요.',
      'incomplete' => '연결이 끊겨 답변을 끝까지 받지 못했습니다. 대화를 다시 열어 확인해 주세요.',
      _ => '서버에서 요청을 처리하지 못했습니다.',
    };
  }
  if (error is PostgrestException) {
    return switch (error.code) {
      'PGRST301' || 'PGRST303' => relogin,
      '42501' => '권한이 없어 처리할 수 없습니다.',
      '23514' || '22P02' || '23502' => '서버에서 허용하지 않는 값이 있습니다.',
      '22023' => '메시지가 비어 있거나 너무 깁니다.',
      '23503' || 'P0002' => '대화를 찾을 수 없습니다. 목록을 새로고침해 주세요.',
      '23505' => '이미 저장된 항목입니다.',
      '42P01' || 'PGRST205' => '서버에 필요한 테이블이 없습니다.',
      '42883' || 'PGRST202' => '서버에 필요한 기능이 없습니다.',
      _ => '서버에서 요청을 처리하지 못했습니다.',
    };
  }
  return network;
}

/// 디버깅용 로그. 비밀번호·토큰이 섞이지 않도록 오류 종류와 코드만 남긴다.
void logError(String context, Object error) {
  final code = switch (error) {
    AuthException(:final code) => code,
    PostgrestException(:final code) => code,
    ChatServiceException(:final code) => code,
    _ => null,
  };
  debugPrint('$context: ${error.runtimeType}${code == null ? '' : ' ($code)'}');
}
