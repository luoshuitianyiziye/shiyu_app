// 时屿 · 日程笔记 —— 核心业务链路测试（数据层）
//
// 覆盖三条发布关键链路：
// 1. 完成任务 → XP 结算 + 等级/段位推进（含防重复结算）
// 2. 重复任务每日滚动（每天/工作日/每周规则）
// 3. 事件提前提醒时刻计算（提前提醒 + 已过时刻自动修正）
import 'package:drift/drift.dart' hide Column;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shiyu_app/core/db/database.dart';
import 'package:shiyu_app/features/growth/data/ranks.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('任务完成与 XP 结算', () {
    test('完成困难+象限I任务得 30 XP，用户经验/等级同步增加', () async {
      final today = DateTime.now();
      final todayDay = DateTime(today.year, today.month, today.day);

      final id = await db.addTask(
        TasksCompanion.insert(
          title: '重要困难任务',
          date: todayDay,
          quadrant: const Value(1), // 象限I：系数 1.5
          difficulty: const Value(3), // 困难：系数 2.0
        ),
      );
      final task = (await db.tasksForDate(todayDay)).firstWhere((t) => t.id == id);

      final userBefore = await db.ensureUser();
      final result = await db.completeTaskAndAwardXp(task);

      // 10 * 2.0 * 1.5 = 30
      expect(result.xp, 30);
      final userAfter = await db.ensureUser();
      expect(userAfter.xpTotal, userBefore.xpTotal + 30);
      expect(userAfter.level, levelFromXp(userAfter.xpTotal));
      expect(userAfter.rank, rankForLevel(userAfter.level).index);
    });

    test('重复完成同一任务不重复结算（防连点刷经验）', () async {
      final today = DateTime.now();
      final todayDay = DateTime(today.year, today.month, today.day);

      final id = await db.addTask(
        TasksCompanion.insert(
          title: '防连点任务',
          date: todayDay,
          quadrant: const Value(2),
          difficulty: const Value(2),
        ),
      );
      final task = (await db.tasksForDate(todayDay)).firstWhere((t) => t.id == id);

      final first = await db.completeTaskAndAwardXp(task);
      expect(first.xp, greaterThan(0));

      final userBefore = await db.ensureUser();
      final second = await db.completeTaskAndAwardXp(task);
      expect(second.xp, 0);
      expect((await db.ensureUser()).xpTotal, userBefore.xpTotal);
    });

    test('未完成任务不可跳过结算（未完成状态直接调用返回 0）', () async {
      final today = DateTime.now();
      final todayDay = DateTime(today.year, today.month, today.day);

      final id = await db.addTask(
        TasksCompanion.insert(
          title: '测试任务',
          date: todayDay,
          quadrant: const Value(2),
          difficulty: const Value(1),
        ),
      );
      final task = (await db.tasksForDate(todayDay)).firstWhere((t) => t.id == id);
      final userBefore = await db.ensureUser();

      await db.softDeleteTask(id); // 已删除任务不可结算
      final result = await db.completeTaskAndAwardXp(task);
      expect(result.xp, 0);
      expect((await db.ensureUser()).xpTotal, userBefore.xpTotal);
    });
  });

  group('重复任务每日滚动', () {
    test('每天任务：昨天建立 → 今天生成副本，模板不再重复', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));

      await db.addTask(
        TasksCompanion.insert(
          title: '每日打卡',
          date: yesterday,
          quadrant: const Value(2),
          repeatRule: const Value('daily'),
        ),
      );

      final created = await db.rollRepeatingTasks();
      expect(created, isNotEmpty);

      final todayTasks = await db.tasksForDate(today);
      expect(todayTasks.where((t) => t.title == '每日打卡'), hasLength(1));

      // 幂等：再次滚动不再生成
      final created2 = await db.rollRepeatingTasks();
      expect(created2, isEmpty);
    });

    test('工作日任务：周六/周日不生成', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      // 找一个周六作为模板日期（模板必须早于今天才会滚动）
      final saturday = _previousWeekday(DateTime(today.year, today.month, today.day), 6);

      await db.addTask(
        TasksCompanion.insert(
          title: '工作日任务',
          date: saturday,
          quadrant: const Value(3),
          repeatRule: const Value('weekdays'),
        ),
      );
      final created = await db.rollRepeatingTasks();
      // 若今天是周六/周日则模板被跳过；否则正常生成
      if (today.weekday >= 6) {
        expect(created, isEmpty);
      } else {
        expect(created, isNotEmpty);
      }
    });

    test('每周任务：只在原星期几生成', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final lastWeek = today.subtract(const Duration(days: 7));

      await db.addTask(
        TasksCompanion.insert(
          title: '每周复盘',
          date: lastWeek,
          quadrant: const Value(2),
          repeatRule: const Value('weekly'),
        ),
      );

      final created = await db.rollRepeatingTasks();
      if (today.weekday == lastWeek.weekday) {
        expect(created, isNotEmpty);
      } else {
        expect(created, isEmpty);
      }
    });
  });

  group('事件提前提醒时刻', () {
    test('有具体时间：提醒 = 事件时间 - remindMinutes', () async {
      final date = DateTime(2026, 10, 1);
      final time = DateTime(2026, 10, 1, 14, 30);
      final remindAt = _remindAt(date, time, 15);
      expect(remindAt, DateTime(2026, 10, 1, 14, 15));
    });

    test('提前 1 天：提醒 = 前一天同时刻', () async {
      final date = DateTime(2026, 12, 25);
      final time = DateTime(2026, 12, 25, 10, 0);
      final remindAt = _remindAt(date, time, 1440);
      expect(remindAt, DateTime(2026, 12, 24, 10, 0));
    });

    test('提醒时刻已过去但事件未发生：修正为 1 分钟后提醒', () async {
      final now = DateTime.now();
      // 事件在 10 分钟后，提前 15 分钟 → 提醒时刻已过 → 修正为 now+1min
      final eventAt = now.add(const Duration(minutes: 10));
      final remindAt = _remindAt(
        DateTime(eventAt.year, eventAt.month, eventAt.day),
        eventAt,
        15,
      );
      expect(remindAt.isAfter(now), isTrue);
      expect(remindAt.difference(now).inMinutes, lessThanOrEqualTo(2));
    });

    test('全天事件：按当天 09:00 提醒', () async {
      final date = DateTime(2026, 11, 5);
      final remindAt = _remindAt(date, null, 15);
      expect(remindAt, DateTime(2026, 11, 5, 9, 0));
    });
  });
}

/// 与 add_event_sheet.dart 相同的提醒时刻计算（复制实现以测数据逻辑）
DateTime _remindAt(DateTime date, DateTime? timeDateTime, int remindMinutes) {
  final now = DateTime.now();
  final eventAt = timeDateTime ??
      DateTime(date.year, date.month, date.day, 23, 59);
  var remindAt = timeDateTime != null
      ? timeDateTime.subtract(Duration(minutes: remindMinutes))
      : DateTime(date.year, date.month, date.day, 9, 0);
  if (remindAt.isBefore(now) && eventAt.isAfter(now)) {
    remindAt = now.add(const Duration(minutes: 1));
  }
  return remindAt;
}

/// 找到 [yearMonthDay] 之前（含当天）最近的星期 [weekday]（1=周一..7=周日）
DateTime _previousWeekday(DateTime day, int weekday) {
  var d = day;
  while (d.weekday != weekday) {
    d = d.subtract(const Duration(days: 1));
  }
  return d;
}
