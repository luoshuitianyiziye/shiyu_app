import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../domain/ranks.dart';

part 'database.g.dart';

// ============ 表定义 ============

/// 用户（本地昵称登录；云同步开启后绑定账号）
@DataClassName('UserRow')
class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nickname => text().withDefault(const Constant('时屿用户'))();
  TextColumn get avatar => text().nullable()();
  IntColumn get xpTotal => integer().withDefault(const Constant(0))();
  IntColumn get level => integer().withDefault(const Constant(1))();
  IntColumn get rank => integer().withDefault(const Constant(1))();
  IntColumn get streakDays => integer().withDefault(const Constant(0))();

  /// 历史最高累计完成任务数（只增不减：成就/统计不随取消完成回退）
  IntColumn get maxTasksDone => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// 任务（四象限 + 时段 + 重复 + 完成/经验）
@DataClassName('TaskRow')
class Tasks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();

  /// 四象限 1=重要紧急 2=重要不紧急 3=紧急不重要 4=不重要不紧急
  IntColumn get quadrant => integer().withDefault(const Constant(1))();

  /// 任务日期（当天零点）
  DateTimeColumn get date => dateTime()();

  /// 时段开始（可为空）
  DateTimeColumn get startTime => dateTime().nullable()();
  DateTimeColumn get endTime => dateTime().nullable()();

  /// 难度 1=简单 2=普通 3=困难
  IntColumn get difficulty => integer().withDefault(const Constant(2))();

  /// 重复规则 none/daily/weekdays/weekly
  TextColumn get repeatRule => text().withDefault(const Constant('none'))();

  /// 重复任务最近一次滚动（复制到当日）的时间（去重用）
  DateTimeColumn get lastRepeatedDate => dateTime().nullable()();
  BoolColumn get isDone => boolean().withDefault(const Constant(false))();
  DateTimeColumn get doneAt => dateTime().nullable()();
  IntColumn get xpAwarded => integer().withDefault(const Constant(0))();
  IntColumn get pomodoroCount => integer().withDefault(const Constant(0))();
  IntColumn get sort => integer().withDefault(const Constant(0))();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// 经验流水
@DataClassName('XpLogRow')
class XpLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get amount => integer()();

  /// 来源：完成任务/番茄专注/连胜奖励
  TextColumn get reason => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// 日历事件（当天提醒 + 倒数日）
@DataClassName('EventRow')
class Events extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  DateTimeColumn get date => dateTime()();
  DateTimeColumn get time => dateTime().nullable()();

  /// 提前提醒分钟数
  IntColumn get remindMinutes => integer().withDefault(const Constant(15))();
  TextColumn get note => text().withDefault(const Constant(''))();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// 笔记分类（用户可自定义）
@DataClassName('NoteCategoryRow')
class NoteCategories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();

  /// 分类颜色（十六进制字符串，如 #9DBB9B）
  TextColumn get color => text().withDefault(const Constant('#9DBB9B'))();
  IntColumn get sort => integer().withDefault(const Constant(0))();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// 笔记（富文本 body + 图片路径列表 + 标签 + 分类）
@DataClassName('NoteRow')
class Notes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();

  /// flutter_quill Delta JSON
  TextColumn get body => text().withDefault(const Constant(''))();

  /// JSON 字符串数组：本地图片路径
  TextColumn get images => text().withDefault(const Constant('[]'))();

  /// JSON 字符串数组：标签
  TextColumn get tags => text().withDefault(const Constant('[]'))();

  /// JSON 对象：本地图片路径 → 图片说明文字
  TextColumn get imageCaptions => text().withDefault(const Constant('{}'))();

  /// 所属分类 id（可空 = 未分类）
  IntColumn get categoryId => integer().nullable()();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
}

/// 设置（单行，id 恒为 1 且为主键，杜绝重复行）
@DataClassName('SettingsRow')
class Settings extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get themeId => text().withDefault(const Constant('mist_green'))();
  TextColumn get whiteNoiseId => text().withDefault(const Constant('rain'))();
  IntColumn get endOfDayHour => integer().withDefault(const Constant(21))();
  IntColumn get endOfDayMinute => integer().withDefault(const Constant(30))();
  IntColumn get focusMinutes => integer().withDefault(const Constant(25))();
  IntColumn get shortBreakMinutes => integer().withDefault(const Constant(5))();
  IntColumn get longBreakMinutes => integer().withDefault(const Constant(15))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 番茄专注记录（统计用：每次完成的番茄 + 实际专注分钟数）
