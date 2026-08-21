import 'package:flutter/material.dart';

import '../../app/theme/morandi_theme.dart';

/// 统一的确认对话框（全 App 共用，替代 7 处重复 AlertDialog 实现）。
///
/// 返回 true = 用户确认；false / 取消 / 点外部关闭 = 未确认。
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String content,
  String confirmText = '确定',
  String cancelText = '取消',
  bool danger = false,
}) async {
  final palette = Theme.of(context).extension<MorandiPalette>();
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelText),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: danger && palette != null
              ? TextButton.styleFrom(foregroundColor: palette.danger)
              : null,
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return result ?? false;
}
