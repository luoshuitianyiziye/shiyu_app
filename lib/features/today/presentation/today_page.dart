import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../../app/theme/morandi_theme.dart';
import '../../../app/widgets/empty_state.dart';
import '../../../app/widgets/slidable_actions.dart';
import '../../../core/db/database.dart';
import '../../../core/db/db_providers.dart';
import '../../../core/feedback/feedback_debouncer.dart';
import '../../../core/notifications/reminder_coordinator.dart';
import '../../../core/utils/confirm_dialog.dart';
import '../../../core/utils/format.dart';
import '../../growth/data/ranks.dart';
import '../../growth/presentation/rank_up_dialog.dart';
import '../data/quadrants.dart';
import 'add_task_sheet.dart';

const _weekdayNames = kWeekdayNames;

const _difficultyNames = {1: '简单', 2: '普通', 3: '困难'};

/// 重复规则中文名（任务行标记用）
const _repeatLabels = {'daily': '每天', 'weekdays': '工作日', 'weekly': '每周'};

/// 今日任务页：四象限分组 + 完成任务得经验
class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final userAsync = ref.watch(userStreamProvider);
    final tasksAsync = ref.watch(todayTasksProvider);
    final today = ref.watch(todayDateProvider); // 跨午夜自动刷新

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${today.month}月${today.day}日 · 周${_weekdayNames[today.weekday - 1]}',
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null, // 多页 FAB 共存（indexedStack），禁用 hero 动画避免标签冲突
        onPressed: () => showAddTaskSheet(context),
        backgroundColor: palette.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          _HeaderCard(userAsync: userAsync),
          const _DailyReviewCard(),
          Expanded(
            child: tasksAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败：$e')),
              data: (tasks) => _TaskQuadrantList(tasks: tasks),
            ),
          ),
        ],
      ),
    );
  }
}

