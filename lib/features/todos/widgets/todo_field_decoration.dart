import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// 할 일 화면의 입력창(할 일 입력, 제목 검색) 모양.
InputDecoration todoFieldDecoration({
  required String hintText,
  required Color fillColor,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  return appFieldDecoration(
    hintText: hintText,
    hintStyle: const TextStyle(color: AppColors.textSub),
    fillColor: fillColor,
    isDense: true,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  );
}
