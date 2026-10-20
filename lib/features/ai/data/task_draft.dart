import 'package:flutter/material.dart';

/// AI 生成的任务草案（尚未落库，用户确认后才创建）
class TaskDraft {
  TaskDraft({
    required this.title,
    this.quadrant = 2,
    this.difficulty = 2,
    this.date,
    this.startTime,
    this.repeatRule = 'none',
  });

  String title;

  /// 四象限 1-4
  int quadrant;

  /// 难度 1-3
  int difficulty;

  /// 任务日期（null = 今天）
  DateTime? date;

  /// 开始时段（null = 不设提醒）
  TimeOfDay? startTime;

  /// 重复规则 none/daily/weekdays/weekly
  String repeatRule;

  /// 实际落库日期（null 视为今天，零点对齐）
  DateTime get effectiveDate {
    final now = DateTime.now();
    final d = date ?? DateTime(now.year, now.month, now.day);
    return DateTime(d.year, d.month, d.day);
  }

  /// 开始时间（日期 + 时分）
  DateTime? get startDateTime {
    final t = startTime;
    if (t == null) return null;
    final d = effectiveDate;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }
}
