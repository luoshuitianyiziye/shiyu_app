import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/db/database.dart';
import 'core/db/db_providers.dart';
import 'core/notifications/notification_service.dart';
import 'core/notifications/reminder_coordinator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN');

  final prefs = await SharedPreferences.getInstance();
  final nickname = ValueNotifier<String?>(prefs.getString('nickname'));

  // 数据库 + 通知初始化
  final db = AppDatabase();
  await db.ensureUser();
  await NotificationService.instance.init();
  // 收尾提醒时间与番茄参数统一存于设置表，此处读取最新值
  final settings = await db.ensureSettings();
  // 主题以设置表为单一事实来源（prefs 仅作启动缓存，二者不一致时以设置表为准）
  final themeId = ValueNotifier<String>(settings.themeId);
  if (prefs.getString('theme_id') != settings.themeId) {
    await prefs.setString('theme_id', settings.themeId);
  }

  // 重复任务滚动：把「每天/工作日/每周」任务复制到今天
  final rolledIds = await db.rollRepeatingTasks();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final dayTasks = await db.tasksForDate(today);
  for (final t in dayTasks) {
    if (rolledIds.contains(t.id)) {
      await ReminderCoordinator.syncTaskReminder(
        taskId: t.id,
        title: t.title,
        startTime: t.startTime,
      );
    }
  }

  final pendingCount = await db.unfinishedCountForDate(today);
  await NotificationService.instance.scheduleDailyEndOfDay(
    hour: settings.endOfDayHour,
    minute: settings.endOfDayMinute,
    unfinishedCount: pendingCount,
  );

  final container = ProviderContainer(
    overrides: [
      nicknameNotifierProvider.overrideWithValue(nickname),
      themeIdNotifierProvider.overrideWithValue(themeId),
      databaseProvider.overrideWithValue(db),
    ],
  );

  // 设置同步快照：启动时注入当前设置，之后随设置流保持同步（供专注页同步读取）
  container.read(settingsSnapshotProvider.notifier).update(settings);
  container.listen(
    settingsStreamProvider,
    (previous, next) =>
        next.whenData(container.read(settingsSnapshotProvider.notifier).update),
    fireImmediately: true,
  );

  // 跨午夜守护：每分钟检查日期是否翻篇 → 刷新今日列表 + 滚动重复任务
  // 带异常保护与重入防护：tick 内任一异步步骤抛错不会让当天滚动/提醒调度
  // 静默失败；tick 执行超过 1 分钟时跳过重叠的下一轮。
  var rolling = false;
  Future<void> checkDateRollover() async {
    if (rolling) return;
    rolling = true;
    try {
      final n = DateTime.now();
      final d = DateTime(n.year, n.month, n.day);
      if (d == container.read(todayDateProvider)) return;
      container.read(todayDateProvider.notifier).state = d;
      final ids = await db.rollRepeatingTasks();
      final dayTasks = await db.tasksForDate(d);
      for (final t in dayTasks) {
        if (ids.contains(t.id)) {
          await ReminderCoordinator.syncTaskReminder(
            taskId: t.id,
            title: t.title,
            startTime: t.startTime,
          );
        }
      }
      await rescheduleEndOfDay(db);
    } catch (e, st) {
      // 单轮失败不致命：记录日志，下一分钟会重试（日期守卫 + 幂等保证不重复）
      debugPrint('跨午夜滚动失败：$e\n$st');
    } finally {
      rolling = false;
    }
  }

  Timer.periodic(const Duration(minutes: 1), (_) => checkDateRollover());
  // 回到前台立即补查一次：后台期间系统可能挂起 Timer，
  // 避免「跨天恢复后今日任务/新添加任务列表滞后」。
  WidgetsBinding.instance.addObserver(_AppLifecycleChecker(checkDateRollover));

  runApp(
    UncontrolledProviderScope(container: container, child: const ShiyuApp()),
  );
}

/// App 回到前台时触发日期检查（后台定时器可能被系统挂起）
class _AppLifecycleChecker with WidgetsBindingObserver {
  _AppLifecycleChecker(this.onResumed);

  final Future<void> Function() onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(onResumed());
    }
  }
}
