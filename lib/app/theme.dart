import 'package:flutter/material.dart';

/// 앱에서 쓰는 색상. 여기 값을 바꾸면 앱 전체에 함께 반영된다.
abstract final class AppColors {
  static const primary = Color(0xFF2563EB);
  static const background = Color(0xFFF2F5FB);
  static const textMain = Color(0xFF1F2937);
  static const textSub = Color(0xFF6B7280);
  static const danger = Color(0xFFDC2626);

  /// 완료된 할 일 글자, 수정·삭제 아이콘
  static const textMuted = Color(0xFF9CA3AF);

  /// 미완료 체크 원, 빈 화면 아이콘
  static const iconMuted = Color(0xFFC3CBD8);

  /// 진행 막대 배경, 필터 칩 테두리
  static const track = Color(0xFFE5EAF3);

  /// 선택된 필터 칩 배경
  static const primaryLight = Color(0xFFDBE6FE);

  /// 이전 데이터 가져오기 안내 배너 배경
  static const warningBackground = Color(0xFFFFF7E6);
}

ThemeData buildAppTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    surface: Colors.white,
  ),
  scaffoldBackgroundColor: AppColors.background,
);

/// 입력창 공통 모양: 둥근 모서리, 평소에는 테두리 없음, 입력 중에는 파란 테두리.
///
/// 힌트·라벨·여백처럼 입력창마다 다른 값은 그대로 넘겨받는다.
InputDecoration appFieldDecoration({
  required Color fillColor,
  String? hintText,
  TextStyle? hintStyle,
  String? labelText,
  Widget? prefixIcon,
  Widget? suffixIcon,
  bool? isDense,
  EdgeInsetsGeometry? contentPadding,
}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide.none,
  );

  return InputDecoration(
    hintText: hintText,
    hintStyle: hintStyle,
    labelText: labelText,
    filled: true,
    fillColor: fillColor,
    isDense: isDense,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    contentPadding: contentPadding,
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
    ),
  );
}
