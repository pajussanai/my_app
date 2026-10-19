import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../models/todo.dart';
import 'todo_field_decoration.dart';
import 'todo_option_pickers.dart';

/// 새 할 일 입력창과 추가 버튼, 카테고리·중요도·마감일 선택.
class TodoInputCard extends StatelessWidget {
  const TodoInputCard({
    super.key,
    required this.controller,
    required this.adding,
    required this.onAdd,
    required this.category,
    required this.priority,
    required this.dueDate,
    required this.onCategoryChanged,
    required this.onPriorityChanged,
    required this.onDueDateChanged,
  });

  final TextEditingController controller;

  /// 서버 응답을 기다리는 중이면 입력과 버튼을 막는다.
  final bool adding;
  final VoidCallback onAdd;

  final TodoCategory category;
  final TodoPriority priority;
  final DateTime? dueDate;
  final ValueChanged<TodoCategory> onCategoryChanged;
  final ValueChanged<TodoPriority> onPriorityChanged;
  final ValueChanged<DateTime?> onDueDateChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('todoInput'),
                    controller: controller,
                    enabled: !adding,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => onAdd(),
                    decoration: todoFieldDecoration(
                      hintText: '할 일을 입력하세요',
                      fillColor: AppColors.background,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: adding ? null : onAdd,
                    icon: adding
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add, size: 20),
                    label: const Text('추가'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TodoOptionPickers(
              category: category,
              priority: priority,
              dueDate: dueDate,
              onCategoryChanged: onCategoryChanged,
              onPriorityChanged: onPriorityChanged,
              onDueDateChanged: onDueDateChanged,
            ),
          ],
        ),
      ),
    );
  }
}
