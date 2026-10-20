import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/morandi_theme.dart';
import '../../../app/widgets/empty_state.dart';
import '../../../app/widgets/slidable_actions.dart';
import '../../../core/db/database.dart';
import '../../../core/db/db_providers.dart';
import '../../../core/utils/confirm_dialog.dart';
import '../../../core/utils/format.dart';
import '../../today/application/task_service.dart';
import '../../today/data/quadrants.dart';
import '../../today/presentation/add_task_sheet.dart';
import '../application/event_service.dart';
import 'add_event_sheet.dart';

const _weekdayNames = kWeekdayNames;

/// 日历页：月视图（事件标记 + 当天提醒）+ 倒数日视图
class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selected = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  int _view = 0; // 0=月历 1=倒数日

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final eventsAsync = ref.watch(eventsStreamProvider);
    final monthTasks =
        ref.watch(monthTasksProvider(_month)).value ?? const <TaskRow>[];
    final dayTasks =
        ref.watch(dateTasksProvider(_selected)).value ?? const <TaskRow>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('日历'),
        actions: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('月历')),
              ButtonSegment(value: 1, label: Text('倒数日')),
            ],
            selected: {_view},
            onSelectionChanged: (s) => setState(() => _view = s.first),
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: palette.accent,
              selectedForegroundColor: palette.primaryDark,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null, // 多页 FAB 共存（indexedStack），禁用 hero 动画避免标签冲突
        onPressed: () => showAddEventSheet(context, initialDate: _selected),
        backgroundColor: palette.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      body: eventsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (events) => _view == 0
            ? _MonthView(
                month: _month,
                selected: _selected,
                events: events,
                tasks: monthTasks,
                dayTasks: dayTasks,
                onMonthChange: _changeMonth,
                onSelect: (d) => setState(() => _selected = d),
                onAddTask: () =>
                    showAddTaskSheet(context, initialDate: _selected),
                onAddEvent: () =>
                    showAddEventSheet(context, initialDate: _selected),
              )
            : _CountdownView(events: events),
      ),
    );
  }
}

// ============ 月视图 ============

class _MonthView extends StatelessWidget {
  const _MonthView({
    required this.month,
    required this.selected,
    required this.events,
    required this.tasks,
    required this.dayTasks,
    required this.onMonthChange,
    required this.onSelect,
    required this.onAddTask,
    required this.onAddEvent,
  });

  final DateTime month;
  final DateTime selected;
  final List<EventRow> events;

  /// 当月全部任务（月视图标记用）
  final List<TaskRow> tasks;

