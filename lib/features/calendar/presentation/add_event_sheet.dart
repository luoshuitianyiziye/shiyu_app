import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/morandi_theme.dart';
import '../../../app/widgets/morandi_picker.dart';
import '../../../app/widgets/morandi_time_picker.dart';
import '../../../core/db/database.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/remind_calc.dart';
import '../application/event_service.dart';

/// 新建日历事件底部弹层
Future<void> showAddEventSheet(BuildContext context, {DateTime? initialDate}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).extension<MorandiPalette>()!.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _AddEventSheet(initialDate: initialDate),
  );
}

/// 编辑日历事件底部弹层（左滑「编辑」用）
Future<void> showEditEventSheet(BuildContext context, EventRow event) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).extension<MorandiPalette>()!.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _AddEventSheet(event: event),
  );
}

class _AddEventSheet extends ConsumerStatefulWidget {
  const _AddEventSheet({this.initialDate, this.event});

  final DateTime? initialDate;

  /// 非空 = 编辑已有事件
  final EventRow? event;

  @override
  ConsumerState<_AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends ConsumerState<_AddEventSheet> {
  final _titleController = TextEditingController();
  late DateTime _date;
  TimeOfDay? _time;
  int _remindMinutes = 15;
  final _noteController = TextEditingController();
  bool _saving = false; // 保存防连点（重复建事件 / 重复提醒）

  bool get _isEdit => widget.event != null;

  @override
  void initState() {
    super.initState();
    final e = widget.event;
    if (e != null) {
      // 编辑模式：预填原事件
      _titleController.text = e.title;
      _date = e.date;
      _time = e.time != null
          ? TimeOfDay(hour: e.time!.hour, minute: e.time!.minute)
          : null;
      _remindMinutes = e.remindMinutes;
      _noteController.text = e.note;
    } else {
      final now = DateTime.now();
      _date = widget.initialDate ?? DateTime(now.year, now.month, now.day);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final first = DateTime.now().subtract(const Duration(days: 365));
    final last = DateTime.now().add(const Duration(days: 3650));
    // initialDate 必须落在 [firstDate, lastDate] 内，否则 showDatePicker 会断言失败
    var initial = _date;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showMorandiTimePicker(
      context: context,
      initial: _time,
      title: '事件时间',
      titleIcon: Icons.access_time,
    );
    if (picked != null && mounted) setState(() => _time = picked);
  }

  String get _remindLabel {
    return switch (_remindMinutes) {
      0 => '准时提醒',
      15 => '15 分钟',
      30 => '30 分钟',
      60 => '1 小时',
      1440 => '1 天',
      _ => '$_remindMinutes 分钟',
    };
  }

  /// 提前提醒：莫兰迪小窗选择（与重复规则/分类一致）
  Future<void> _pickRemind() async {
    final picked = await showMorandiPicker<int>(
      context: context,
      title: '提前提醒',
      titleIcon: Icons.notifications_outlined,
      selected: _remindMinutes,
      items: const [
        PickerItem(
          value: 0,
          label: '准时提醒',
          icon: Icons.alarm_on_outlined,
          subtitle: '事件开始时提醒',
        ),
        PickerItem(
          value: 15,
          label: '15 分钟',
          icon: Icons.timer_outlined,
          subtitle: '提前 15 分钟',
        ),
        PickerItem(
          value: 30,
          label: '30 分钟',
          icon: Icons.timer_outlined,
          subtitle: '提前 30 分钟',
        ),
        PickerItem(
          value: 60,
          label: '1 小时',
          icon: Icons.schedule_outlined,
          subtitle: '提前 1 小时',
        ),
        PickerItem(
          value: 1440,
          label: '1 天',
          icon: Icons.event_available_outlined,
          subtitle: '提前 1 天',
        ),
      ],
    );
    if (picked != null && mounted) setState(() => _remindMinutes = picked);
  }

  /// 计算提醒时刻（规则见 [computeEventRemindAt]：提前提醒 / 全天事件 /
  /// 已过时刻修正 / 下限钳制）
  DateTime _remindAt(
    DateTime date,
    DateTime? timeDateTime,
    int remindMinutes,
  ) => computeEventRemindAt(
    date: date,
    time: timeDateTime,
    remindMinutes: remindMinutes,
  );

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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入事件名称')));
      return;
    }
    final timeDateTime = _time != null
        ? DateTime(
            _date.year,
            _date.month,
            _date.day,
            _time!.hour,
            _time!.minute,
          )
        : null;
    final service = ref.read(eventServiceProvider);

    if (_isEdit) {
      // 编辑：更新事件 + 重建提醒（编排在 EventService 内）
      final id = widget.event!.id;
      await service.update(
        id,
        EventsCompanion(
          title: Value(title),
          date: Value(DateTime(_date.year, _date.month, _date.day)),
          time: Value(timeDateTime),
          remindMinutes: Value(_remindMinutes),
          note: Value(_noteController.text.trim()),
          updatedAt: Value(DateTime.now()),
        ),
        title: title,
        remindAt: _remindAt(_date, timeDateTime, _remindMinutes),
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('事件已更新，提醒已同步')));
      }
      return;
    }

    // 新建事件（含当天提醒调度）
    await service.create(
      EventsCompanion.insert(
        title: title,
        date: DateTime(_date.year, _date.month, _date.day),
        time: Value(timeDateTime),
        remindMinutes: Value(_remindMinutes),
        note: Value(_noteController.text.trim()),
      ),
      title: title,
      remindAt: _remindAt(_date, timeDateTime, _remindMinutes),
    );

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('事件已添加，当天会提醒你')));
    }
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
              _isEdit ? '编辑事件' : '新建事件',
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
                hintText: '事件名称（考试 / 纪念日 / 会议…）',
                prefixIcon: Icon(Icons.event_outlined),
              ),
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(
                DateFormat('yyyy年M月d日', 'zh_CN').format(_date),
                style: TextStyle(color: palette.textPrimary),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickDate,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.access_time),
              title: Text(
                _time == null
                    ? '全天（当天 09:00 提醒）'
                    : '时间 ${formatHm(_time!.hour, _time!.minute)}',
                style: TextStyle(color: palette.textPrimary),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickTime,
            ),
            const SizedBox(height: 16),
            Text(
              '提醒',
              style: TextStyle(fontSize: 13, color: palette.textSecondary),
            ),
            const SizedBox(height: 8),
            MorandiOptionField(
              icon: Icons.notifications_outlined,
              label: '提前提醒',
              valueText: _remindLabel,
              onTap: _pickRemind,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                hintText: '备注（可选）',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: Text(
                _isEdit ? '保存修改' : '添加事件',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
