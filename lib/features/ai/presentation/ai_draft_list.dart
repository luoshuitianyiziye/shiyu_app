import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/morandi_theme.dart';
import '../../../app/widgets/morandi_picker.dart';
import '../../../app/widgets/morandi_time_picker.dart';
import '../../../core/db/database.dart';
import '../../../core/utils/format.dart';
import '../../today/application/task_service.dart';
import '../../today/data/quadrants.dart';
import '../data/added_summary.dart';
import '../data/task_draft.dart';

/// AI 任务草案列表（可编辑/删除/批量添加）——AI 页与笔记页共用。
///
/// 生成结果始终是「草案」：用户确认后才调用 TaskService 落库。
class AiDraftList extends ConsumerStatefulWidget {
  const AiDraftList({super.key, required this.drafts, this.onAdded});

  final List<TaskDraft> drafts;

  /// 批量添加完成回调（外部可据此清空草案状态）
  final VoidCallback? onAdded;

  @override
  ConsumerState<AiDraftList> createState() => _AiDraftListState();
}

class _AiDraftListState extends ConsumerState<AiDraftList> {
  late List<TaskDraft> _items;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.drafts);
  }

  Future<void> _edit(int index) async {
    final updated = await showDraftEditor(context, _items[index]);
    if (updated != null && mounted) {
      setState(() => _items[index] = updated);
    }
  }

  Future<void> _addAll() async {
    if (_items.isEmpty || _adding) return;
    setState(() => _adding = true);
    final service = ref.read(taskServiceProvider);
    final now = DateTime.now();

    final succeeded = <TaskDraft>[];
    final failed = <TaskDraft>[];
    for (final draft in _items) {
      try {
        await service.create(
          TasksCompanion.insert(
            title: draft.title,
            date: draft.effectiveDate,
            quadrant: Value(draft.quadrant),
            difficulty: Value(draft.difficulty),
            startTime: Value(draft.startDateTime),
            repeatRule: Value(draft.repeatRule),
          ),
          title: draft.title,
          startTime: draft.startDateTime,
        );
        succeeded.add(draft);
      } catch (_) {
        // 单条失败不中断其余条目，保留在列表供重试
        failed.add(draft);
      }
    }

    if (!mounted) return;
    setState(() {
      // 只保留失败条目，方便用户重试；全部成功则清空
      _items = failed;
      _adding = false;
    });

    final messenger = ScaffoldMessenger.of(context);
    if (succeeded.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('添加失败，请稍后重试')));
      return;
    }

    // 按日期统计：让用户明确任务被加到了哪一天（未来日期不在今日页显示）
    final failedHint = failed.isEmpty ? '' : '，${failed.length} 个失败可重试';

    messenger.showSnackBar(
      SnackBar(
        content: Text('${summarizeAddedTasks(succeeded, now: now)}$failedHint'),
        duration: const Duration(seconds: 4),
      ),
    );

    if (failed.isEmpty) {
      widget.onAdded?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    if (_items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.checklist, size: 18, color: palette.primaryDark),
            const SizedBox(width: 6),
            Text(
              '识别到 ${_items.length} 条任务',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < _items.length; i++)
          _DraftTile(
            draft: _items[i],
            index: i,
            onTap: () => _edit(i),
            onDelete: () => setState(() => _items.removeAt(i)),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _adding ? null : _addAll,
          icon: _adding
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.playlist_add_check, size: 18),
          label: Text('全部添加（${_items.length}）'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        ),
      ],
    );
  }
}

/// 任务草案行：标题 + 摘要，点击编辑 / 右侧删除
class _DraftTile extends StatelessWidget {
  const _DraftTile({
    required this.draft,
    required this.index,
    required this.onTap,
    required this.onDelete,
  });

  final TaskDraft draft;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  static const _difficultyNames = {1: '简单', 2: '普通', 3: '困难'};
  static const _repeatNames = {
    'none': '不重复',
    'daily': '每天',
    'weekdays': '工作日',
    'weekly': '每周',
  };

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final q = quadrantById(draft.quadrant);
    final timeStr = draft.startTime == null
        ? null
        : formatHm(draft.startTime!.hour, draft.startTime!.minute);
    final dateStr = draft.date == null
        ? '今天'
        : '${draft.date!.month}月${draft.date!.day}日';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          radius: 15,
          backgroundColor: palette.accent,
          child: Text(
            '${index + 1}',
            style: TextStyle(fontSize: 12, color: palette.primaryDark),
          ),
        ),
        title: Text(
          draft.title,
          style: TextStyle(fontSize: 14, color: palette.textPrimary),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            '$dateStr${timeStr == null ? '' : ' $timeStr'} · ${q.name} · '
            '${_difficultyNames[draft.difficulty] ?? '普通'}'
            '${draft.repeatRule == 'none' ? '' : ' · ${_repeatNames[draft.repeatRule]}'}',
            style: TextStyle(fontSize: 11, color: palette.textSecondary),
          ),
        ),
        trailing: IconButton(
          onPressed: onDelete,
          icon: Icon(Icons.delete_outline, size: 18, color: palette.danger),
          tooltip: '移除这条',
        ),
      ),
    );
  }
}