/// 顶部：段位徽章 + 等级 + 经验进度
class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.userAsync});

  final AsyncValue<UserRow> userAsync;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Card(
        child: userAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (_, _) => const SizedBox.shrink(),
          data: (user) {
            final level = levelFromXp(user.xpTotal);
            final rank = rankForLevel(level);
            final nextXp = xpNeededForLevel(level + 1);
            // Lv.1 的经验区间下限是 0（而非 xpNeededForLevel(1)=100），
            // 否则新用户前 100 XP 进度条恒为 0
            final curXp = level == 1 ? 0 : xpNeededForLevel(level);
            final progress = ((user.xpTotal - curXp) / (nextXp - curXp))
                .clamp(0.0, 1.0)
                .toDouble();

            return Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset(
                      rank.assetPath,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      cacheWidth: 120,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Lv.$level · ${rank.name}',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: palette.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${user.xpTotal} XP',
                              style: TextStyle(
                                fontSize: 12,
                                color: palette.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: ShaderMask(
                            // 渐变进度条：主色 → 暖金，呼应经验/奖励
                            shaderCallback: (rect) => LinearGradient(
                              colors: [palette.primary, palette.gold],
                            ).createShader(rect),
                            blendMode: BlendMode.srcATop,
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 8,
                              backgroundColor: palette.accent,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '距 Lv.${level + 1} 还差 ${nextXp - user.xpTotal} XP · 连续 ${user.streakDays} 天',
                          style: TextStyle(
                            fontSize: 11,
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 今日复盘卡片：完成率 + 本周番茄数 + 连续打卡（数据来自统计快照）
class _DailyReviewCard extends ConsumerWidget {
  const _DailyReviewCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final stats = ref.watch(statsSnapshotProvider).value;
    if (stats == null) return const SizedBox.shrink();

    final rate = stats.todayRate;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.insights_outlined,
                size: 18,
                color: palette.primaryDark,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stats.todayTotal == 0
                          ? '今日还没有任务，去添加一个吧'
                          : '今日完成 ${stats.todayDone}/${stats.todayTotal} 项'
                                '（${(rate * 100).round()}%）',
                      style: TextStyle(
                        fontSize: 13,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '本周番茄 ${stats.weekPomodoros} · 连续打卡 ${stats.streakDays} 天',
                      style: TextStyle(
                        fontSize: 11,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 按四象限分组展示未完成任务；已完成任务单独放「已完成」区（支持多选恢复/彻底删除）
class _TaskQuadrantList extends ConsumerStatefulWidget {
  const _TaskQuadrantList({required this.tasks});

  final List<TaskRow> tasks;

  @override
  ConsumerState<_TaskQuadrantList> createState() => _TaskQuadrantListState();
}

class _TaskQuadrantListState extends ConsumerState<_TaskQuadrantList> {
  bool _selectMode = false;
  final Set<int> _selected = {};

  /// 进入多选模式（[id] 非空时同时选中该项）；长按任意任务或点「多选」进入。
  void _enterSelectMode(int? id) {
    setState(() {
      _selectMode = true;
      if (id != null) _selected.add(id);
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
  }

  void _toggleSelected(int id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  /// 全选 / 取消全选（未完成 + 已完成全部任务）
  void _toggleAll() {
    final all = widget.tasks.map((t) => t.id).toList();
    setState(() {
      if (_selected.length == all.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(all);
      }
    });
  }

  /// 批量恢复：仅恢复选中中的已完成任务（未完成任务不受影响）。
  /// 循环外只重建一次收尾提醒，避免 N 个任务触发 N 次全量调度。
  Future<void> _restoreSelected() async {
    final db = ref.read(databaseProvider);
    final targets = widget.tasks
        .where((t) => t.isDone && _selected.contains(t.id))
        .toList();
    if (targets.isEmpty) return;
    for (final task in targets) {
      await _restoreTask(task, syncEndOfDay: false);
    }
    ref.invalidate(statsSnapshotProvider);
    await rescheduleEndOfDay(db);
    if (mounted) _exitSelectMode();
  }

  /// 恢复任务为未完成，并按开始时间重建提醒（完成/删除时取消的提醒恢复对称）。
  /// [syncEndOfDay] 默认 true（单任务恢复时立即同步收尾提醒）；
  /// 批量恢复传 false，由外层统一调度一次。
  Future<void> _restoreTask(TaskRow task, {bool syncEndOfDay = true}) async {
    final db = ref.read(databaseProvider);
    await db.uncompleteTaskById(task.id);
    await ReminderCoordinator.syncTaskReminder(
      taskId: task.id,
      title: task.title,
      startTime: task.startTime,
    );
    ref.invalidate(statsSnapshotProvider);
    if (syncEndOfDay) {
      await rescheduleEndOfDay(db);
    }
  }

  /// 多选删除：确认后彻底删除（含未完成 + 已完成），并取消对应提醒。
  Future<void> _deleteSelected() async {
    final count = _selected.length;
    if (count == 0) return;
    final ok = await showConfirmDialog(
      context,
      title: '删除任务',
      content: '将永久删除 $count 个任务（经验保留，无法恢复）',
      confirmText: '删除',
      danger: true,
    );
    if (ok != true || !mounted) return;
    final db = ref.read(databaseProvider);
    final ids = _selected.toList();
    await db.hardDeleteTasks(ids);
    for (final id in ids) {
      await ReminderCoordinator.cancelTaskReminder(id);
    }
    ref.invalidate(statsSnapshotProvider);
    await rescheduleEndOfDay(db);
    if (mounted) _exitSelectMode();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final tasks = widget.tasks;
    final unfinished = tasks.where((t) => !t.isDone).toList();
    final done = tasks.where((t) => t.isDone).toList();
    // build 期只读：列表为空时强制退出多选模式
    if (tasks.isEmpty && _selectMode) {
      _selectMode = false;
      _selected.clear();
    }

    final grouped = <int, List<TaskRow>>{};
    for (final t in unfinished) {
      grouped.putIfAbsent(t.quadrant, () => []).add(t);
    }

    if (tasks.isEmpty) {
      return EmptyState(
        icon: Icons.wb_sunny_outlined,
        title: '今天还没有任务',
        subtitle: '点右下角 + 添加第一个任务，开始你的一天',
        actionLabel: '添加第一个任务',
        onAction: () => showAddTaskSheet(context),
      );
    }

    // 选中项中已完成的个数（决定「恢复」按钮是否可用）
    final selectedDone = tasks
        .where((t) => t.isDone && _selected.contains(t.id))
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      children: [
        // ===== 多选工具条（长按任意任务进入）=====
        if (_selectMode) ...[
          _SelectionBar(
            selectedCount: _selected.length,
            totalCount: tasks.length,
            allSelected: tasks.isNotEmpty && _selected.length == tasks.length,
            onToggleAll: _toggleAll,
            onRestore: selectedDone > 0 ? _restoreSelected : null,
            onDelete: _selected.isEmpty ? null : _deleteSelected,
            onCancel: _exitSelectMode,
          ),
          const SizedBox(height: 8),
        ],
        for (final q in kQuadrants)
          if (grouped[q.id]?.isNotEmpty ?? false) ...[
            _QuadrantHeader(q: q),
            const SizedBox(height: 8),
            ...grouped[q.id]!.map(
              (t) => _TaskTile(
                task: t,
                selectMode: _selectMode,
                selected: _selected.contains(t.id),
                onLongPress: () => _enterSelectMode(t.id),
                onCheckTap: () => _toggleSelected(t.id),
              ),
            ),
            const SizedBox(height: 12),
          ],
        // ===== 已完成区（与未完成互不干扰）=====
        if (done.isNotEmpty) ...[
          Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 18,
                color: palette.primaryDark,
              ),
              const SizedBox(width: 6),
              Text(
                '已完成 · ${done.length}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
              const Spacer(),
              if (!_selectMode)
                TextButton(
                  onPressed: () => _enterSelectMode(null),
                  child: const Text('多选'),
                ),
            ],
          ),
          ...done.map(
            (t) => _DoneTaskTile(
              key: ValueKey('done-${t.id}'),
              task: t,
              selectMode: _selectMode,
              selected: _selected.contains(t.id),
              onTap: () {
                if (!_selectMode) {
                  // 非多选模式：点击恢复为未完成（并重建开始提醒）
                  _restoreTask(t);
                  return;
                }
                _toggleSelected(t.id);
              },
              onLongPress: () => _enterSelectMode(t.id),
            ),
          ),
        ],
      ],
    );
  }
}

/// 多选工具条：全选 / 已选数 / 取消 / 恢复（仅已完成项）/ 彻底删除
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.selectedCount,
    required this.totalCount,
    required this.allSelected,
    required this.onToggleAll,
    required this.onRestore,
    required this.onDelete,
    required this.onCancel,
  });

  final int selectedCount;
  final int totalCount;
  final bool allSelected;
  final VoidCallback onToggleAll;

  /// 为 null 时禁用（选中项中没有已完成任务）
  final VoidCallback? onRestore;

  /// 为 null 时禁用（未选中任何任务）
  final VoidCallback? onDelete;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: palette.accent.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Column(
          children: [
            Row(
              children: [
                TextButton.icon(
                  onPressed: onToggleAll,
                  icon: Icon(
                    allSelected
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 18,
                  ),
                  label: Text(allSelected ? '取消全选' : '全选'),
                ),
                const Spacer(),
                Text(
                  '已选 $selectedCount/$totalCount',
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
                IconButton(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: '退出多选',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: onRestore,
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text('恢复'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_forever_outlined, size: 18),
                    label: const Text('彻底删除'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.danger,
                      side: BorderSide(
                        color: palette.danger.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 已完成任务行：普通模式点击恢复；多选模式点击勾选；长按进入多选
class _DoneTaskTile extends StatelessWidget {
  const _DoneTaskTile({
    super.key,
    required this.task,
    required this.selectMode,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  final TaskRow task;
  final bool selectMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final q = quadrantById(task.quadrant);
    final timeStr = task.startTime != null
        ? formatHm(task.startTime!.hour, task.startTime!.minute)
        : null;

    return TweenAnimationBuilder<double>(
      // 新出现的已完成条目：淡入 + 轻微上滑（列表重建不会重播）
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 10),
          child: child,
        ),
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        color: selected ? palette.accent.withValues(alpha: 0.5) : null,
        child: ListTile(
          onTap: onTap,
          onLongPress: onLongPress,
          leading: selectMode
              ? Icon(
                  selected ? Icons.check_box : Icons.check_box_outline_blank,
                  color: selected ? palette.primaryDark : palette.textSecondary,
                  size: 24,
                )
              : Icon(Icons.check_circle, color: palette.primary, size: 26),
          title: Text(
            task.title,
            style: TextStyle(
              color: palette.textSecondary,
              decoration: TextDecoration.lineThrough,
              fontSize: 15,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (timeStr != null) ...[
                  Icon(
                    Icons.access_time,
                    size: 13,
                    color: palette.textSecondary,
                  ),
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 12,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
                Text(
                  _difficultyNames[task.difficulty] ?? '普通',
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
                Text(
                  q.name,
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
                if (task.xpAwarded > 0)
                  Text(
                    '+${task.xpAwarded} XP',
                    style: TextStyle(fontSize: 12, color: palette.primaryDark),
                  ),
              ],
            ),
          ),
          trailing: selectMode
              ? null
              : Icon(Icons.restore, size: 18, color: palette.textSecondary),
        ),
      ),
    );
  }
}

/// 四象限主题色（任务卡色条 / 分组标题共用）
Color _quadrantColor(MorandiPalette palette, int quadrant) =>
    switch (quadrant) {
      1 => palette.danger,
      2 => palette.primary,
      3 => palette.primaryDark,
      _ => palette.textSecondary,
    };

class _QuadrantHeader extends StatelessWidget {
  const _QuadrantHeader({required this.q});

  final QuadrantInfo q;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final color = _quadrantColor(palette, q.id);

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            '${q.name} · ${q.motto}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile({
    required this.task,
    this.selectMode = false,
    this.selected = false,
    this.onLongPress,
    this.onCheckTap,
  });

  final TaskRow task;

  /// 多选模式：点击 = 勾选/取消勾选，长按 = 进入多选并选中
  final bool selectMode;
  final bool selected;
  final VoidCallback? onLongPress;
  final VoidCallback? onCheckTap;

  /// 连点防护：刚完成的任务在短时间内忽略「恢复」点击，
  /// 避免第三次连点命中已刷新的 tile 把任务撤销回未完成。
  /// 上限防无限增长：超过 200 条整体清空（旧条目只是失去 1s 防护，无副作用）。
  static final Map<int, DateTime> _recentlyCompleted = {};
  static const int _recentlyCompletedCap = 200;

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    try {
      if (!task.isDone) {
        _recentlyCompleted[task.id] = DateTime.now();
        if (_recentlyCompleted.length > _recentlyCompletedCap) {
          _recentlyCompleted.clear();
        }
        final result = await db.completeTaskAndAwardXp(task);
        await ReminderCoordinator.cancelTaskReminder(task.id);
        ref.invalidate(statsSnapshotProvider);
        // 未完成数变化 → 更新收尾提醒
        await rescheduleEndOfDay(db);
        if (!context.mounted) return;
        if (result.xp <= 0) return; // 已结算过（连点/已被删除）→ 静默
        if (result.newRank > result.oldRank) {
          await showRankUpDialog(context, kRanks[result.newRank - 1]);
        } else {
          // 合并提示：短时间内多次完成只弹一条汇总
          FeedbackDebouncer.xp(context, result.xp, action: '任务完成');
        }
      } else {
        // 连点防护：1 秒内刚完成的任务，忽略本次「恢复」点击，
        // 避免第三次连点命中已刷新的 tile 把任务撤销回未完成
        final doneAt = _recentlyCompleted[task.id];
        if (doneAt != null &&
            DateTime.now().difference(doneAt) < const Duration(seconds: 1)) {
          return;
        }
        // 取消完成：恢复未完成状态，并按开始时间重建提醒
        // （完成时已取消的提醒在此恢复，保证取消/重建对称）
        await db.uncompleteTaskById(task.id);
        await ReminderCoordinator.syncTaskReminder(
          taskId: task.id,
          title: task.title,
          startTime: task.startTime,
        );
        ref.invalidate(statsSnapshotProvider);
        await rescheduleEndOfDay(db);
      }
    } catch (e, st) {
      // DB/通知失败（右滑 dismiss 场景尤为关键）：不让卡片永久塌陷，
      // 刷新列表恢复可交互状态并记录日志
      debugPrint('任务切换失败：$e\n$st');
      if (context.mounted) {
        FeedbackDebouncer.toast(context, '操作失败，请重试', group: 'global');
      }
      ref.invalidate(todayTasksProvider);
    }
  }

  /// 左滑「删除」：确认后删除并取消提醒、刷新收尾提醒
  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除任务',
      content: '「${task.title}」将从列表移除',
      confirmText: '删除',
      danger: true,
    );
    if (ok != true) return;
    final db = ref.read(databaseProvider);
    await db.softDeleteTask(task.id);
    await ReminderCoordinator.cancelTaskReminder(task.id);
    ref.invalidate(statsSnapshotProvider);
    await rescheduleEndOfDay(db);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final q = quadrantById(task.quadrant);
    final timeStr = task.startTime != null
        ? formatHm(task.startTime!.hour, task.startTime!.minute)
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Slidable(
        key: ValueKey('task-${task.id}'),
        // 多选模式下禁用左右滑操作，避免与勾选点击冲突
        startActionPane: selectMode
            ? null
            : buildCompletePane(
                context,
                onComplete: () => _toggle(context, ref),
              ),
        endActionPane: selectMode
            ? null
            : buildEditDeletePane(
                context,
                onEdit: () => showEditTaskSheet(context, task),
                onDelete: () => _delete(context, ref),
              ),
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 象限色条：一眼区分四象限
                Container(
                  width: 4,
                  color: _quadrantColor(palette, task.quadrant),
                ),
                Expanded(
                  child: ListTile(
                    onTap: selectMode
                        ? onCheckTap
                        : () => _toggle(context, ref),
                    onLongPress: onLongPress,
                    selected: selected,
                    selectedTileColor: palette.accent.withValues(alpha: 0.35),
                    leading: selectMode
                        ? Icon(
                            selected
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            color: selected
                                ? palette.primaryDark
                                : palette.textSecondary,
                            size: 26,
                          )
                        : Icon(
                            task.isDone
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            color: task.isDone
                                ? palette.primary
                                : palette.textSecondary,
                            size: 26,
                          ),
                    title: Text(
                      task.title,
                      style: TextStyle(
                        color: task.isDone
                            ? palette.textSecondary
                            : palette.textPrimary,
                        decoration: task.isDone
                            ? TextDecoration.lineThrough
                            : null,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (timeStr != null) ...[
                            Icon(
                              Icons.access_time,
                              size: 13,
                              color: palette.textSecondary,
                            ),
                            Text(
                              timeStr,
                              style: TextStyle(
                                fontSize: 12,
                                color: palette.textSecondary,
                              ),
                            ),
                          ],
                          Text(
                            _difficultyNames[task.difficulty] ?? '普通',
                            style: TextStyle(
                              fontSize: 12,
                              color: palette.textSecondary,
                            ),
                          ),
                          Text(
                            q.name,
                            style: TextStyle(
                              fontSize: 12,
                              color: palette.textSecondary,
                            ),
                          ),
                          if (_repeatLabels.containsKey(task.repeatRule)) ...[
                            Icon(
                              Icons.repeat,
                              size: 13,
                              color: palette.primaryDark,
                            ),
                            Text(
                              _repeatLabels[task.repeatRule]!,
                              style: TextStyle(
                                fontSize: 12,
                                color: palette.primaryDark,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
