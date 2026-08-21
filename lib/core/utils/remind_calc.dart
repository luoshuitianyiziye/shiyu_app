/// 日历事件「提前提醒时刻」计算（纯函数，UI 与测试共用同一实现）。
///
/// 规则：
/// - 有具体时间：提醒 = 事件时间 - remindMinutes
/// - 全天事件（time 为 null）：以当天 09:00 为基准提前 remindMinutes，
///   下限钳到当天 00:00
/// - 提醒时刻已过去但事件尚未发生：修正为 [now] + 1 分钟后提醒
///   （避免提前提醒被静默丢弃）
DateTime computeEventRemindAt({
  required DateTime date,
  DateTime? time,
  required int remindMinutes,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  // 全天事件视为当天 23:59 发生（用于判断是否已过去）
  final eventAt = time ?? DateTime(date.year, date.month, date.day, 23, 59);
  final DateTime remindAt;
  if (time != null) {
    remindAt = time.subtract(Duration(minutes: remindMinutes));
  } else {
    final base = DateTime(date.year, date.month, date.day, 9, 0);
    final early = base.subtract(Duration(minutes: remindMinutes));
    final dayStart = DateTime(date.year, date.month, date.day);
    remindAt = early.isBefore(dayStart) ? dayStart : early;
  }
  if (remindAt.isBefore(current) && eventAt.isAfter(current)) {
    return current.add(const Duration(minutes: 1));
  }
  return remindAt;
}
