import 'package:flutter/material.dart';

/// 앱에서 쓰는 색상. 여기 값을 바꾸면 앱 전체에 함께 반영된다.
///
/// 아기 테마: 크림·아이보리 바탕에 연한 핑크와 베이비 블루를 포인트로 쓴다.
abstract final class AppColors {
  /// 버튼·강조색(로즈 핑크). 흰 글자를 올려도 읽히도록 조금 진하게 잡았다.
  static const primary = Color(0xFFD45D7E);

  /// 화면 바탕(크림)
  static const background = Color(0xFFFFF8F1);

  /// 카드·패널 바탕(아이보리)
  static const surface = Color(0xFFFFFDF9);

  static const textMain = Color(0xFF3F3437);
  static const textSub = Color(0xFF85787C);
  static const danger = Color(0xFFC94A4A);

  /// 흐린 글자, 전송되지 않은 말풍선
  static const textMuted = Color(0xFFB0A5A8);

  /// 빈 화면 아이콘
  static const iconMuted = Color(0xFFE7C9D1);

  /// 진행 막대 배경, 구분선
  static const track = Color(0xFFF2E6E2);

  /// 선택된 항목 배경(연한 핑크)
  static const primaryLight = Color(0xFFFCE4EA);

  /// 베이비 블루: 아기 얼굴 배경 등 보조 포인트
  static const babyBlue = Color(0xFFDCEEFA);

  /// 사용자 말풍선(연한 핑크)
  static const userBubble = Color(0xFFFBD9E2);

  /// 아기(AI) 말풍선
  static const babyBubble = Colors.white;

  /// 데모 모드 안내 배너 배경
  static const warningBackground = Color(0xFFFFF1DC);
}

/// 부드러운 그림자. 카드·말풍선·입력창에 함께 쓴다.
const softShadow = [
  BoxShadow(color: Color(0x14B0707F), blurRadius: 16, offset: Offset(0, 4)),
];

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    surface: AppColors.surface,
    error: AppColors.danger,
  );
  const stadium = StadiumBorder();

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textMain,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: stadium,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(shape: stadium),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: stadium),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.textMain,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.track, thickness: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
      circularTrackColor: AppColors.primaryLight,
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      iconColor: AppColors.textSub,
    ),
  );
}

/// 입력창 공통 모양: 둥근 모서리, 평소에는 테두리 없음, 입력 중에는 핑크 테두리.
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
  double radius = 16,
}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(radius),
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
