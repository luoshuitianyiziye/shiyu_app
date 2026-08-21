import 'package:flutter/material.dart';

import '../theme/morandi_theme.dart';

/// 莫兰迪「小窗」选择项
class PickerItem<T> {
  const PickerItem({
    required this.value,
    required this.label,
    this.icon,
    this.color,
    this.subtitle,
  });

  final T value;
  final String label;
  final IconData? icon;
  /// 图标底色（十六进制/Color）
  final Color? color;
  final String? subtitle;
}

/// 弹出莫兰迪风格选择小窗（重复规则 / 笔记分类等通用）。
/// 返回选中的值；取消则返回 null。
Future<T?> showMorandiPicker<T>({
  required BuildContext context,
  required String title,
  required List<PickerItem<T>> items,
  required T selected,
  IconData? titleIcon,
}) {
  final palette = Theme.of(context).extension<MorandiPalette>()!;
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: palette.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
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
                if (titleIcon != null) ...[
                  Icon(titleIcon, size: 18, color: palette.primaryDark),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                for (final item in items)
                  _PickerTile<T>(
                    item: item,
                    selected: item.value == selected,
                    onTap: () => Navigator.of(ctx).pop(item.value),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class _PickerTile<T> extends StatelessWidget {
  const _PickerTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final PickerItem<T> item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ListTile(
        onTap: onTap,
        selected: selected,
        selectedTileColor: palette.accent.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: (item.color ?? palette.accent).withValues(alpha: 0.55),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(
            item.icon ?? Icons.circle_outlined,
            size: 18,
            color: selected ? palette.primaryDark : palette.textSecondary,
          ),
        ),
        title: Text(
          item.label,
          style: TextStyle(
            fontSize: 15,
            color: palette.textPrimary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        subtitle: item.subtitle == null
            ? null
            : Text(
                item.subtitle!,
                style: TextStyle(fontSize: 12, color: palette.textSecondary),
              ),
        trailing: selected
            ? Icon(Icons.check_circle, size: 22, color: palette.primaryDark)
            : null,
      ),
    );
  }
}

/// 莫兰迪「可点击字段」：展示当前值，点击弹出 [showMorandiPicker]。
/// 用于重复规则 / 笔记分类等小窗选择，保持全 App 一致。
class MorandiOptionField extends StatelessWidget {
  const MorandiOptionField({
    super.key,
    required this.icon,
    required this.label,
    required this.valueText,
    required this.onTap,
    this.dense = false,
  });

  final IconData icon;
  final String label;
  final String valueText;
  final VoidCallback onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: dense ? 8 : 12,
        ),
        decoration: BoxDecoration(
          color: palette.accent.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: dense ? 18 : 20, color: palette.primaryDark),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: dense ? 13 : 14,
                  color: palette.textSecondary,
                ),
              ),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                valueText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: dense ? 13 : 14,
                  fontWeight: FontWeight.w600,
                  color: palette.primaryDark,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more, size: 20, color: palette.textSecondary),
          ],
        ),
      ),
    );
  }
}
