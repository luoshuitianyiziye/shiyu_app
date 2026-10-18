import '../db/database.dart';
import 'notification_service.dart';

/// 提醒协调器：把「任务/事件 → 系统通知」的同步模式收敛到一处，
/// 避免各页面重复写「先 cancel 再 schedule」的编排（也统一了「何时该提醒」）。
///
/// 所有方法都在 [NotificationService] 未初始化时安全空转（测试/预览环境）。
class ReminderCoordinator {
  ReminderCoordinator._();

  /// 同步任务开始提醒：按任务当前状态重建。
  /// - [startTime] 为空或已过 → 只取消已有提醒；
  /// - 未过 → 取消旧提醒后按新时间重新调度。
  static Future<void> syncTaskReminder({
    required int taskId,
    required String title,
    DateTime? startTime,
  }) async {
    await NotificationService.instance.cancelTaskReminder(taskId);
    if (startTime == null) return;
    await NotificationService.instance.scheduleTaskReminder(
      taskId: taskId,
      title: title,
      at: startTime,
    );
  }

  /// 取消任务提醒（完成/删除任务时调用）
  static Future<void> cancelTaskReminder(int taskId) =>
      NotificationService.instance.cancelTaskReminder(taskId);

  /// 同步事件提醒：取消旧提醒后按新时刻重新调度（新增/编辑事件时调用）
  static Future<void> syncEventReminder({
    required int eventId,
    required String title,
    required DateTime at,
  }) async {
    await NotificationService.instance.cancelEventReminder(eventId);
    await NotificationService.instance.scheduleEventReminder(
      eventId: eventId,
      title: title,
      at: at,
    );
  }

  /// 取消事件提醒（删除事件时调用）
  static Future<void> cancelEventReminder(int eventId) =>
      NotificationService.instance.cancelEventReminder(eventId);
}

/// 任务列表变化（新增/完成/恢复/删除）后调用：用最新未完成数重建每日收尾提醒。
///
/// 并发安全：连续快速变化（如连点完成多个任务）时多个调用交错执行，
/// 用单调递增版本号做 last-write-wins —— 只有最新一次调用的结果会被保留，
/// 旧的（可能读取到过期计数）结果会被丢弃。
Future<void> rescheduleEndOfDay(AppDatabase db) async {
  final version = ++_endOfDayVersion;
  final s = await db.ensureSettings();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final count = await db.unfinishedCountForDate(today);
  // 已有更新的重建请求 → 本次结果过期，丢弃（避免旧计数覆盖新计数）
  if (version != _endOfDayVersion) return;
  await NotificationService.instance.scheduleDailyEndOfDay(
    hour: s.endOfDayHour,
    minute: s.endOfDayMinute,
    unfinishedCount: count,
  );
}

/// 收尾提醒重建版本号（last-write-wins 串行化用）
int _endOfDayVersion = 0;