@DataClassName('PomodoroSessionRow')
class PomodoroSessions extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 本次实际专注分钟数（取完成时设置）
  IntColumn get focusMinutes => integer()();
  DateTimeColumn get completedAt =>
      dateTime().withDefault(currentDateAndTime)();
}

// ============ 数据库 ============

@DriftDatabase(
  tables: [
    Users,
    Tasks,
    XpLogs,
    Events,
    Notes,
    NoteCategories,
    Settings,
    PomodoroSessions,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// [executor] 可注入（测试用内存库）；默认使用 drift_flutter 原生 SQLite
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'shiyu'));

  @override
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createIndexes();
    },
    onUpgrade: (m, from, to) async {
      // v1 → v2：新增笔记分类表 + 笔记分类字段
      if (from < 2) {
        await m.createTable(noteCategories);
        await m.addColumn(notes, notes.categoryId);
      }
      // v2 → v3：新增番茄专注记录表（统计用）
      if (from < 3) {
        await m.createTable(pomodoroSessions);
      }
      // v3 → v4：任务新增「重复滚动时间」字段（每日重复任务去重用）
      if (from < 4) {
        await m.addColumn(tasks, tasks.lastRepeatedDate);
      }
      // v4 → v5：笔记新增「图片说明」字段（图片路径 → 说明文字）
      if (from < 5) {
        await m.addColumn(notes, notes.imageCaptions);
      }
      // v5 → v6：settings 表加主键（防止重复行导致 watchSingle 崩溃）
      if (from < 6) {
        // 先清理历史可能存在的重复行（每个 id 只保留 rowid 最小的一行）
        await customStatement(
          'DELETE FROM settings WHERE rowid NOT IN '
          '(SELECT MIN(rowid) FROM settings GROUP BY id);',
        );
        // 重建表以应用主键约束（SQLite 修改主键需重建）
        await customStatement(
          'CREATE TABLE settings_new ('
          'id INTEGER NOT NULL DEFAULT 1 PRIMARY KEY, '
          'theme_id TEXT NOT NULL DEFAULT \'mist_green\', '
          'white_noise_id TEXT NOT NULL DEFAULT \'rain\', '
          'end_of_day_hour INTEGER NOT NULL DEFAULT 21, '
          'end_of_day_minute INTEGER NOT NULL DEFAULT 30, '
          'focus_minutes INTEGER NOT NULL DEFAULT 25, '
          'short_break_minutes INTEGER NOT NULL DEFAULT 5, '
          'long_break_minutes INTEGER NOT NULL DEFAULT 15);',
        );
        await customStatement(
          'INSERT OR IGNORE INTO settings_new (id, theme_id, white_noise_id, '
          'end_of_day_hour, end_of_day_minute, focus_minutes, '
          'short_break_minutes, long_break_minutes) '
          'SELECT id, theme_id, white_noise_id, end_of_day_hour, '
          'end_of_day_minute, focus_minutes, short_break_minutes, '
          'long_break_minutes FROM settings;',
        );
        await customStatement('DROP TABLE settings;');
        await customStatement('ALTER TABLE settings_new RENAME TO settings;');
      }
      // v6 → v7：users 新增「历史最高完成任务数」（成就不随取消完成回退）
      if (from < 7) {
        await m.addColumn(users, users.maxTasksDone);
      }
      // v7 → v8：常用查询索引（日期过滤 / 笔记排序 / 番茄统计 / 重复滚动）
      if (from < 8) {
        await _createIndexes();
      }
      // v8 → v9：清理旧版「每日复制副本」逻辑产生的重复任务副本。
      // 这些副本（repeatRule='none'、与仍在重复的任务同标题）只是历史
      // bug 产物，没有展示入口，留在库里只会让今日页出现重复任务。
      if (from < 9) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final repeatTasks =
            await (select(tasks)..where(
                  (t) =>
                      t.repeatRule.isNotValue('none') & t.deleted.equals(false),
                ))
                .get();
        final titles = repeatTasks.map((t) => t.title).toSet();
        if (titles.isNotEmpty) {
          final copies =
              await (select(tasks)..where(
                    (t) =>
                        t.repeatRule.equals('none') &
                        t.deleted.equals(false) &
                        t.title.isIn(titles),
                  ))
                  .get();
          final staleIds = copies
              .where((c) => !c.date.isAfter(today))
              .map((c) => c.id)
              .toList();
          if (staleIds.isNotEmpty) {
            await (delete(tasks)..where((t) => t.id.isIn(staleIds))).go();
          }
        }
      }
    },
  );

  /// 常用查询索引（v8 起）。数据量小时收益不明显，但可避免长期使用后
  /// 今日列表、笔记列表、收尾提醒计数、重复任务滚动退化为全表扫描。
  static const List<String> _indexStatements = [
    'CREATE INDEX IF NOT EXISTS idx_tasks_date ON tasks (date);',
    'CREATE INDEX IF NOT EXISTS idx_tasks_repeat ON tasks (repeat_rule, date);',
    'CREATE INDEX IF NOT EXISTS idx_events_date ON events (date);',
    'CREATE INDEX IF NOT EXISTS idx_notes_updated ON notes (deleted, updated_at);',
    'CREATE INDEX IF NOT EXISTS idx_pomodoro_completed ON pomodoro_sessions (completed_at);',
  ];

  Future<void> _createIndexes() async {
    for (final sql in _indexStatements) {
      await customStatement(sql);
    }
  }

  // ---------- 用户 ----------

  /// 保证至少存在一个用户，返回它。
  /// 事务内 select-then-insert，避免并发（如启动与流首次加载同时调用）重复创建用户行。
  Future<UserRow> ensureUser() async {
    return transaction(() async {
      final rows = await (select(users)..limit(1)).get();
      if (rows.isNotEmpty) return rows.first;
      return into(users).insertReturning(UsersCompanion());
    });
  }

  Stream<UserRow> watchUser() {
    final q = select(users)..limit(1);
    return q.watchSingle();
  }

  /// 增加经验并同步等级/段位（在事务内调用）
  Future<void> addXpToUser(int amount) async {
    final user = await ensureUser();
    final newXp = user.xpTotal + amount;
    final newLevel = levelFromXp(newXp);
    await (update(users)..where((u) => u.id.equals(user.id))).write(
      UsersCompanion(
        xpTotal: Value(newXp),
        level: Value(newLevel),
        rank: Value(rankForLevel(newLevel).index),
      ),
    );
  }

  /// 修改用户昵称（个人资料页）
  Future<void> updateUserNickname(String nickname) async {
    final user = await ensureUser();
    await (update(users)..where((u) => u.id.equals(user.id))).write(
      UsersCompanion(nickname: Value(nickname)),
    );
  }

  // ---------- 任务 ----------

  Stream<List<TaskRow>> watchTasksForDate(DateTime date) {
    final q = _tasksForDateQuery(date);
    return q.watch();
  }

  Future<List<TaskRow>> tasksForDate(DateTime date) async =>
      _tasksForDateQuery(date).get();

  SimpleSelectStatement<$TasksTable, TaskRow> _tasksForDateQuery(
    DateTime date,
  ) {
    return select(tasks)
      ..where((t) => t.date.equals(date) & t.deleted.equals(false))
      ..orderBy([
        (t) => OrderingTerm(expression: t.quadrant),
        (t) => OrderingTerm(expression: t.startTime, mode: OrderingMode.asc),
      ]);
  }

  Future<int> addTask(TasksCompanion entry) => into(tasks).insert(entry);

  /// 编辑任务（标题/四象限/难度/时段/重复）
  Future<void> updateTask(int id, TasksCompanion entry) async {
    await (update(tasks)..where((t) => t.id.equals(id))).write(entry);
  }

  /// 完成任务并结算经验（事务），返回所得经验 + 段位变化。
  /// 事务内重读任务状态：已完成/已删除的任务不重复结算（防连点刷经验）。
  /// 同时结算「连续打卡」：昨天完成过 +1，今天已完成过不变，否则重置为 1。
  ///
  /// 防刷规则：
  /// - 任务处于已完成/已删除 → 不结算（返回 xp=0）
  /// - 任务曾被结算过（xpAwarded > 0）且被取消完成 → 属于「重复完成」，
  ///   只恢复完成状态，**不再结算 XP、不写流水、不叠加连胜**
  ///   （完成→取消→再完成无法刷经验/连胜）
  Future<({int xp, int oldRank, int newRank})> completeTaskAndAwardXp(
    TaskRow task,
  ) async {
    var skipped = false;
    var repeated = false;
    late int xp;
    late int oldRank;
    late int newRank;
    await transaction(() async {
      // H2：重读最新状态，防止 UI 流刷新前连点重复结算
      final current = await (select(
        tasks,
      )..where((t) => t.id.equals(task.id))).getSingleOrNull();
      final user = await ensureUser();
      if (current == null || current.isDone || current.deleted) {
        skipped = true;
        oldRank = user.rank;
        newRank = user.rank;
        return;
      }
      // 重复完成：xpAwarded > 0 说明此前结算过又被取消。仅恢复完成态，
      // 不重复结算 XP（XP 与连胜都不再叠加），但仍推进历史最高完成数。
      if (current.xpAwarded > 0) {
        repeated = true;
        await (update(tasks)..where((t) => t.id.equals(task.id))).write(
          TasksCompanion(
            isDone: const Value(true),
            doneAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );
        final completedCount = await completedTaskCount();
        final newMaxTasksDone = completedCount > user.maxTasksDone
            ? completedCount
            : user.maxTasksDone;
        await (update(users)..where((u) => u.id.equals(user.id))).write(
          UsersCompanion(maxTasksDone: Value(newMaxTasksDone)),
        );
        oldRank = user.rank;
        newRank = user.rank;
        return;
      }
      // 以事务内重读的最新任务配置结算（难度/象限/标题可能已被编辑，
      // 与 UI 快照不一致时以最新数据为准，避免奖励与当前配置脱节）
      xp = taskXp(difficulty: current.difficulty, quadrant: current.quadrant);
      await (update(tasks)..where((t) => t.id.equals(task.id))).write(
        TasksCompanion(
          isDone: const Value(true),
          doneAt: Value(DateTime.now()),
          xpAwarded: Value(xp),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await into(xpLogs).insert(
        XpLogsCompanion.insert(amount: xp, reason: '完成任务「${current.title}」'),
      );

      // H1：连续打卡结算。昨天完成过 +1；今天已完成过不变；否则重置为 1。
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final int newStreak;
      final lastDone = await _lastDoneDateExcluding(task.id);
      if (lastDone == null) {
        newStreak = 1;
      } else {
        final diff = today.difference(lastDone).inDays;
        if (diff == 0) {
          newStreak = user.streakDays;
        } else if (diff == 1) {
          newStreak = user.streakDays + 1;
        } else {
          newStreak = 1;
        }
      }

      oldRank = user.rank;
      final newXp = user.xpTotal + xp;
      final newLevel = levelFromXp(newXp);
      newRank = rankForLevel(newLevel).index;
      // 历史最高完成任务数：只增不减（成就/统计不随取消完成回退）
      final completedCount = await completedTaskCount();
      final newMaxTasksDone = completedCount > user.maxTasksDone
          ? completedCount
          : user.maxTasksDone;
      await (update(users)..where((u) => u.id.equals(user.id))).write(
        UsersCompanion(
          xpTotal: Value(newXp),
          level: Value(newLevel),
          rank: Value(newRank),
          streakDays: Value(newStreak),
          maxTasksDone: Value(newMaxTasksDone),
        ),
      );
    });
    if (skipped || repeated) return (xp: 0, oldRank: oldRank, newRank: newRank);
    return (xp: xp, oldRank: oldRank, newRank: newRank);
  }

  /// 除 [taskId] 外最近一次完成任务的日子（零点对齐），无则 null
  Future<DateTime?> _lastDoneDateExcluding(int taskId) async {
    final q = selectOnly(tasks)
      ..addColumns([tasks.doneAt.max()])
      ..where(
        tasks.isDone.equals(true) &
            tasks.deleted.equals(false) &
            tasks.id.isNotValue(taskId),
      );
    final row = await q.getSingle();
    final dt = row.read(tasks.doneAt.max());
    if (dt == null) return null;
    return DateTime(dt.year, dt.month, dt.day);
  }

  /// 取消完成（不回收经验）。按 id 恢复，用于「已完成区」取消完成/批量恢复。
  Future<void> uncompleteTaskById(int id) async {
    await (update(tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        isDone: const Value(false),
        doneAt: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// 软删除任务
  Future<void> softDeleteTask(int id) async {
    await (update(tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        deleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// 彻底删除任务（已完成区多选彻底删除用，不可恢复）
  Future<void> hardDeleteTasks(List<int> ids) async {
    if (ids.isEmpty) return;
    await (delete(tasks)..where((t) => t.id.isIn(ids))).go();
  }

  /// 每日滚动（单条模型）：重复任务**不复制**，只把「活」记录推进/复位到今天。
  ///
  /// 规则（跨天首次调用时生效，整个「查询 + 推进 + 标记」在一个事务内完成）：
  /// - 昨天未完成 → 日期推进到今天，保持未完成（仍留在正常栏）；
  /// - 昨天已完成 → 复位为未完成（从已完成栏回到正常栏），[xpAwarded] 清零
  ///   （新的一天重新结算；当天内「完成→取消→再完成」仍由 xpAwarded 防刷）；
  /// - 工作日/每周规则：非匹配日不推进（任务停留在最近一次匹配日）。
  ///
  /// 幂等：推进后 date = today，且用 [Tasks.lastRepeatedDate] 做当日去重。
  /// 返回今天被推进的任务 id（调用方据此重建开始提醒）。
  Future<List<int>> rollRepeatingTasks() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final rolled = <int>[];

    await transaction(() async {
      final active =
          await (select(tasks)..where(
                (t) =>
                    t.deleted.equals(false) &
                    t.repeatRule.isNotValue('none') &
                    t.date.isSmallerThanValue(today),
              ))
              .get();

      for (final t in active) {
        // 今天已推进过 → 跳过（防御并发/重复调用）
        if (t.lastRepeatedDate != null) {
          final last = t.lastRepeatedDate!;
          if (last.year == today.year &&
              last.month == today.month &&
              last.day == today.day) {
            continue;
          }
        }
        // 工作日规则：周六日不推进
        if (t.repeatRule == 'weekdays' && today.weekday >= 6) continue;
        // 每周规则：只在原星期几推进
        if (t.repeatRule == 'weekly' && today.weekday != t.date.weekday) {
          continue;
        }

        // 已完成 → 次日复位为未完成（回到正常栏）；未完成 → 保持未完成。
        // xpAwarded 清零：新的一天重新结算，当天内防刷不受影响。
        final startTime = t.startTime == null
            ? null
            : DateTime(
                today.year,
                today.month,
                today.day,
                t.startTime!.hour,
                t.startTime!.minute,
              );
        final endTime = t.endTime == null
            ? null
            : DateTime(
                today.year,
                today.month,
                today.day,
                t.endTime!.hour,
                t.endTime!.minute,
              );
        await (update(tasks)..where((x) => x.id.equals(t.id))).write(
          TasksCompanion(
            date: Value(today),
            startTime: Value(startTime),
            endTime: Value(endTime),
            isDone: const Value(false),
            doneAt: const Value(null),
            xpAwarded: const Value(0),
            lastRepeatedDate: Value(now),
            updatedAt: Value(now),
          ),
        );
        rolled.add(t.id);
      }
    });
    return rolled;
  }

  /// 完成一个番茄专注：+XP 并记录流水与专注记录（[focusMinutes] 为本次实际专注分钟）
  Future<void> awardPomodoroXp({
    String reason = '完成一个番茄专注',
    int? focusMinutes,
  }) async {
    await transaction(() async {
      await into(xpLogs)
          .insert(XpLogsCompanion.insert(amount: pomodoroXp, reason: reason));
      await addXpToUser(pomodoroXp);
      if (focusMinutes != null) {
        await into(
          pomodoroSessions,
        ).insert(PomodoroSessionsCompanion.insert(focusMinutes: focusMinutes));
      }
    });
  }

  // ---------- 设置 ----------

  Stream<SettingsRow> watchSettings() {
    final q = select(settings)..limit(1);
    return q.watchSingle();
  }

  Future<SettingsRow> ensureSettings() async {
    final rows = await (select(settings)..limit(1)).get();
    if (rows.isNotEmpty) return rows.first;
    return into(settings).insertReturning(SettingsCompanion());
  }

  /// 更新设置（只更新传入的字段）
  Future<void> updateSettings({
    String? themeId,
    String? whiteNoiseId,
    int? endOfDayHour,
    int? endOfDayMinute,
    int? focusMinutes,
    int? shortBreakMinutes,
    int? longBreakMinutes,
  }) async {
    await (update(settings)..where((s) => s.id.equals(1))).write(
      SettingsCompanion(
        themeId: themeId == null ? const Value.absent() : Value(themeId),
        whiteNoiseId: whiteNoiseId == null
            ? const Value.absent()
            : Value(whiteNoiseId),
        endOfDayHour: endOfDayHour == null
            ? const Value.absent()
            : Value(endOfDayHour),
        endOfDayMinute: endOfDayMinute == null
            ? const Value.absent()
            : Value(endOfDayMinute),
        focusMinutes: focusMinutes == null
            ? const Value.absent()
            : Value(focusMinutes),
        shortBreakMinutes: shortBreakMinutes == null
            ? const Value.absent()
            : Value(shortBreakMinutes),
        longBreakMinutes: longBreakMinutes == null
            ? const Value.absent()
            : Value(longBreakMinutes),
      ),
    );
  }

  /// 指定日期未完成任务数（收尾提醒用）
  Future<int> unfinishedCountForDate(DateTime date) async {
    final rows = await _tasksForDateQuery(date).get();
    return rows.where((t) => !t.isDone).length;
  }

  // ---------- 统计 ----------

  /// 某时间区间内的番茄专注记录（按完成时间升序）
  Future<List<PomodoroSessionRow>> pomodoroSessionsBetween(
    DateTime start,
    DateTime end,
  ) async {
    final q = select(pomodoroSessions)
      ..where((s) => s.completedAt.isBetweenValues(start, end))
      ..orderBy([(s) => OrderingTerm(expression: s.completedAt)]);
    return q.get();
  }

  /// 累计完成的番茄数
  Future<int> pomodoroSessionCount() async {
    final count = await (selectOnly(pomodoroSessions)..addColumns([countAll()]))
        .map((row) => row.read(countAll())!)
        .getSingle();
    return count;
  }

  /// 累计完成的任务数（未删除且已勾选）
  Future<int> completedTaskCount() async {
    final count =
        await (selectOnly(tasks)
              ..addColumns([countAll()])
              ..where(tasks.isDone.equals(true) & tasks.deleted.equals(false)))
            .map((row) => row.read(countAll())!)
            .getSingle();
    return count;
  }

  /// 某日任务总数与已完成数
  Future<({int total, int done})> taskStatsForDate(DateTime date) async {
    final rows = await _tasksForDateQuery(date).get();
    return (total: rows.length, done: rows.where((t) => t.isDone).length);
  }

  // ---------- 笔记 ----------

  Stream<List<NoteRow>> watchNotes() {
    final q = select(notes)
      ..where((n) => n.deleted.equals(false))
      ..orderBy([
        (n) => OrderingTerm(expression: n.pinned, mode: OrderingMode.desc),
        (n) => OrderingTerm(expression: n.updatedAt, mode: OrderingMode.desc),
      ]);
    return q.watch();
  }

  Future<int> addNote(NotesCompanion entry) => into(notes).insert(entry);

  Future<void> updateNote(int id, NotesCompanion entry) async {
    await (update(notes)..where((n) => n.id.equals(id))).write(entry);
  }

  Future<void> softDeleteNote(int id) async {
    await (update(notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        deleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // ---------- 笔记分类 ----------

  Stream<List<NoteCategoryRow>> watchNoteCategories() {
    final q = select(noteCategories)
      ..where((c) => c.deleted.equals(false))
      ..orderBy([(c) => OrderingTerm(expression: c.sort)]);
    return q.watch();
  }

  Future<int> addNoteCategory(String name, {String color = '#9DBB9B'}) {
    return into(noteCategories).insert(
      NoteCategoriesCompanion.insert(
        name: name,
        color: Value(color),
        sort: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
      ),
    );
  }

  Future<void> updateNoteCategory(int id, {String? name, String? color}) async {
    await (update(noteCategories)..where((c) => c.id.equals(id))).write(
      NoteCategoriesCompanion(
        name: name == null ? const Value.absent() : Value(name),
        color: color == null ? const Value.absent() : Value(color),
      ),
    );
  }

  /// 删除分类：软删分类，并将该分类下的笔记置为未分类
  Future<void> deleteNoteCategory(int id) async {
    await transaction(() async {
      await (update(noteCategories)..where((c) => c.id.equals(id))).write(
        NoteCategoriesCompanion(
          deleted: const Value(true),
          sort: const Value(999999),
        ),
      );
      await (update(notes)..where((n) => n.categoryId.equals(id))).write(
        NotesCompanion(
          categoryId: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  // ---------- 事件 ----------

  Stream<List<EventRow>> watchEvents() {
    final q = select(events)
      ..where((e) => e.deleted.equals(false))
      ..orderBy([(e) => OrderingTerm(expression: e.date)]);
    return q.watch();
  }

  Future<int> addEvent(EventsCompanion entry) => into(events).insert(entry);

  /// 编辑事件（标题/日期/时间/提醒/备注）
  Future<void> updateEvent(int id, EventsCompanion entry) async {
    await (update(events)..where((e) => e.id.equals(id))).write(entry);
  }

  Future<void> softDeleteEvent(int id) async {
    await (update(events)..where((e) => e.id.equals(id))).write(
      EventsCompanion(
        deleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
