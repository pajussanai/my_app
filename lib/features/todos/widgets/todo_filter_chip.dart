import 'package:flutter/material.dart';

import '../../../app/theme.dart';

class TodoFilterChip extends StatelessWidget {
  const TodoFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
    this.iconColor,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      avatar: icon == null ? null : Icon(icon, size: 16, color: iconColor),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
      backgroundColor: Colors.white,
      selectedColor: AppColors.primaryLight,
      side: BorderSide(color: selected ? AppColors.primary : AppColors.track),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      labelStyle: TextStyle(
        fontSize: 13,
        color: selected ? AppColors.primary : AppColors.textMain,
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}
