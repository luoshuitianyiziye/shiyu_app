// 时屿 · 日程笔记 —— 核心业务链路测试（数据层）
//
// 覆盖发布关键链路：
// 1. 完成任务 → XP 结算 + 等级/段位推进（含防重复结算）
// 2. 重复任务每日滚动（每天/工作日/每周规则）
// 3. 事件提前提醒时刻计算（提前提醒 + 已过时刻自动修正）
// 4. 导入文本切分与笔记正文
// 5. 数据备份导出 / 恢复
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_quill/flutter_quill.dart' show Document;
import 'package:flutter_test/flutter_test.dart';

import 'package:shiyu_app/core/backup/backup_service.dart';
import 'package:shiyu_app/core/db/database.dart';
import 'package:shiyu_app/core/domain/ranks.dart';
import 'package:shiyu_app/core/domain/stats.dart';
import 'package:shiyu_app/core/utils/format.dart';
import 'package:shiyu_app/core/utils/remind_calc.dart';
import 'package:shiyu_app/features/notes/data/note_body.dart';
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
      final task = (await db.tasksForDate(todayDay))
          .firstWhere((t) => t.id == id);

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
      final task = (await db.tasksForDate(todayDay))
          .firstWhere((t) => t.id == id);

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
      var task = (await db.tasksForDate(todayDay))
          .firstWhere((t) => t.id == id);

      // 第一次完成：结算 XP
      final first = await db.completeTaskAndAwardXp(task);
      expect(first.xp, greaterThan(0));
      final userAfterFirst = await db.ensureUser();

      // 取消完成（XP 不回收获益，但任务回到未完成）
      await db.uncompleteTaskById(task.id);
      final refreshed = (await db.tasksForDate(todayDay))
          .firstWhere((t) => t.id == id);
      expect(refreshed.isDone, isFalse);
      expect(refreshed.xpAwarded, greaterThan(0)); // 保留历史结算标记

      // 再次完成：只恢复完成状态，不重复结算 XP（防刷）
      task = refreshed;
      final second = await db.completeTaskAndAwardXp(task);
      expect(second.xp, 0);
      final userAfterSecond = await db.ensureUser();
      expect(userAfterSecond.xpTotal, userAfterFirst.xpTotal);

      // 任务恢复为已完成
      final done = (await db.tasksForDate(todayDay))
          .firstWhere((t) => t.id == id);
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
      final task = (await db.tasksForDate(todayDay))
          .firstWhere((t) => t.id == id);
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

    test('生成的正文可被富文本编辑器解析（Document.fromJson 不抛错）', () {
      final body = buildEntriesBody(['账号：a', '密码：b']);
      final doc = Document.fromJson(jsonDecode(body) as List);
      expect(doc.toPlainText(), contains('账号：a'));
      expect(doc.toPlainText(), contains('密码：b'));
    });
  });

  group('数据备份与恢复', () {
    test('导出 JSON 后清空再恢复，任务/用户数据一致', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      await db.addTask(
        TasksCompanion.insert(
          title: '备份任务',
          date: today,
          quadrant: const Value(2),
        ),
      );
      final userBefore = await db.ensureUser();
      final json = await BackupService.buildBackupJson(db);

      // 模拟数据丢失
      await db.delete(db.tasks).go();
      await db.delete(db.users).go();

      final dir = await Directory.systemTemp.createTemp('shiyu_backup_test');
      final file = File('${dir.path}/backup.json');
      await file.writeAsString(json);
      try {
        final summary = await BackupService.restoreFromFile(db, file);
        expect(summary, contains('任务 1'));
      } finally {
        await file.delete();
        await dir.delete();
      }

      final tasks = await db.tasksForDate(today);
      expect(tasks.where((t) => t.title == '备份任务'), hasLength(1));
      expect((await db.ensureUser()).xpTotal, userBefore.xpTotal);
    });

    test('恢复非时屿备份文件抛 FormatException', () async {
      final dir = await Directory.systemTemp.createTemp('shiyu_backup_bad');
      final file = File('${dir.path}/bad.json');
      await file.writeAsString('{"foo": 1}');
      try {
        await expectLater(
          BackupService.restoreFromFile(db, file),
          throwsA(isA<FormatException>()),
        );
      } finally {
        await file.delete();
        await dir.delete();
      }
    });
  });

  group('段位与经验规则', () {
    test('任务 XP 系数：难度 × 象限', () {
      // 基础 10 XP；难度：简单 0.5 / 普通 1.0 / 困难 2.0；象限 I 额外 ×1.5
      expect(taskXp(difficulty: 1, quadrant: 2), 5);
      expect(taskXp(difficulty: 2, quadrant: 2), 10);
      expect(taskXp(difficulty: 3, quadrant: 2), 20);
      expect(taskXp(difficulty: 1, quadrant: 1), 8); // 10*0.5*1.5=7.5 → 8
      expect(taskXp(difficulty: 2, quadrant: 1), 15);
      expect(taskXp(difficulty: 3, quadrant: 1), 30);
    });

    test('等级经验公式与段位边界', () {
      // 升到 L 级所需累计经验：50 * L * (L+1) → Lv.2 需 300 XP
      expect(xpNeededForLevel(1), 100);
      expect(xpNeededForLevel(2), 300);
      expect(levelFromXp(0), 1);
      expect(levelFromXp(99), 1);
      expect(levelFromXp(100), 1);
      expect(levelFromXp(299), 1);
      expect(levelFromXp(300), 2);
      // 每 5 级晋一段：1=雾芽 6=浅湾 ... 41=时屿
      expect(rankForLevel(1).index, 1);
      expect(rankForLevel(5).index, 1);
      expect(rankForLevel(6).index, 2);
      expect(rankForLevel(11).index, 3);
      expect(rankForLevel(41).index, 9);
      expect(rankForLevel(99).index, 9);
      expect(unlockedRankCount(1), 1);
      expect(unlockedRankCount(6), 2);
      expect(unlockedRankCount(41), 9);
    });

    test('成就全解锁：任务数/番茄/段位达标', () {
      const snapshot = StatsSnapshot(
        totalPomodoros: 100,
        totalMinutes: 1000,
        weekPomodoros: 3,
        weekMinutes: 75,
        last7Days: [0, 0, 0, 0, 0, 0, 10],
        totalTasksDone: 100,
        streakDays: 7,
        rankIndex: 9,
        todayTotal: 3,
        todayDone: 2,
      );
      final achievements = buildAchievements(snapshot);
      expect(
        achievements.where((a) => a.unlocked),
        hasLength(achievements.length),
      );
    });

    test('成就进度与未解锁状态', () {
      const snapshot = StatsSnapshot(
        totalPomodoros: 0,
        totalMinutes: 0,
        weekPomodoros: 0,
        weekMinutes: 0,
        last7Days: [0, 0, 0, 0, 0, 0, 0],
        totalTasksDone: 0,
        streakDays: 0,
        rankIndex: 1,
        todayTotal: 0,
        todayDone: 0,
      );
      final achievements = buildAchievements(snapshot);
      expect(achievements.where((a) => a.unlocked), isEmpty);
      final first = achievements.firstWhere((a) => a.id == 'first');
      expect(first.progress, 0);
    });
  });

  group('格式化与图片路径', () {
    test('formatHm 两位补零', () {
      expect(formatHm(9, 5), '09:05');
      expect(formatHm(23, 59), '23:59');
      expect(formatHm(0, 0), '00:00');
    });

    test('parseHexColor 解析与兜底', () {
      expect(parseHexColor('#9DBB9B'), const Color(0xFF9DBB9B));
      expect(parseHexColor('9DBB9B'), const Color(0xFF9DBB9B));
      expect(parseHexColor('zzz'), const Color(0xFF9DBB9B)); // 非法 → 兜底
    });

    test('extractImagePaths 提取本地图片路径', () {
      const body = '[{"insert":{"image":"file:///a/b.png"}},{"insert":"\\n"}]';
      expect(extractImagePaths(body), ['/a/b.png']);
      expect(extractImagePaths('not json'), isEmpty);
      expect(extractImagePaths(''), isEmpty);
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