  /// 选中日期的任务
  final List<TaskRow> dayTasks;
  final void Function(int delta) onMonthChange;
  final void Function(DateTime day) onSelect;
  final VoidCallback onAddTask;
  final VoidCallback onAddEvent;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);

    final firstDay = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingBlanks = firstDay.weekday - 1;
    final eventsByDay = <int, List<EventRow>>{};
    for (final e in events) {
      if (e.date.year == month.year && e.date.month == month.month) {
        eventsByDay.putIfAbsent(e.date.day, () => []).add(e);
      }
    }
    final tasksByDay = <int, List<TaskRow>>{};
    for (final t in tasks) {
      if (t.date.year == month.year && t.date.month == month.month) {
        tasksByDay.putIfAbsent(t.date.day, () => []).add(t);
      }
    }
    final dayEvents =
        events
            .where(
              (e) =>
                  e.date.year == selected.year &&
                  e.date.month == selected.month &&
                  e.date.day == selected.day,
            )
            .toList()
          ..sort((a, b) => (a.time ?? a.date).compareTo(b.time ?? b.date));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        // 月份导航
        Row(
          children: [
            IconButton(
              onPressed: () => onMonthChange(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                '${month.year} 年 ${month.month} 月',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: palette.textPrimary,
                ),
              ),
            ),
            IconButton(
              onPressed: () => onMonthChange(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // 星期表头
        Row(
          children: _weekdayNames
              .map(
                (w) => Expanded(
                  child: Center(
                    child: Text(
                      w,
                      style: TextStyle(
                        fontSize: 12,
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
        // 日期网格
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 0.95,
          ),
          itemCount: leadingBlanks + daysInMonth,
          itemBuilder: (context, i) {
            if (i < leadingBlanks) return const SizedBox.shrink();
            final day = i - leadingBlanks + 1;
            final date = DateTime(month.year, month.month, day);
            final isToday = date == todayDay;
            final isSelected = date == selected;
            final hasEvents = eventsByDay[day]?.isNotEmpty ?? false;
            final dayTaskList = tasksByDay[day];
            final hasTasks = dayTaskList?.isNotEmpty ?? false;
            final allTasksDone =
                hasTasks && dayTaskList!.every((t) => t.isDone);

            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onSelect(date),
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? palette.accent : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isToday ? palette.primary : null,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$day',
                        style: TextStyle(
                          color: isToday
                              ? Colors.white
                              : isSelected
                              ? palette.primaryDark
                              : palette.textPrimary,
                          fontWeight: isToday
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (hasTasks || hasEvents)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasTasks)
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: allTasksDone
                                    ? palette.outline
                                    : palette.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          if (hasTasks && hasEvents) const SizedBox(width: 2),
                          if (hasEvents)
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: palette.primaryDark,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      )
                    else
                      const SizedBox(height: 5),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        // 选中日的任务与事件
        Row(
          children: [
            Text(
              DateFormat('M月d日', 'zh_CN').format(selected),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: onAddTask,
              icon: const Icon(Icons.checklist, size: 18),
              label: const Text('任务'),
            ),
            TextButton.icon(
              onPressed: onAddEvent,
              icon: const Icon(Icons.event, size: 18),
              label: const Text('事件'),
            ),
          ],
        ),
        if (dayTasks.isEmpty && dayEvents.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                '这一天没有任务和事件',
                style: TextStyle(color: palette.textSecondary, fontSize: 13),
              ),
            ),
          )
        else ...[
          for (final task in dayTasks) _CalendarTaskCard(task: task),
          if (dayTasks.isNotEmpty && dayEvents.isNotEmpty)
            const Divider(height: 20),
          for (final e in dayEvents) _EventCard(event: e),
        ],
      ],
    );
  }
}

/// 日历中的任务卡片：勾选完成 / 点击编辑
class _CalendarTaskCard extends ConsumerWidget {
  const _CalendarTaskCard({required this.task});

  final TaskRow task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final q = quadrantById(task.quadrant);
    final time = task.startTime == null
        ? null
        : formatHm(task.startTime!.hour, task.startTime!.minute);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => showEditTaskSheet(context, task),
        leading: Checkbox(
          value: task.isDone,
          activeColor: palette.primary,
          onChanged: (_) async {
            await ref.read(taskServiceProvider).toggle(task);
          },
        ),
        title: Text(
          task.title,
          style: TextStyle(
            fontSize: 14,
            color: task.isDone ? palette.textSecondary : palette.textPrimary,
            decoration: task.isDone ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            '${time ?? '未设时段'} · ${q.name}'
            '${task.repeatRule == 'none' ? '' : ' · 重复'}',
            style: TextStyle(fontSize: 11, color: palette.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _EventCard extends ConsumerWidget {
  const _EventCard({required this.event});

  final EventRow event;

  /// 左滑「删除」：确认后删除并取消提醒
  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除事件',
      content: '「${event.title}」将被移除',
      confirmText: '删除',
      danger: true,
    );
    if (ok != true) return;
    await ref.read(eventServiceProvider).delete(event);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final timeStr = event.time != null
        ? formatHm(event.time!.hour, event.time!.minute)
        : '全天';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Slidable(
        key: ValueKey('event-${event.id}'),
        endActionPane: buildEditDeletePane(
          context,
          onEdit: () => showEditEventSheet(context, event),
          onDelete: () => _delete(context, ref),
        ),
        child: Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            onTap: () => showEditEventSheet(context, event),
            leading: Icon(Icons.event, color: palette.primaryDark, size: 26),
            title: Text(
              event.title,
              style: TextStyle(color: palette.textPrimary, fontSize: 15),
            ),
            subtitle: Text(
              '$timeStr${event.note.isEmpty ? '' : ' · ${event.note}'}',
              style: TextStyle(color: palette.textSecondary, fontSize: 12),
            ),
            trailing: event.pinned
                ? Icon(Icons.push_pin, size: 16, color: palette.primaryDark)
                : null,
          ),
        ),
      ),
    );
  }
}

// ============ 倒数日视图 ============

class _CountdownView extends StatelessWidget {
  const _CountdownView({required this.events});

  final List<EventRow> events;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);

    final sorted = [...events]..sort((a, b) => a.date.compareTo(b.date));

    if (sorted.isEmpty) {
      return EmptyState(
        icon: Icons.hourglass_empty,
        title: '还没有倒数日',
        subtitle: '添加重要事件，开始倒数',
        actionLabel: '添加事件',
        onAction: () => showAddEventSheet(context),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        for (final e in sorted) _CountdownCard(event: e, today: todayDay),
      ],
    );
  }
}

