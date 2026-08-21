import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/morandi_theme.dart';
import '../../../app/widgets/morandi_picker.dart';
import '../../../app/widgets/morandi_time_picker.dart';
import '../../../core/db/database.dart';
import '../../../core/db/db_providers.dart';
import '../../../core/notifications/notification_service.dart';
import '../data/quadrants.dart';

/// 新建任务底部弹层
Future<void> showAddTaskSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).extension<MorandiPalette>()!.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _AddTaskSheet(),
  );
}

/// 编辑任务底部弹层（今日页左滑「编辑」用）
Future<void> showEditTaskSheet(BuildContext context, TaskRow task) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).extension<MorandiPalette>()!.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _AddTaskSheet(task: task),
  );
}

class _AddTaskSheet extends ConsumerStatefulWidget {
  const _AddTaskSheet({this.task});

  /// 非空 = 编辑已有任务
  final TaskRow? task;

  @override
  ConsumerState<_AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends ConsumerState<_AddTaskSheet> {
  final _titleController = TextEditingController();
  int _quadrant = 2; // 默认「重要不紧急」
  int _difficulty = 2; // 默认「普通」
  bool _withTime = false;
  TimeOfDay? _startTime;
  String _repeat = 'none';
  bool _saving = false; // 保存防连点（重复建任务 / 重复提醒 / 二次 pop）

  bool get _isEdit => widget.task != null;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    if (t != null) {
      _titleController.text = t.title;
      _quadrant = t.quadrant;
      _difficulty = t.difficulty;
      _withTime = t.startTime != null;
      _startTime = t.startTime != null
          ? TimeOfDay(hour: t.startTime!.hour, minute: t.startTime!.minute)
          : null;
      _repeat = t.repeatRule;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    _saving = true;
    try {
      await _doSave();
    } finally {
      _saving = false;
    }
  }

  Future<void> _doSave() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入任务标题')),
      );
      return;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final db = ref.read(databaseProvider);

    final startDateTime = _withTime && _startTime != null
        ? DateTime(today.year, today.month, today.day,
            _startTime!.hour, _startTime!.minute)
        : null;
    // 开始时间已过 → 提醒不会触发（scheduleTaskReminder 内部会跳过），
    // 提前告知用户，避免「已添加」但实际无提醒的误导
    final startInPast =
        startDateTime != null && startDateTime.isBefore(DateTime.now());

