import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/date_utils.dart';
import '../../../models/todo.dart';

class TodoCard extends StatelessWidget {
  const TodoCard({
    super.key,
    required this.todo,
    required this.busy,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final Todo todo;

  /// 서버 응답을 기다리는 중이면 조작을 막고 진행 표시를 보여 준다.
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final overdue = todo.isOverdue(today);
    final dueDate = todo.dueDate;

    return Card(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: overdue
            ? BorderSide(
                color: AppColors.danger.withValues(alpha: 0.5),
                width: 1.5,
              )
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: busy ? null : onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            children: [
              if (busy)
                const SizedBox.square(
                  dimension: 24,
                  child: Padding(
                    padding: EdgeInsets.all(3),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                Icon(
                  todo.done ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: todo.done ? AppColors.primary : AppColors.iconMuted,
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      todo.title,
                      style: TextStyle(
                        fontSize: 15,
                        color: todo.done
                            ? AppColors.textMuted
                            : AppColors.textMain,
                        decoration: todo.done
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Opacity(
                      opacity: todo.done ? 0.6 : 1,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _Badge(
                            icon: todo.category.icon,
                            label: todo.category.label,
                            color: todo.category.color,
                          ),
                          _Badge(
                            icon: Icons.flag,
                            label: todo.priority.label,
                            color: todo.priority.color,
                          ),
                          if (dueDate != null)
                            overdue
                                ? _Badge(
                                    icon: Icons.event_busy,
                                    label:
                                        '기한 지남 · ${formatDueDate(dueDate, today)}',
                                    color: AppColors.danger,
                                  )
                                : _Badge(
                                    icon: Icons.event,
                                    label:
                                        '마감 ${formatDueDate(dueDate, today)}',
                                    color: AppColors.textSub,
                                  ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '수정',
                icon: const Icon(Icons.edit_outlined),
                color: AppColors.textMuted,
                visualDensity: VisualDensity.compact,
                onPressed: busy ? null : onEdit,
              ),
              IconButton(
                tooltip: '삭제',
                icon: const Icon(Icons.delete_outline),
                color: AppColors.textMuted,
                visualDensity: VisualDensity.compact,
                onPressed: busy ? null : onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
