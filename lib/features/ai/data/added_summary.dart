import 'task_draft.dart';

/// 汇总已添加任务的日期分布（用于完成提示）。
///
/// 未来日期的任务不会出现在今日页，提示里写明日期可避免「以为没添加成功」。
String summarizeAddedTasks(List<TaskDraft> added, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  var todayCount = 0;
  final otherDates = <String, int>{};
  for (final draft in added) {
    final date = draft.effectiveDate;
    if (date == today) {
      todayCount++;
    } else {
      final label = '${date.month}月${date.day}日';
      otherDates[label] = (otherDates[label] ?? 0) + 1;
    }
  }
  final parts = <String>[];
  if (todayCount > 0) parts.add('今天 $todayCount 个');
  otherDates.forEach((label, count) => parts.add('$label $count 个'));
  return '已添加 ${added.length} 个任务（${parts.join('、')}）';
}
