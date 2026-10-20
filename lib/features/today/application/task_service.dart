import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../../core/db/db_providers.dart';
import '../../../core/notifications/reminder_coordinator.dart';

/// 任务完成结果（UI 据此决定晋级弹窗 / 经验提示 / 静默）
class TaskCompleteOutcome {
  const TaskCompleteOutcome({
    required this.xp,
    required this.oldRank,
    required this.newRank,
    required this.repeated,
  });

  /// 本次获得经验（0 = 未结算）
  final int xp;

  /// 完成前段位
  final int oldRank;

  /// 完成后段位
  final int newRank;

  /// true = 重复完成（此前已结算过），只有完成态变化、无 XP/连胜
  final bool repeated;
}

final taskServiceProvider = Provider<TaskService>((ref) => TaskService(ref));

/// 任务应用服务：封装「DB 写入 + 开始提醒同步 + 统计/收尾提醒失效」的编排。
///
/// UI 层只调用本服务，不再直接读写数据库或调度通知，
/// 保证任何入口（今日页、弹层、未来新增页面）走同一套业务规则。
class TaskService {
  TaskService(this._ref);

  final Ref _ref;

  AppDatabase get _db => _ref.read(databaseProvider);

  /// 完成 / 取消完成（点击任务或右滑）
  Future<TaskCompleteOutcome> toggle(TaskRow task) async {
    if (task.isDone) {
      await _db.uncompleteTaskById(task.id);
      await ReminderCoordinator.syncTaskReminder(
        taskId: task.id,
        title: task.title,
        startTime: task.startTime,
      );
      _refreshStats();
      await rescheduleEndOfDay(_db);
      return const TaskCompleteOutcome(
        xp: 0,
        oldRank: 0,
        newRank: 0,
        repeated: true,
      );
    }
    final result = await _db.completeTaskAndAwardXp(task);
    await ReminderCoordinator.cancelTaskReminder(task.id);
    _refreshStats();
    await rescheduleEndOfDay(_db);
    return TaskCompleteOutcome(
      xp: result.xp,
      oldRank: result.oldRank,
      newRank: result.newRank,
      repeated: result.xp <= 0,
    );
  }

  /// 恢复已完成任务为未完成（点击已完成区 / 多选恢复）
  Future<void> uncomplete(TaskRow task) async {
    await _db.uncompleteTaskById(task.id);
    await ReminderCoordinator.syncTaskReminder(
      taskId: task.id,
      title: task.title,
      startTime: task.startTime,
    );
    _refreshStats();
    await rescheduleEndOfDay(_db);
  }

  /// 批量恢复（循环外只重建一次收尾提醒）
  Future<void> uncompleteMany(List<TaskRow> tasks) async {
    if (tasks.isEmpty) return;
    for (final task in tasks) {
      await _db.uncompleteTaskById(task.id);
      await ReminderCoordinator.syncTaskReminder(
        taskId: task.id,
        title: task.title,
        startTime: task.startTime,
      );
    }
    _refreshStats();
    await rescheduleEndOfDay(_db);
  }

  /// 软删除任务（左滑删除）
  Future<void> delete(TaskRow task) async {
    await _db.softDeleteTask(task.id);
    await ReminderCoordinator.cancelTaskReminder(task.id);
    _refreshStats();
    await rescheduleEndOfDay(_db);
  }

  /// 批量彻底删除（多选删除）
  Future<void> deleteMany(List<int> ids) async {
    if (ids.isEmpty) return;
    await _db.hardDeleteTasks(ids);
    for (final id in ids) {
      await ReminderCoordinator.cancelTaskReminder(id);
    }
    _refreshStats();
    await rescheduleEndOfDay(_db);
  }

  /// 新建任务（含开始提醒、统计与收尾提醒刷新）
  Future<int> create(
    TasksCompanion entry, {
    required String title,
    DateTime? startTime,
  }) async {
    final id = await _db.addTask(entry);
    await ReminderCoordinator.syncTaskReminder(
      taskId: id,
      title: title,
      startTime: startTime,
    );
    _refreshStats();
    await rescheduleEndOfDay(_db);
    return id;
  }

  /// 编辑任务（含开始提醒重建）
  Future<void> update(
    int id,
    TasksCompanion entry, {
    required String title,
    DateTime? startTime,
  }) async {
    await _db.updateTask(id, entry);
    await ReminderCoordinator.syncTaskReminder(
      taskId: id,
      title: title,
      startTime: startTime,
    );
  }

  void _refreshStats() => _ref.invalidate(statsSnapshotProvider);
}
