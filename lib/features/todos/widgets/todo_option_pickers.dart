import 'dart:math';

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/date_utils.dart';
import '../../../models/todo.dart';

/// 카테고리·중요도·마감일 선택 버튼 묶음. 추가 입력창과 수정 화면에서 함께 쓴다.
class TodoOptionPickers extends StatelessWidget {
  const TodoOptionPickers({
    super.key,
    required this.category,
    required this.priority,
    required this.dueDate,
    required this.onCategoryChanged,
    required this.onPriorityChanged,
    required this.onDueDateChanged,
    this.keyPrefix = '',
  });

  final TodoCategory category;
  final TodoPriority priority;
  final DateTime? dueDate;
  final ValueChanged<TodoCategory> onCategoryChanged;
  final ValueChanged<TodoPriority> onPriorityChanged;
  final ValueChanged<DateTime?> onDueDateChanged;

  /// 같은 화면에 두 번 나올 때(추가 입력창 + 수정 화면) 테스트 키를 구분한다.
  final String keyPrefix;

  Future<void> _pickDueDate(BuildContext context) async {
    final today = dateOnly(DateTime.now());
    final current = dueDate;
    // 이미 정해진 마감일이 선택 범위 밖이어도 열 수 있게 범위를 넓힌다.
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? today,
      firstDate: DateTime(min(today.year - 1, current?.year ?? today.year)),
      lastDate: DateTime(max(today.year + 10, current?.year ?? 0), 12, 31),
      helpText: '마감일 선택',
      cancelText: '취소',
      confirmText: '확인',
    );
    if (picked != null) onDueDateChanged(dateOnly(picked));
  }

  @override
  Widget build(BuildContext context) {
    final dueDate = this.dueDate;
    final menuShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        PopupMenuButton<TodoCategory>(
          key: Key('${keyPrefix}categoryPicker'),
          tooltip: '카테고리 선택',
          initialValue: category,
          color: Colors.white,
          shape: menuShape,
          onSelected: onCategoryChanged,
          itemBuilder: (_) => [
            for (final c in TodoCategory.values)
              PopupMenuItem(
                value: c,
                child: _MenuRow(icon: c.icon, color: c.color, label: c.label),
              ),
          ],
          child: _PickerChip(
            icon: category.icon,
            color: category.color,
            label: category.label,
          ),
        ),
        PopupMenuButton<TodoPriority>(
          key: Key('${keyPrefix}priorityPicker'),
          tooltip: '중요도 선택',
          initialValue: priority,
          color: Colors.white,
          shape: menuShape,
          onSelected: onPriorityChanged,
          itemBuilder: (_) => [
            for (final p in TodoPriority.values)
              PopupMenuItem(
                value: p,
                child: _MenuRow(
                  icon: Icons.flag,
                  color: p.color,
                  label: p.label,
                ),
              ),
          ],
          child: _PickerChip(
            icon: Icons.flag,
            color: priority.color,
            label: '중요도 ${priority.label}',
          ),
        ),
        InkWell(
          key: Key('${keyPrefix}dueDatePicker'),
          onTap: () => _pickDueDate(context),
          borderRadius: BorderRadius.circular(10),
          child: _PickerChip(
            icon: Icons.event,
            color: dueDate == null ? AppColors.textSub : AppColors.primary,
            label: dueDate == null
                ? '마감일 선택'
                : '마감 ${formatDueDate(dueDate, dateOnly(DateTime.now()))}',
            trailing: dueDate == null
                ? null
                : InkResponse(
                    key: Key('${keyPrefix}clearDueDate'),
                    onTap: () => onDueDateChanged(null),
                    radius: 16,
                    child: const Tooltip(
                      message: '마감일 지우기',
                      child: Icon(
                        Icons.close,
                        size: 16,
                        color: AppColors.textSub,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// 추가 입력창 아래에서 카테고리·중요도·마감일을 고르는 작은 버튼 모양.
class _PickerChip extends StatelessWidget {
  const _PickerChip({
    required this.icon,
    required this.color,
    required this.label,
    this.trailing,
  });

  final IconData icon;
  final Color color;
  final String label;

  /// 없으면 드롭다운 화살표를 표시한다.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Ink(
      height: 36,
      padding: const EdgeInsets.only(left: 10, right: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppColors.textMain),
            ),
          ),
          const SizedBox(width: 2),
          trailing ??
              const Icon(
                Icons.arrow_drop_down,
                size: 18,
                color: AppColors.textSub,
              ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}
