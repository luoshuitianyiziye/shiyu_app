import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/morandi_theme.dart';

/// 弹出莫兰迪「滚动时间选择器」（双列滚轮，24 小时制时/分）。
/// 小时与分钟各占半宽、数字在各自区域内居中，单位标签固定在列内左侧。
/// 返回选中的 [TimeOfDay]；取消则返回 null。
Future<TimeOfDay?> showMorandiTimePicker({
  required BuildContext context,
  TimeOfDay? initial,
  String title = '选择时间',
  IconData titleIcon = Icons.access_time,
}) {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).extension<MorandiPalette>()!.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => SafeArea(
      child: SingleChildScrollView(
        child: _MorandiTimePicker(
          initial: initial,
          title: title,
          titleIcon: titleIcon,
        ),
      ),
    ),
  );
}

class _MorandiTimePicker extends StatefulWidget {
  const _MorandiTimePicker({
    required this.initial,
    required this.title,
    required this.titleIcon,
  });

  final TimeOfDay? initial;
  final String title;
  final IconData titleIcon;

  @override
  State<_MorandiTimePicker> createState() => _MorandiTimePickerState();
}

class _MorandiTimePickerState extends State<_MorandiTimePicker> {
  late int _hour;
  late int _minute;
  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;

  @override
  void initState() {
    super.initState();
    final t = widget.initial ?? const TimeOfDay(hour: 9, minute: 0);
    _hour = t.hour;
    _minute = t.minute;
    _hourController = FixedExtentScrollController(initialItem: _hour);
    _minuteController = FixedExtentScrollController(initialItem: _minute);
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  /// 单列滚轮：数字在列内居中，单位标签固定左侧。
  Widget _buildWheel({
    required FixedExtentScrollController controller,
    required int count,
    required int value,
    required String unit,
    required ValueChanged<int> onChanged,
  }) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;

    return Stack(
      alignment: Alignment.center,
      children: [
        CupertinoPicker(
          scrollController: controller,
          itemExtent: 36,
          magnification: 1.2,
          squeeze: 1.15,
          backgroundColor: Colors.transparent,
          onSelectedItemChanged: onChanged,
          selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
            background: palette.accent.withValues(alpha: 0.55),
            capStartEdge: false,
            capEndEdge: false,
          ),
          children: [
            for (var i = 0; i < count; i++)
              Center(
                child: Text(
                  i.toString().padLeft(2, '0'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: i == value ? FontWeight.w600 : FontWeight.w400,
                    color: i == value
                        ? palette.primaryDark
                        : palette.textSecondary,
                  ),
                ),
              ),
          ],
        ),
        // 单位标签：固定于列内左侧，垂直居中
        Positioned(
          left: 10,
          top: 0,
          bottom: 0,
          child: Center(
            child: Text(
              unit,
              style: TextStyle(fontSize: 14, color: palette.textSecondary),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Row(
            children: [
              Icon(widget.titleIcon, size: 18, color: palette.primaryDark),
              const SizedBox(width: 8),
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: palette.textPrimary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 200,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: palette.accent.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              Expanded(
                child: _buildWheel(
                  controller: _hourController,
                  count: 24,
                  value: _hour,
                  unit: '时',
                  onChanged: (i) => setState(() => _hour = i),
                ),
              ),
              Expanded(
                child: _buildWheel(
                  controller: _minuteController,
                  count: 60,
                  value: _minute,
                  unit: '分',
                  onChanged: (i) => setState(() => _minute = i),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () =>
                      Navigator.of(context)
                          .pop(TimeOfDay(hour: _hour, minute: _minute)),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('确定'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