/// 打开草案编辑弹层（标题 / 象限 / 难度 / 日期 / 时段 / 重复），返回修改后的草案
Future<TaskDraft?> showDraftEditor(BuildContext context, TaskDraft draft) {
  final palette = Theme.of(context).extension<MorandiPalette>()!;
  return showModalBottomSheet<TaskDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: palette.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _DraftEditorSheet(draft: draft),
  );
}

class _DraftEditorSheet extends StatefulWidget {
  const _DraftEditorSheet({required this.draft});

  final TaskDraft draft;

  @override
  State<_DraftEditorSheet> createState() => _DraftEditorSheetState();
}

class _DraftEditorSheetState extends State<_DraftEditorSheet> {
  late final TextEditingController _titleController;
  late int _quadrant;
  late int _difficulty;
  late DateTime? _date;
  late TimeOfDay? _time;
  late String _repeat;

  static const _difficultyLabels = {1: '简单', 2: '普通', 3: '困难'};
  static const _repeatLabels = {
    'none': '不重复',
    'daily': '每天',
    'weekdays': '工作日',
    'weekly': '每周',
  };

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.draft.title);
    _quadrant = widget.draft.quadrant;
    _difficulty = widget.draft.difficulty;
    _date = widget.draft.date;
    _time = widget.draft.startTime;
    _repeat = widget.draft.repeatRule;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? today,
      firstDate: today,
      lastDate: DateTime(today.year + 2, today.month, today.day),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showMorandiTimePicker(
      context: context,
      initial: _time,
      title: '开始时段',
      titleIcon: Icons.access_time,
    );
    if (picked != null && mounted) setState(() => _time = picked);
  }

  Future<void> _pickRepeat() async {
    final picked = await showMorandiPicker<String>(
      context: context,
      title: '重复规则',
      titleIcon: Icons.repeat,
      selected: _repeat,
      items: [
        for (final entry in _repeatLabels.entries)
          PickerItem(value: entry.key, label: entry.value),
      ],
    );
    if (picked != null && mounted) setState(() => _repeat = picked);
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('标题不能为空')));
      return;
    }
    Navigator.of(context).pop(
      TaskDraft(
        title: title,
        quadrant: _quadrant,
        difficulty: _difficulty,
        date: _date,
        startTime: _time,
        repeatRule: _repeat,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
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
              '调整任务',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                hintText: '任务标题',
                prefixIcon: Icon(Icons.task_alt_outlined),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '四象限',
              style: TextStyle(fontSize: 13, color: palette.textSecondary),
            ),
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
                    color: _quadrant == q.id
                        ? palette.primaryDark
                        : palette.textSecondary,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Text(
              '难度',
              style: TextStyle(fontSize: 13, color: palette.textSecondary),
            ),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: [
                for (final entry in _difficultyLabels.entries)
                  ButtonSegment(value: entry.key, label: Text(entry.value)),
              ],
              selected: {_difficulty},
              onSelectionChanged: (s) => setState(() => _difficulty = s.first),
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: palette.accent,
                selectedForegroundColor: palette.primaryDark,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(
                _date == null
                    ? '今天'
                    : '${_date!.year}年${_date!.month}月${_date!.day}日',
                style: TextStyle(color: palette.textPrimary),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickDate,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.access_time),
              title: Text(
                _time == null ? '不设时段' : formatHm(_time!.hour, _time!.minute),
                style: TextStyle(color: palette.textPrimary),
              ),
              trailing: _time == null
                  ? const Icon(Icons.chevron_right)
                  : IconButton(
                      onPressed: () => setState(() => _time = null),
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: '清除时段',
                    ),
              onTap: _pickTime,
            ),
            MorandiOptionField(
              icon: Icons.repeat,
              label: '重复',
              valueText: _repeatLabels[_repeat] ?? '不重复',
              onTap: _pickRepeat,
              dense: true,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                child: const Text('保存调整'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