class _CountdownCard extends ConsumerWidget {
  const _CountdownCard({required this.event, required this.today});

  final EventRow event;
  final DateTime today;

  /// 左滑「删除」：确认后删除并取消提醒
  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除事件',
      content: '「${event.title}」将被移除',
      confirmText: '删除',
      danger: true,
    );
    if (ok != true) return;
    await ref.read(eventServiceProvider).delete(event);
  }

  /// 点击倒数日卡片：弹出详情小窗（事件 + 倒数日期）
  Future<void> _showDetail(BuildContext context) async {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final eventDay = DateTime(
      event.date.year,
      event.date.month,
      event.date.day,
    );
    final diff = eventDay.difference(today).inDays;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(Icons.hourglass_bottom, color: palette.primaryDark, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                event.title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: palette.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow(
              context,
              icon: Icons.event,
              text: '${event.date.year}年${event.date.month}月${event.date.day}日',
            ),
            if (event.time != null)
              _detailRow(
                context,
                icon: Icons.access_time,
                text: formatHm(event.time!.hour, event.time!.minute),
              ),
            if (event.note.isNotEmpty)
              _detailRow(context, icon: Icons.notes, text: event.note),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: palette.accent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    switch (diff) {
                      < 0 => '已过去 ${-diff} 天',
                      0 => '就是今天',
                      _ => '还有 $diff 天',
                    },
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: switch (diff) {
                        <= 7 => palette.danger,
                        _ => palette.primaryDark,
                      },
                    ),
                  ),
                  if (diff != 0)
                    Text(
                      diff < 0
                          ? '${eventDay.year}.${eventDay.month}.${eventDay.day} 已经过去'
                          : '距离 ${eventDay.year}.${eventDay.month}.${eventDay.day}',
                      style: TextStyle(
                        fontSize: 12,
                        color: palette.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(
    BuildContext context, {
    required IconData icon,
    required String text,
  }) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: palette.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 14, color: palette.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final eventDay = DateTime(
      event.date.year,
      event.date.month,
      event.date.day,
    );
    final diff = eventDay.difference(today).inDays;

    final (label, color) = switch (diff) {
      < 0 => ('已过 ${-diff} 天', palette.textSecondary),
      0 => ('就是今天 🎉', palette.danger),
      <= 3 => ('还有 $diff 天', palette.danger),
      <= 7 => ('还有 $diff 天', palette.primaryDark),
      _ => ('还有 $diff 天', palette.textSecondary),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Slidable(
        key: ValueKey('countdown-${event.id}'),
        endActionPane: buildEditDeletePane(
          context,
          onEdit: () => showEditEventSheet(context, event),
          onDelete: () => _delete(context, ref),
        ),
        child: Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: () => _showDetail(context),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: palette.accent.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${event.date.month}.${event.date.day}',
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.primaryDark,
                          ),
                        ),
                        Text(
                          '${event.date.year}',
                          style: TextStyle(
                            fontSize: 10,
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: palette.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
