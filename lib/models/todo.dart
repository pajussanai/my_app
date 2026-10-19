import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../core/date_utils.dart';

enum TodoCategory {
  work('업무', Icons.work_outline, Color(0xFF2563EB)),
  personal('개인', Icons.person_outline, Color(0xFF7C3AED)),
  exercise('운동', Icons.fitness_center, Color(0xFF059669)),
  other('기타', Icons.label_outline, Color(0xFF64748B));

  const TodoCategory(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;

  /// 저장된 값('work' 또는 '업무')이 없거나 알 수 없으면 '기타'로 처리한다.
  static TodoCategory fromName(Object? name) => values.firstWhere(
    (c) => c.name == name || c.label == name,
    orElse: () => other,
  );
}

enum TodoPriority {
  high('높음', AppColors.danger),
  medium('보통', Color(0xFFD97706)),
  low('낮음', Color(0xFF6B7280));

  const TodoPriority(this.label, this.color);

  final String label;
  final Color color;

  /// 저장된 값('high' 또는 '높음')이 없거나 알 수 없으면 '보통'으로 처리한다.
  static TodoPriority fromName(Object? name) => values.firstWhere(
    (p) => p.name == name || p.label == name,
    orElse: () => medium,
  );
}

class Todo {
  const Todo({
    required this.id,
    required this.title,
    this.done = false,
    this.category = TodoCategory.other,
    this.priority = TodoPriority.medium,
    this.dueDate,
    this.createdAt,
  });

  /// Supabase public.todos 행을 읽는다. 비어 있거나 알 수 없는 값은 기본값으로 채운다.
  factory Todo.fromRow(Map<String, dynamic> row) {
    return Todo(
      id: row['id'] as String,
      title: row['title'] as String? ?? '',
      done: row['is_completed'] as bool? ?? false,
      category: TodoCategory.fromName(row['category']),
      priority: TodoPriority.fromName(row['priority']),
      dueDate: parseIsoDate(row['due_date']),
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? ''),
    );
  }

  /// 서버 연결 전 버전이 기기에 저장한 형식을 읽는다.
  /// 새 필드가 없는 이전 버전 데이터는 기본값으로 채운다.
  factory Todo.fromJson(Map<String, dynamic> json) {
    return Todo(
      id: json['id'] as String,
      title: json['title'] as String,
      done: json['done'] as bool? ?? false,
      category: TodoCategory.fromName(json['category']),
      priority: TodoPriority.fromName(json['priority']),
      dueDate: parseIsoDate(json['dueDate']),
    );
  }

  final String id;
  final String title;
  final bool done;
  final TodoCategory category;
  final TodoPriority priority;

  /// 시각 없이 날짜만 사용한다. null이면 마감일 없음.
  final DateTime? dueDate;

  /// 서버에서 정한 생성 시각. 아직 저장 전이면 null.
  final DateTime? createdAt;

  bool isOverdue(DateTime today) =>
      !done && dueDate != null && dueDate!.isBefore(dateOnly(today));

  Todo copyWith({
    String? id,
    String? title,
    bool? done,
    TodoCategory? category,
    TodoPriority? priority,
    DateTime? dueDate,
    bool clearDueDate = false,
    DateTime? createdAt,
  }) => Todo(
    id: id ?? this.id,
    title: title ?? this.title,
    done: done ?? this.done,
    category: category ?? this.category,
    priority: priority ?? this.priority,
    dueDate: clearDueDate ? null : dueDate ?? this.dueDate,
    createdAt: createdAt ?? this.createdAt,
  );

  /// public.todos에 보낼 값. [userId]가 있으면 user_id도 넣는다(추가할 때).
  Map<String, dynamic> toRow({String? userId}) => {
    'id': id,
    'user_id': ?userId,
    'title': title,
    'category': category.name,
    'priority': priority.name,
    'due_date': dueDate == null ? null : toIsoDate(dueDate!),
    'is_completed': done,
    'created_at': ?createdAt?.toUtc().toIso8601String(),
  };
}
