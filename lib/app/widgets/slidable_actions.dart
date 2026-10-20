import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../theme/morandi_theme.dart';

/// 统一的左滑操作面板：编辑 + 删除。
///
/// 44% 宽的窄操作条，贴在卡片右侧；按钮高度与卡片（正文框）完全一致
/// （卡片的下边距移到 Slidable 外层，见各调用处），圆角与全局 CardTheme
/// （radius 20）对齐，左右两半拼成一条圆角操作条，中间无凹口。
ActionPane buildEditDeletePane(
  BuildContext context, {
  required VoidCallback onEdit,
  required VoidCallback onDelete,
  double extentRatio = 0.44,
  double radius = 20,
}) {
  final palette = Theme.of(context).extension<MorandiPalette>()!;

  return ActionPane(
    motion: const DrawerMotion(),
    extentRatio: extentRatio,
    children: [
      SlidableAction(
        onPressed: (_) => onEdit(),
        backgroundColor: palette.primaryDark,
        foregroundColor: Colors.white,
        icon: Icons.edit_outlined,
        label: '编辑',
        borderRadius: BorderRadius.horizontal(left: Radius.circular(radius)),
        flex: 1,
      ),
      SlidableAction(
        onPressed: (_) => onDelete(),
        backgroundColor: palette.danger,
        foregroundColor: Colors.white,
        icon: Icons.delete_outline,
        label: '删除',
        borderRadius: BorderRadius.horizontal(right: Radius.circular(radius)),
        flex: 1,
      ),
    ],
  );
}

/// 统一的右滑完成手势（今日任务「右滑到底 = 完成」）。
///
/// 无按钮、无背景条：右滑滑过 [extentRatio]（默认 40%）松手 → 卡片自动
/// 滑出并收缩消失 → 触发 [onComplete]；未过阈值则弹回原位（不自动打开
/// 面板，通过 openThreshold/closeThreshold ≈ 1 实现）。滑动中背景透明。
///
/// 注意：实际完成阈值由 [extentRatio] 决定（flutter_slidable 只在
/// position > extentRatio 时才派发 dismiss 手势），[dismissThreshold]
/// 需小于 [extentRatio] 才能参与判定。
ActionPane buildCompletePane(
  BuildContext context, {
  required VoidCallback onComplete,
  double extentRatio = 0.4,
}) {
  return ActionPane(
    motion: const DrawerMotion(),
    extentRatio: extentRatio,
    // 永不自动「打开」面板：未过阈值一律弹回，只有超过 extentRatio
    // 才走 dismiss 手势完成
    openThreshold: 0.99,
    closeThreshold: 0.99,
    dismissible: DismissiblePane(
      onDismissed: onComplete,
      dismissThreshold: extentRatio - 0.1, // 必须小于 extentRatio 才生效
    ),
    children: [
      // 透明占位：DrawerMotion 要求子项带非零 flex，这里不需要可见内容
      Flexible(fit: FlexFit.tight, child: SizedBox.expand()),
    ],
  );
}