    if (_isEdit) {
      // 编辑：更新任务 + 重建开始提醒
      await db.updateTask(
        widget.task!.id,
        TasksCompanion(
          title: Value(title),
          quadrant: Value(_quadrant),
          difficulty: Value(_difficulty),
          startTime: Value(startDateTime),
          repeatRule: Value(_repeat),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await NotificationService.instance.cancelTaskReminder(widget.task!.id);
      if (startDateTime != null) {
        await NotificationService.instance.scheduleTaskReminder(
          taskId: widget.task!.id,
          title: title,
          at: startDateTime,
        );
      }
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              startInPast ? '任务已更新（该时段已过，未设提醒）' : '任务已更新，提醒已同步',
            ),
          ),
        );
      }
      return;
    }

    final id = await db.addTask(
      TasksCompanion.insert(
        title: title,
        date: today,
        quadrant: Value(_quadrant),
        difficulty: Value(_difficulty),
        startTime: Value(startDateTime),
        repeatRule: Value(_repeat),
      ),
    );
    // 今日任务数变化 → 刷新统计快照 + 收尾提醒数字
    ref.invalidate(statsSnapshotProvider);
    await rescheduleEndOfDay(db);

    // 设置开始时段 → 到时提醒
    if (startDateTime != null) {
      await NotificationService.instance
          .scheduleTaskReminder(taskId: id, title: title, at: startDateTime);
    }

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            startInPast ? '已添加到今日任务（该时段已过，未设提醒）' : '已添加到今日任务',
          ),
        ),
      );
    }
  }

  Future<void> _pickTime() async {
    final picked = await showMorandiTimePicker(
      context: context,
      initial: _startTime,
      title: '开始时段',
      titleIcon: Icons.access_time,
    );
    if (picked != null && mounted) setState(() => _startTime = picked);
  }

  static const _repeatLabels = {
    'none': '不重复',
    'daily': '每天',
    'weekdays': '工作日',
    'weekly': '每周',
  };

  String get _repeatLabel => _repeatLabels[_repeat] ?? '不重复';

  /// 重复规则：莫兰迪小窗选择（与笔记分类一致）
  Future<void> _pickRepeat() async {
    final picked = await showMorandiPicker<String>(
      context: context,
      title: '重复规则',
      titleIcon: Icons.repeat,
      selected: _repeat,
      items: const [
        PickerItem(
          value: 'none',
          label: '不重复',
          icon: Icons.block,
          subtitle: '只在当天出现',
        ),
        PickerItem(
          value: 'daily',
          label: '每天',
          icon: Icons.calendar_today_outlined,
          subtitle: '每天自动生成',
        ),
        PickerItem(
          value: 'weekdays',
          label: '工作日',
          icon: Icons.work_outline,
          subtitle: '周一至周五',
        ),
        PickerItem(
          value: 'weekly',
          label: '每周',
          icon: Icons.date_range_outlined,
          subtitle: '每周同一天',
        ),
      ],
    );
    if (picked != null && mounted) setState(() => _repeat = picked);
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;

    return Padding(
      // 键盘弹出时上移
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _isEdit ? '编辑任务' : '新建任务',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '要完成什么？',
                prefixIcon: Icon(Icons.task_alt_outlined),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),            ),
            const SizedBox(height: 20),
            Text('四象限', style: TextStyle(fontSize: 13, color: palette.textSecondary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kQuadrants.map((q) {
                return ChoiceChip(
                  label: Text(q.name),
                  selected: _quadrant == q.id,
                  onSelected: (_) => setState(() => _quadrant = q.id),
                  selectedColor: palette.accent,
                  labelStyle: TextStyle(
                    color: _quadrant == q.id ? palette.primaryDark : palette.textSecondary,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            Text('难度', style: TextStyle(fontSize: 13, color: palette.textSecondary)),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('简单')),
                ButtonSegment(value: 2, label: Text('普通')),
                ButtonSegment(value: 3, label: Text('困难')),
              ],
              selected: {_difficulty},
              onSelectionChanged: (s) => setState(() => _difficulty = s.first),
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: palette.accent,
                selectedForegroundColor: palette.primaryDark,
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('设置开始时段', style: TextStyle(color: palette.textPrimary)),
              subtitle: Text(
                _withTime && _startTime != null
                    ? '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')} 开始提醒'
                    : '到时提醒我',
                style: TextStyle(color: palette.textSecondary, fontSize: 12),
              ),
              value: _withTime,
              activeTrackColor: palette.primary,
              onChanged: (v) async {
                if (!v) {
                  // 关闭：仅关闭开关，保留已选时间供下次预选
                  setState(() => _withTime = false);
                  return;
                }
                // 每次打开都弹出滚动选择器（预选上次时间）：
                // 确定后才开启；取消则保持关闭，避免「开着却没时间」。
                final picked = await showMorandiTimePicker(
                  context: context,
                  initial: _startTime,
                  title: '开始时段',
                  titleIcon: Icons.access_time,
                );
                if (!mounted) return;
                if (picked == null) {
                  setState(() => _withTime = false);
                  return;
                }
                setState(() {
                  _startTime = picked;
                  _withTime = true;
                });
              },
              secondary: _withTime && _startTime != null
                  ? IconButton(
                      onPressed: _pickTime,
                      icon: const Icon(Icons.access_time),
                      color: palette.primaryDark,
                    )
                  : null,
            ),
            const SizedBox(height: 16),
            Text('重复', style: TextStyle(fontSize: 13, color: palette.textSecondary)),
            const SizedBox(height: 8),
            MorandiOptionField(
              icon: Icons.repeat,
              label: '重复规则',
              valueText: _repeatLabel,
              onTap: _pickRepeat,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: Text(
                _isEdit ? '保存修改' : '添加任务',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
