import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/morandi_theme.dart';
import '../../../app/widgets/morandi_picker.dart';
import '../../../app/widgets/morandi_time_picker.dart';
import '../../../core/ai/ai_client.dart';
import '../../../core/db/database.dart';
import '../../../core/utils/format.dart';
import '../../today/application/task_service.dart';
import '../../today/data/quadrants.dart';
import '../application/ai_providers.dart';
import '../application/ai_service.dart';
import '../data/task_draft.dart';
import 'ai_mascot.dart';

/// AI 助手页面：Q 版形象 + 自然语言生成任务（预览确认后批量创建）
class AiPage extends ConsumerStatefulWidget {
  const AiPage({super.key});

  @override
  ConsumerState<AiPage> createState() => _AiPageState();
}

class _AiPageState extends ConsumerState<AiPage> {
  final _inputController = TextEditingController();
  bool _loading = false;
  List<TaskDraft> _drafts = [];
  String? _error;
  int _ignored = 0;

  static const _difficultyNames = {1: '简单', 2: '普通', 3: '困难'};
  static const _repeatNames = {
    'none': '不重复',
    'daily': '每天',
    'weekdays': '工作日',
    'weekly': '每周',
  };

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  AiMascotMood get _mood {
    if (_loading) return AiMascotMood.thinking;
    if (_error != null) return AiMascotMood.sad;
    if (_drafts.isNotEmpty) return AiMascotMood.happy;
    return AiMascotMood.idle;
  }

  Future<void> _generate() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _ignored = 0;
    });
    try {
      final result = await ref
          .read(aiServiceProvider)
          .generateTasks(_inputController.text);
      if (!mounted) return;
      setState(() {
        _drafts = result.drafts;
        _ignored = result.ignored;
        if (result.drafts.isEmpty) {
          _error = '没有识别到任务，换个说法再试试？';
        }
      });
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '出错了：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addAll() async {
    if (_drafts.isEmpty) return;
    final service = ref.read(taskServiceProvider);
    final count = _drafts.length;
    try {
      for (final draft in _drafts) {
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
      }
      if (!mounted) return;
      setState(() => _drafts = []);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已添加 $count 个任务')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '添加失败：$e');
    }
  }

  Future<void> _editDraft(int index) async {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final updated = await showModalBottomSheet<TaskDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _DraftEditorSheet(draft: _drafts[index]),
    );
    if (updated != null && mounted) {
      setState(() => _drafts[index] = updated);
    }
  }

  void _fillExample(String text) {
    _inputController.text = text;
    _inputController.selection = TextSelection.collapsed(offset: text.length);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final config = ref.watch(aiConfigProvider).value;
    final configured = config?.isConfigured ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 助手'),
        actions: [
          IconButton(
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'AI 设置',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Center(child: AiMascot(mood: _mood, size: 130)),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _inputController,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        hintText: '例如：明天下午 3 点写周报\n或粘贴一段待办/会议文字，让 AI 帮你拆成任务',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _exampleChip('明天下午 3 点写周报', palette),
                        _exampleChip('把「准备期末考试」拆成任务', palette),
                        _exampleChip('整理待办：买牛奶、交话费、预约体检', palette),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _loading ? null : _generate,
                        icon: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.auto_awesome, size: 18),
                        label: Text(_loading ? 'AI 正在思考…' : '让 AI 帮我生成'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!configured) ...[
              const SizedBox(height: 10),
              _banner(
                palette,
                icon: Icons.key_outlined,
                text: '还没有配置 AI：去设置里填写 API Key 后就能使用啦',
                actionLabel: '去设置',
                onTap: () => context.push('/settings'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              _banner(
                palette,
                icon: Icons.error_outline,
                text: _error!,
                danger: true,
                actionLabel: '重试',
                onTap: _loading ? null : _generate,
              ),
            ],
            if (_drafts.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.checklist, size: 18, color: palette.primaryDark),
                  const SizedBox(width: 6),
                  Text(
                    '识别到 ${_drafts.length} 条任务',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                  ),
                  if (_ignored > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      '（忽略 $_ignored 条格式异常）',
                      style: TextStyle(
                        fontSize: 11,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _drafts.length; i++)
                _DraftTile(
                  draft: _drafts[i],
                  index: i,
                  difficultyNames: _difficultyNames,
                  repeatNames: _repeatNames,
                  onTap: () => _editDraft(i),
                  onDelete: () => setState(() => _drafts.removeAt(i)),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _addAll,
                  icon: const Icon(Icons.playlist_add_check, size: 18),
                  label: Text('全部添加（${_drafts.length}）'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _exampleChip(String text, MorandiPalette palette) {
    return ActionChip(
      label: Text(text, style: const TextStyle(fontSize: 11)),
      backgroundColor: palette.accent.withValues(alpha: 0.35),
      side: BorderSide(color: palette.outline),
      onPressed: () => _fillExample(text),
    );
  }

  Widget _banner(
    MorandiPalette palette, {
    required IconData icon,
    required String text,
    String? actionLabel,
    VoidCallback? onTap,
    bool danger = false,
  }) {
    final color = danger ? palette.danger : palette.primaryDark;
    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: 12, color: palette.textPrimary),
              ),
            ),
            if (actionLabel != null)
              TextButton(
                onPressed: onTap,
                child: Text(actionLabel, style: TextStyle(color: color)),
              ),
          ],
        ),
      ),
    );
  }
}

/// 任务草案行：标题 + 摘要，点击编辑 / 右侧删除
class _DraftTile extends StatelessWidget {
  const _DraftTile({
    required this.draft,
    required this.index,
    required this.difficultyNames,
    required this.repeatNames,
    required this.onTap,
    required this.onDelete,
  });

  final TaskDraft draft;
  final int index;
  final Map<int, String> difficultyNames;
  final Map<String, String> repeatNames;
  final VoidCallback onTap;
  final VoidCallback onDelete;

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
            '${difficultyNames[draft.difficulty] ?? '普通'}'
            '${draft.repeatRule == 'none' ? '' : ' · ${repeatNames[draft.repeatRule]}'}',
            style: TextStyle(fontSize: 11, color: palette.textSecondary),
          ),
        ),
        trailing: IconButton(
          onPressed: onDelete,
          icon: Icon(
            Icons.delete_outline,
            size: 18,
            color: palette.danger,
          ),
          tooltip: '移除这条',
        ),
      ),
    );
  }
}

/// 草案编辑弹层（标题 / 象限 / 难度 / 日期 / 时段 / 重复）
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('标题不能为空')),
      );
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
                    color: _quadrant == q.id
                        ? palette.primaryDark
                        : palette.textSecondary,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Text('难度', style: TextStyle(fontSize: 13, color: palette.textSecondary)),
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
