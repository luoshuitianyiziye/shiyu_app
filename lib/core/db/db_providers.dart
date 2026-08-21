import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/focus/data/custom_noise.dart';
import '../../features/growth/data/stats.dart';
import 'database.dart';

/// 数据库单例（测试中可 override 为内存库）
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// 当前用户（首次访问自动创建默认用户）
final userStreamProvider = StreamProvider<UserRow>((ref) async* {
  final db = ref.watch(databaseProvider);
  await db.ensureUser();
  yield* db.watchUser();
});

/// 当前「今日」日期（零点对齐）。跨午夜由 main 中的定时器更新，
/// 更新后 [todayTasksProvider] 与今日页标题自动刷新到新一天。
final todayDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// 今日任务流
final todayTasksProvider = StreamProvider<List<TaskRow>>((ref) {
  final db = ref.watch(databaseProvider);
  final date = ref.watch(todayDateProvider);
  return db.watchTasksForDate(date);
});

/// 全部事件流（日历模块用）
final eventsStreamProvider = StreamProvider<List<EventRow>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchEvents();
});

/// 笔记列表流
final notesStreamProvider = StreamProvider<List<NoteRow>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchNotes();
});

/// 笔记分类流（用户自定义）
final noteCategoriesProvider = StreamProvider<List<NoteCategoryRow>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchNoteCategories();
});

/// 设置流（番茄时长等；首次访问自动创建默认行）
final settingsStreamProvider = StreamProvider<SettingsRow>((ref) async* {
  final db = ref.watch(databaseProvider);
  await db.ensureSettings();
  yield* db.watchSettings();
});

/// 用户上传的自定义白噪音清单（本机文档目录）
final customNoiseProvider = FutureProvider<List<CustomNoiseItem>>((ref) {
  return CustomNoiseStore.load();
});

/// 统计快照（专注 + 任务 + 成就进度）。
/// 完成任务/番茄后由对应页面调用 [invalidate] 刷新。
/// 同时监听日期变化，跨午夜后自动重算（避免今日统计停留在昨天）。
final statsSnapshotProvider = FutureProvider<StatsSnapshot>((ref) async {
  ref.watch(todayDateProvider);
  final db = ref.watch(databaseProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  // 本周（周一起）
  final weekStart = today.subtract(Duration(days: today.weekday - 1));
  final weekEnd = today.add(const Duration(days: 1));
  final sessionsThisWeek =
      await db.pomodoroSessionsBetween(weekStart, weekEnd);

  // 累计
  final allSessions =
      await db.pomodoroSessionsBetween(DateTime(2020), weekEnd);

  // 最近 7 天每日番茄数（索引 0 = 6 天前）
  final last7 = List<int>.filled(7, 0);
  final sevenDaysAgo = today.subtract(const Duration(days: 6));
  final recent = await db.pomodoroSessionsBetween(sevenDaysAgo, weekEnd);
  for (final s in recent) {
    final day = DateTime(s.completedAt.year, s.completedAt.month, s.completedAt.day);
    final diff = day.difference(sevenDaysAgo).inDays;
    if (diff >= 0 && diff < 7) last7[diff]++;
  }

  final completedTasks = await db.completedTaskCount();
  final todayStats = await db.taskStatsForDate(today);
  final user = await db.ensureUser();

  return StatsSnapshot(
    totalPomodoros: allSessions.length,
    totalMinutes: allSessions.fold(0, (a, s) => a + s.focusMinutes),
    weekPomodoros: sessionsThisWeek.length,
    weekMinutes: sessionsThisWeek.fold(0, (a, s) => a + s.focusMinutes),
    last7Days: last7,
    // 历史最高完成任务数：成就进度不随「取消完成/删除已完成任务」回退
    totalTasksDone: user.maxTasksDone > completedTasks
        ? user.maxTasksDone
        : completedTasks,
    streakDays: user.streakDays,
    rankIndex: user.rank,
    todayTotal: todayStats.total,
    todayDone: todayStats.done,
  );
});
