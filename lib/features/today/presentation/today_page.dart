import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../../app/theme/morandi_theme.dart';
import '../../../app/widgets/slidable_actions.dart';
import '../../../core/db/database.dart';
import '../../../core/db/db_providers.dart';
import '../../../core/feedback/feedback_debouncer.dart';
import '../../../core/notifications/notification_service.dart';
import '../../growth/data/ranks.dart';
import '../../growth/presentation/rank_up_dialog.dart';
import '../data/quadrants.dart';
import 'add_task_sheet.dart';

const _weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

const _difficultyNames = {1: '简单', 2: '普通', 3: '困难'};

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
        title: Text('${today.month}月${today.day}日 · 周${_weekdayNames[today.weekday - 1]}'),
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
            child: Center(child: SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )),
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
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 8,
                            backgroundColor: palette.accent,
                            color: palette.primary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '距 Lv.${level + 1} 还差 ${nextXp - user.xpTotal} XP · 连续 ${user.streakDays} 天',
                          style: TextStyle(fontSize: 11, color: palette.textSecondary),
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

  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      _selected.clear();
    });
  }

  /// 恢复任务为未完成，并按开始时间重建提醒（完成/删除时取消的提醒恢复对称）。
  Future<void> _restoreTask(TaskRow task) async {
    final db = ref.read(databaseProvider);
    await db.uncompleteTaskById(task.id);
    final st = task.startTime;
    if (st != null && st.isAfter(DateTime.now())) {
      await NotificationService.instance.scheduleTaskReminder(
        taskId: task.id,
        title: task.title,
        at: st,
      );
    }
    ref.invalidate(statsSnapshotProvider);
    await rescheduleEndOfDay(db);
  }

  Future<void> _restoreSelected() async {
    final db = ref.read(databaseProvider);
    for (final id in _selected.toList()) {
      final task = widget.tasks.where((t) => t.id == id).firstOrNull;
      if (task != null) {
        await _restoreTask(task);
      } else {
        await db.uncompleteTaskById(id);
      }
    }
    ref.invalidate(statsSnapshotProvider);
    await rescheduleEndOfDay(db);
    if (mounted) setState(() => _selected.clear());
  }

  Future<void> _deleteSelected() async {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final count = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('彻底删除'),
        content: Text('将永久删除 $count 个已完成任务（经验保留，无法恢复）'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: palette.danger),
            child: const Text('彻底删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final db = ref.read(databaseProvider);
    await db.hardDeleteTasks(_selected.toList());
    ref.invalidate(statsSnapshotProvider);
    await rescheduleEndOfDay(db);
    if (!mounted) return;
    setState(() {
      _selected.clear();
      // 已完成任务全部删光时退出多选模式，避免失去「取消」入口
      final remainingDone =
          widget.tasks.where((t) => t.isDone).length - _selected.length;
      if (remainingDone <= 0) _selectMode = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final tasks = widget.tasks;
    final unfinished = tasks.where((t) => !t.isDone).toList();
    final done = tasks.where((t) => t.isDone).toList();
    // build 期只读：已完成列表为空时强制退出多选模式
    // （selected 的失效清理在恢复/删除完成时已同步执行）
    if (done.isEmpty && _selectMode) {
      _selectMode = false;
      _selected.clear();
    }

    final grouped = <int, List<TaskRow>>{};
    for (final t in unfinished) {
      grouped.putIfAbsent(t.quadrant, () => []).add(t);
    }

    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wb_sunny_outlined, size: 56, color: palette.accent),
            const SizedBox(height: 12),
            Text(
              '今天还没有任务',
              style: TextStyle(fontSize: 16, color: palette.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              '点右下角 + 添加第一个任务',
              style: TextStyle(fontSize: 13, color: palette.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      children: [
        for (final q in kQuadrants)
          if (grouped[q.id]?.isNotEmpty ?? false) ...[
            _QuadrantHeader(q: q),
            const SizedBox(height: 8),
            ...grouped[q.id]!.map((t) => _TaskTile(task: t)),
            const SizedBox(height: 12),
          ],
        // ===== 已完成区（与未完成互不干扰）=====
        if (done.isNotEmpty) ...[
          Row(
            children: [
              Icon(Icons.check_circle_outline, size: 18, color: palette.primaryDark),
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
              TextButton(
                onPressed: _toggleSelectMode,
                child: Text(_selectMode ? '取消' : '多选'),
              ),
            ],
          ),
          if (_selectMode) ...[
            _SelectionBar(
              selectedCount: _selected.length,
              totalCount: done.length,
              allSelected: _selected.length == done.length,
              onToggleAll: () {
                setState(() {
                  if (_selected.length == done.length) {
                    _selected.clear();
                  } else {
                    _selected
                      ..clear()
                      ..addAll(done.map((t) => t.id));
                  }
                });
              },
              onRestore: _restoreSelected,
              onDelete: _deleteSelected,
            ),
            const SizedBox(height: 8),
          ],
          ...done.map(
            (t) => _DoneTaskTile(
              task: t,
              selectMode: _selectMode,
              selected: _selected.contains(t.id),
              onTap: () {
                if (!_selectMode) {
                  // 非多选模式：点击恢复为未完成（并重建开始提醒）
                  _restoreTask(t);
                  return;
                }
                setState(() {
                  if (!_selected.remove(t.id)) _selected.add(t.id);
                });
              },
            ),
          ),
        ],
      ],
    );
  }
}

/// 已完成区多选工具条：全选 / 已选数 / 恢复 / 彻底删除
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.selectedCount,
    required this.totalCount,
    required this.allSelected,
    required this.onToggleAll,
    required this.onRestore,
    required this.onDelete,
  });

  final int selectedCount;
  final int totalCount;
  final bool allSelected;
  final VoidCallback onToggleAll;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

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
                    allSelected ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 18,
                  ),
                  label: Text(allSelected ? '取消全选' : '全选'),
                ),
                const Spacer(),
                Text(
                  '已选 $selectedCount/$totalCount',
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: selectedCount == 0 ? null : onRestore,
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text('恢复'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: selectedCount == 0 ? null : onDelete,
                    icon: const Icon(Icons.delete_forever_outlined, size: 18),
                    label: const Text('彻底删除'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.danger,
                      side: BorderSide(color: palette.danger.withValues(alpha: 0.6)),
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

/// 已完成任务行：普通模式点击恢复；多选模式点击勾选
class _DoneTaskTile extends StatelessWidget {
  const _DoneTaskTile({
    required this.task,
    required this.selectMode,
    required this.selected,
    required this.onTap,
  });

  final TaskRow task;
  final bool selectMode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final q = quadrantById(task.quadrant);
    final timeStr = task.startTime != null
        ? '${task.startTime!.hour.toString().padLeft(2, '0')}:${task.startTime!.minute.toString().padLeft(2, '0')}'
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: selected ? palette.accent.withValues(alpha: 0.5) : null,
      child: ListTile(
        onTap: onTap,
        leading: selectMode
            ? Icon(
                selected ? Icons.check_box : Icons.check_box_outline_blank,
                color: selected ? palette.primaryDark : palette.textSecondary,
                size: 24,
              )
            : Icon(
                Icons.check_circle,
                color: palette.primary,
                size: 26,
              ),
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
                Icon(Icons.access_time, size: 13, color: palette.textSecondary),
                Text(timeStr, style: TextStyle(fontSize: 12, color: palette.textSecondary)),
              ],
              Text(_difficultyNames[task.difficulty] ?? '普通',
                  style: TextStyle(fontSize: 12, color: palette.textSecondary)),
              Text(q.name, style: TextStyle(fontSize: 12, color: palette.textSecondary)),
              if (task.xpAwarded > 0)
                Text('+${task.xpAwarded} XP',
                    style: TextStyle(fontSize: 12, color: palette.primaryDark)),
            ],
          ),
        ),
        trailing: selectMode
            ? null
            : Icon(Icons.restore, size: 18, color: palette.textSecondary),
      ),
    );
  }
}

