// 时屿 · 应用服务层测试：TaskService / EventService / NoteService / 统计快照
//
// 通过 ProviderContainer + 内存数据库验证应用层编排（DB 写入、状态变化、幂等），
// 通知服务未初始化时静默跳过，不影响数据层断言。
import 'package:drift/drift.dart' hide Column, isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shiyu_app/core/db/database.dart';
import 'package:shiyu_app/core/db/db_providers.dart';
import 'package:shiyu_app/features/calendar/application/event_service.dart';
import 'package:shiyu_app/features/notes/application/note_service.dart';
import 'package:shiyu_app/features/today/application/task_service.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  DateTime today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('TaskService', () {
    test('新建任务后出现在今日列表，完成后结算经验', () async {
      final service = container.read(taskServiceProvider);
      final id = await service.create(
        TasksCompanion.insert(
          title: '服务层任务',
          date: today(),
          quadrant: const Value(2),
          difficulty: const Value(1), // 简单任务 = 5 XP
        ),
        title: '服务层任务',
      );

      final tasks = await db.tasksForDate(today());
      expect(tasks.where((t) => t.id == id), hasLength(1));

      final task = tasks.firstWhere((t) => t.id == id);
      final outcome = await service.toggle(task);
      expect(outcome.xp, 5);
      expect(outcome.repeated, isFalse);

      final refreshed = (await db.tasksForDate(today()))
          .firstWhere((t) => t.id == id);
      expect(refreshed.isDone, isTrue);
    });

    test('取消完成后再完成不重复结算（应用层幂等）', () async {
      final service = container.read(taskServiceProvider);
      final id = await service.create(
        TasksCompanion.insert(
          title: '幂等任务',
          date: today(),
          quadrant: const Value(2),
          difficulty: const Value(2),
        ),
        title: '幂等任务',
      );
      var task = (await db.tasksForDate(today())).firstWhere((t) => t.id == id);

      final first = await service.toggle(task);
      expect(first.xp, greaterThan(0));
      final userAfterFirst = await db.ensureUser();

      // 再次 toggle（已完成 → 取消完成）
      task = (await db.tasksForDate(today())).firstWhere((t) => t.id == id);
      await service.toggle(task);
      task = (await db.tasksForDate(today())).firstWhere((t) => t.id == id);
      expect(task.isDone, isFalse);

      // 再完成：只恢复完成态，不重复结算
      final second = await service.toggle(task);
      expect(second.xp, 0);
      expect(second.repeated, isTrue);
      expect((await db.ensureUser()).xpTotal, userAfterFirst.xpTotal);
    });

    test('批量删除后任务不在列表', () async {
      final service = container.read(taskServiceProvider);
      final ids = <int>[];
      for (final title in ['批量一', '批量二']) {
        ids.add(
          await service.create(
            TasksCompanion.insert(title: title, date: today()),
            title: title,
          ),
        );
      }
      expect((await db.tasksForDate(today())), hasLength(2));

      await service.deleteMany(ids);
      expect(await db.tasksForDate(today()), isEmpty);
    });
  });

  group('EventService', () {
    test('新建事件后可查询到，删除后消失', () async {
      final service = container.read(eventServiceProvider);
      final id = await service.create(
        EventsCompanion.insert(title: '服务层事件', date: today()),
        title: '服务层事件',
        remindAt: DateTime.now().add(const Duration(hours: 1)),
      );

      final events = await (db.select(db.events)).get();
      expect(events.where((e) => e.id == id), hasLength(1));

      final event = events.firstWhere((e) => e.id == id);
      await service.delete(event);
      final after = await (db.select(db.events)).get();
      expect(after.firstWhere((e) => e.id == id).deleted, isTrue);
    });
  });

  group('NoteService', () {
    test('新建/更新/删除笔记', () async {
      final service = container.read(noteServiceProvider);
      final id = await service.create(NotesCompanion.insert(title: '服务层笔记'));

      var notes = await (db.select(db.notes)).get();
      expect(notes.where((n) => n.id == id), hasLength(1));

      await service.update(id, NotesCompanion(title: const Value('服务层笔记-改')));
      notes = await (db.select(db.notes)).get();
      expect(notes.firstWhere((n) => n.id == id).title, '服务层笔记-改');

      final note = notes.firstWhere((n) => n.id == id);
      await service.delete(note);
      final after = await (db.select(db.notes)).get();
      expect(after.firstWhere((n) => n.id == id).deleted, isTrue);
    });

    test('分类管理：新增/重命名/删除后笔记归入未分类', () async {
      final service = container.read(noteServiceProvider);
      final catId = await service.addCategory('学习');
      final noteId = await service.create(
        NotesCompanion.insert(title: '分类笔记', categoryId: Value(catId)),
      );

      await service.renameCategory(catId, '学习资料');
      final cats = await (db.select(db.noteCategories)).get();
      expect(cats.firstWhere((c) => c.id == catId).name, '学习资料');

      await service.deleteCategory(catId);
      final note = (await (db.select(
        db.notes,
      )).get()).firstWhere((n) => n.id == noteId);
      expect(note.categoryId, isNull);
    });
  });

  group('统计快照', () {
    test('番茄与任务汇总正确', () async {
      await db.awardPomodoroXp(focusMinutes: 25);
      await db.awardPomodoroXp(focusMinutes: 25);
      await db.addTask(
        TasksCompanion.insert(
          title: '统计任务',
          date: today(),
          quadrant: const Value(2),
        ),
      );
      final task = (await db.tasksForDate(today())).first;
      await db.completeTaskAndAwardXp(task);

      final stats = await container.read(statsSnapshotProvider.future);
      expect(stats.totalPomodoros, 2);
      expect(stats.totalMinutes, 50);
      expect(stats.todayTotal, 1);
      expect(stats.todayDone, 1);
    });
  });
}
