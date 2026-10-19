import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../models/todo.dart';
import 'todo_option_pickers.dart';

/// 할 일의 제목·카테고리·중요도·마감일을 고치는 대화상자.
/// 저장을 누르면 수정된 할 일을 돌려준다(서버 반영은 호출한 쪽이 한다).
class EditTodoDialog extends StatefulWidget {
  const EditTodoDialog({super.key, required this.todo});

  final Todo todo;

  @override
  State<EditTodoDialog> createState() => _EditTodoDialogState();
}

class _EditTodoDialogState extends State<EditTodoDialog> {
  late final TextEditingController _titleController = TextEditingController(
    text: widget.todo.title,
  );
  late TodoCategory _category = widget.todo.category;
  late TodoPriority _priority = widget.todo.priority;
  late DateTime? _dueDate = widget.todo.dueDate;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    Navigator.of(context).pop(
      widget.todo.copyWith(
        title: title,
        category: _category,
        priority: _priority,
        dueDate: _dueDate,
        clearDueDate: _dueDate == null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('할 일 수정'),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.all(16),
      scrollable: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: SizedBox(
        width: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('editTitleInput'),
              controller: _titleController,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: appFieldDecoration(
                hintText: '할 일 제목',
                fillColor: AppColors.background,
              ),
            ),
            const SizedBox(height: 12),
            TodoOptionPickers(
              keyPrefix: 'edit.',
              category: _category,
              priority: _priority,
              dueDate: _dueDate,
              onCategoryChanged: (c) => setState(() => _category = c),
              onPriorityChanged: (p) => setState(() => _priority = p),
              onDueDateChanged: (d) => setState(() => _dueDate = d),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: _titleController.text.trim().isEmpty ? null : _save,
          child: const Text('저장'),
        ),
      ],
    );
  }
}
