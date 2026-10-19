import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../models/todo.dart';
import 'todo_field_decoration.dart';
import 'todo_filter_chip.dart';

enum TodoStatusFilter {
  all('전체'),
  active('진행 중'),
  done('완료');

  const TodoStatusFilter(this.label);

  final String label;
}

/// 제목 검색창과 상태·카테고리 필터 칩.
class TodoFilters extends StatelessWidget {
  const TodoFilters({
    super.key,
    required this.searchController,
    required this.statusFilter,
    required this.categoryFilter,
    required this.onStatusChanged,
    required this.onCategoryChanged,
  });

  final TextEditingController searchController;
  final TodoStatusFilter statusFilter;

  /// null이면 모든 카테고리
  final TodoCategory? categoryFilter;
  final ValueChanged<TodoStatusFilter> onStatusChanged;
  final ValueChanged<TodoCategory?> onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('searchInput'),
          controller: searchController,
          textInputAction: TextInputAction.search,
          decoration: todoFieldDecoration(
            hintText: '제목으로 검색',
            fillColor: Colors.white,
            prefixIcon: const Icon(Icons.search, color: AppColors.textSub),
            suffixIcon: searchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: '검색어 지우기',
                    icon: const Icon(Icons.close, color: AppColors.textSub),
                    onPressed: searchController.clear,
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in TodoStatusFilter.values)
              TodoFilterChip(
                label: f.label,
                selected: statusFilter == f,
                onSelected: () => onStatusChanged(f),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            TodoFilterChip(
              label: '모든 카테고리',
              selected: categoryFilter == null,
              onSelected: () => onCategoryChanged(null),
            ),
            for (final c in TodoCategory.values)
              TodoFilterChip(
                label: c.label,
                icon: c.icon,
                iconColor: c.color,
                selected: categoryFilter == c,
                onSelected: () => onCategoryChanged(c),
              ),
          ],
        ),
      ],
    );
  }
}