class _QuadrantHeader extends StatelessWidget {
  const _QuadrantHeader({required this.q});

  final QuadrantInfo q;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final color = switch (q.id) {
      1 => palette.danger,
      2 => palette.primary,
      3 => palette.primaryDark,
      _ => palette.textSecondary,
    };

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
  const _TaskTile({required this.task});

  final TaskRow task;

  /// 连点防护：刚完成的任务在短时间内忽略「恢复」点击，
  /// 避免第三次连点命中已刷新的 tile 把任务撤销回未完成。
  static final Map<int, DateTime> _recentlyCompleted = {};

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    try {
      if (!task.isDone) {
        _recentlyCompleted[task.id] = DateTime.now();
        final result = await db.completeTaskAndAwardXp(task);
        await NotificationService.instance.cancelTaskReminder(task.id);
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
        await db.uncompleteTask(task);
        final st = task.startTime;
        if (st != null && st.isAfter(DateTime.now())) {
          await NotificationService.instance.scheduleTaskReminder(
            taskId: task.id,
            title: task.title,
            at: st,
          );
        }
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
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除任务'),
        content: Text('「${task.title}」将从列表移除'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: palette.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final db = ref.read(databaseProvider);
    await db.softDeleteTask(task.id);
    await NotificationService.instance.cancelTaskReminder(task.id);
    ref.invalidate(statsSnapshotProvider);
    await rescheduleEndOfDay(db);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final q = quadrantById(task.quadrant);
    final timeStr = task.startTime != null
        ? '${task.startTime!.hour.toString().padLeft(2, '0')}:${task.startTime!.minute.toString().padLeft(2, '0')}'
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Slidable(
        key: ValueKey('task-${task.id}'),
        // 右滑 → 完成（与点击图标同逻辑）
        startActionPane: buildCompletePane(
          context,
          onComplete: () => _toggle(context, ref),
        ),
        endActionPane: buildEditDeletePane(
          context,
          onEdit: () => showEditTaskSheet(context, task),
          onDelete: () => _delete(context, ref),
        ),
        child: Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            onTap: () => _toggle(context, ref),
          leading: Icon(
            task.isDone ? Icons.check_circle : Icons.radio_button_unchecked,
            color: task.isDone ? palette.primary : palette.textSecondary,
            size: 26,
          ),
          title: Text(
            task.title,
            style: TextStyle(
              color: task.isDone ? palette.textSecondary : palette.textPrimary,
              decoration: task.isDone ? TextDecoration.lineThrough : null,
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
                  Icon(Icons.access_time, size: 13, color: palette.textSecondary),
                  Text(timeStr, style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                ],
                Text(_difficultyNames[task.difficulty] ?? '普通',
                    style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                Text(q.name, style: TextStyle(fontSize: 12, color: palette.textSecondary)),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }
}
