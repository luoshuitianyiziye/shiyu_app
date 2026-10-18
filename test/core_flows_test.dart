// 时屿 · 日程笔记 —— 核心业务链路测试（数据层）
//
// 覆盖三条发布关键链路：
// 1. 完成任务 → XP 结算 + 等级/段位推进（含防重复结算）
// 2. 重复任务每日滚动（每天/工作日/每周规则）
// 3. 事件提前提醒时刻计算（提前提醒 + 已过时刻自动修正）
import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shiyu_app/core/db/database.dart';
import 'package:shiyu_app/core/utils/remind_calc.dart';
import 'package:shiyu_app/features/growth/data/ranks.dart';
import 'package:shiyu_app/features/notes/data/text_import.dart';

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

    test('取消完成后再完成不重复结算（防完成→取消→再完成刷经验）', () async {
      final today = DateTime.now();
      final todayDay = DateTime(today.year, today.month, today.day);

      final id = await db.addTask(
        TasksCompanion.insert(
          title: '取消后再完成',
          date: todayDay,
          quadrant: const Value(2),
          difficulty: const Value(2),
        ),
      );
      var task = (await db.tasksForDate(todayDay)).firstWhere((t) => t.id == id);

      // 第一次完成：结算 XP
      final first = await db.completeTaskAndAwardXp(task);
      expect(first.xp, greaterThan(0));
      final userAfterFirst = await db.ensureUser();

      // 取消完成（XP 不回收获益，但任务回到未完成）
      await db.uncompleteTask(task);
      final refreshed = (await db.tasksForDate(todayDay)).firstWhere((t) => t.id == id);
      expect(refreshed.isDone, isFalse);
      expect(refreshed.xpAwarded, greaterThan(0)); // 保留历史结算标记

      // 再次完成：只恢复完成状态，不重复结算 XP（防刷）
      task = refreshed;
      final second = await db.completeTaskAndAwardXp(task);
      expect(second.xp, 0);
      final userAfterSecond = await db.ensureUser();
      expect(userAfterSecond.xpTotal, userAfterFirst.xpTotal);

      // 任务恢复为已完成
      final done = (await db.tasksForDate(todayDay)).firstWhere((t) => t.id == id);
      expect(done.isDone, isTrue);
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

  group('重复任务每日滚动（单条模型）', () {
    test('每天任务：昨天未完成 → 推进到今天、仍为未完成、不产生副本', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));

      final id = await db.addTask(
        TasksCompanion.insert(
          title: '每日打卡',
          date: yesterday,
          quadrant: const Value(2),
          repeatRule: const Value('daily'),
        ),
      );

      final rolled = await db.rollRepeatingTasks();
      expect(rolled, contains(id));

      final todayTasks = await db.tasksForDate(today);
      final matched = todayTasks.where((t) => t.title == '每日打卡').toList();
      expect(matched, hasLength(1), reason: '不应隔天多生成副本');
      final task = matched.first;
      expect(task.id, id, reason: '推进的是同一条记录');
      expect(task.isDone, isFalse);
      expect(task.date, today);
      expect(task.repeatRule, 'daily', reason: '重复标记保留在活记录上');

      // 幂等：再次推进不会重复
      final rolled2 = await db.rollRepeatingTasks();
      expect(rolled2, isEmpty);
    });

    test('每天任务：昨天已完成 → 次日复位为未完成（回到正常栏）', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));

      final id = await db.addTask(
        TasksCompanion.insert(
          title: '完成后次日复位',
          date: yesterday,
          quadrant: const Value(2),
          repeatRule: const Value('daily'),
        ),
      );
      // 模拟昨天已完成（含 XP 结算标记）
      await (db.update(db.tasks)..where((t) => t.id.equals(id))).write(
        const TasksCompanion(
          isDone: Value(true),
          doneAt: Value(null),
          xpAwarded: Value(10),
        ),
      );

      final rolled = await db.rollRepeatingTasks();
      expect(rolled, contains(id));

      final task = (await db.tasksForDate(today)).firstWhere((t) => t.id == id);
      expect(task.isDone, isFalse, reason: '已完成 → 次日从已完成栏回到正常栏');
      expect(task.date, today);
      expect(task.xpAwarded, 0, reason: '新的一天重新结算，当天防刷不受影响');
    });

    test('每天任务：连续多天未完成 → 仍只有一条、推进到今天', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final fiveDaysAgo = today.subtract(const Duration(days: 5));

      final id = await db.addTask(
        TasksCompanion.insert(
          title: '跨多天未完成',
          date: fiveDaysAgo,
          quadrant: const Value(2),
          repeatRule: const Value('daily'),
        ),
      );

      await db.rollRepeatingTasks();
      final task = (await db.tasksForDate(today)).firstWhere((t) => t.id == id);
      expect(task.date, today);
      expect(task.isDone, isFalse);
      expect(
        (await db.tasksForDate(today)).where((t) => t.title == '跨多天未完成'),
        hasLength(1),
      );
    });

    test('工作日任务：周六/周日不推进', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      // 找一个周六作为模板日期（模板必须早于今天才会被选中）
      final saturday = _previousWeekday(today, 6);

      final id = await db.addTask(
        TasksCompanion.insert(
          title: '工作日任务',
          date: saturday,
          quadrant: const Value(3),
          repeatRule: const Value('weekdays'),
        ),
      );
      final rolled = await db.rollRepeatingTasks();
      if (today.weekday >= 6) {
        expect(rolled, isEmpty, reason: '周末不推进');
      } else {
        expect(rolled, contains(id));
      }
    });

    test('每周任务：只在原星期几推进', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final lastWeek = today.subtract(const Duration(days: 7));

      final id = await db.addTask(
        TasksCompanion.insert(
          title: '每周复盘',
          date: lastWeek,
          quadrant: const Value(2),
          repeatRule: const Value('weekly'),
        ),
      );

      final rolled = await db.rollRepeatingTasks();
      if (today.weekday == lastWeek.weekday) {
        expect(rolled, contains(id));
      } else {
        expect(rolled, isEmpty);
      }
    });
  });

  group('事件提前提醒时刻', () {
    test('有具体时间：提醒 = 事件时间 - remindMinutes', () {
      final time = DateTime(2026, 10, 1, 14, 30);
      final remindAt = computeEventRemindAt(
        date: time,
        time: time,
        remindMinutes: 15,
        now: DateTime(2026, 10, 1, 8, 0),
      );
      expect(remindAt, DateTime(2026, 10, 1, 14, 15));
    });

    test('提前 1 天：提醒 = 前一天同时刻', () {
      final time = DateTime(2026, 12, 25, 10, 0);
      final remindAt = computeEventRemindAt(
        date: time,
        time: time,
        remindMinutes: 1440,
        now: DateTime(2026, 12, 1, 8, 0),
      );
      expect(remindAt, DateTime(2026, 12, 24, 10, 0));
    });

    test('提醒时刻已过去但事件未发生：修正为 1 分钟后提醒', () {
      // 事件在 10 分钟后，提前 15 分钟 → 提醒时刻已过 → 修正为 now+1min
      final now = DateTime(2026, 6, 1, 12, 0);
      final eventAt = now.add(const Duration(minutes: 10));
      final remindAt = computeEventRemindAt(
        date: DateTime(eventAt.year, eventAt.month, eventAt.day),
        time: eventAt,
        remindMinutes: 15,
        now: now,
      );
      expect(remindAt.isAfter(now), isTrue);
      expect(remindAt.difference(now).inMinutes, lessThanOrEqualTo(2));
    });

    test('全天事件：以当天 09:00 为基准提前 remindMinutes', () {
      final remindAt = computeEventRemindAt(
        date: DateTime(2026, 11, 5),
        time: null,
        remindMinutes: 15,
        now: DateTime(2026, 11, 5, 8, 0),
      );
      // 09:00 - 15min = 08:45（早于当天 00:00 才钳制，这里不触发）
      expect(remindAt, DateTime(2026, 11, 5, 8, 45));
    });

    test('全天事件提前 1 天：下限钳到当天 00:00', () {
      // 事件在未来的某天：09:00 - 24h = 前一天 09:00，早于当天 00:00 → 钳到当天 00:00
      // （事件在未来，提醒时刻尚未过去，不触发「修正为 now+1min」）
      final remindAt = computeEventRemindAt(
        date: DateTime(2027, 1, 5),
        time: null,
        remindMinutes: 1440,
        now: DateTime(2026, 11, 5, 8, 0),
      );
      expect(remindAt, DateTime(2027, 1, 5, 0, 0));
    });
  });

  group('导入文本自动切分', () {
    test('无空行：每行一条', () {
      expect(splitImportText('a\nb\nc'), ['a', 'b', 'c']);
    });

    test('含空行：按空行分段，段内换行保留', () {
      expect(splitImportText('第一段\n第二行\n\n第二段'), ['第一段\n第二行', '第二段']);
    });

    test('分隔线视为条目边界（--- / ===）', () {
      expect(splitImportText('账号：x\n---\n密码：y'), ['账号：x', '密码：y']);
    });

    test('空文本/全空白返回空列表', () {
      expect(splitImportText('   \n  \n'), isEmpty);
      expect(splitImportText(''), isEmpty);
    });

    test('buildEntriesBody 生成可解析的 Quill Delta（段落以换行结尾）', () {
      final json = buildEntriesBody(['条目一', '条目二']);
      final decoded = jsonDecode(json) as List;
      expect(decoded, isNotEmpty);
      expect(decoded.last['insert'], '\n'); // Quill 段落结束
      expect(
        decoded.map((op) => (op as Map)['insert']).join(),
        contains('条目一'),
      );
      expect(
        decoded.map((op) => (op as Map)['insert']).join(),
        contains('条目二'),
      );
    });
  });
}

/// 找到 [yearMonthDay] 之前（含当天）最近的星期 [weekday]（1=周一..7=周日）
DateTime _previousWeekday(DateTime day, int weekday) {
  var d = day;
  while (d.weekday != weekday) {
    d = d.subtract(const Duration(days: 1));
  }
  return d;
}
