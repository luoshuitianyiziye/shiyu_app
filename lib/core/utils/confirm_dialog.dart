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

/// 统一的单行文字输入对话框（重命名分类 / 图片说明等）。
///
/// 返回用户输入（去首尾空白）；取消/点外部关闭返回 null。
/// 空字符串 ≠ null：表示用户点了确认但未输入内容，由调用方决定如何处理。
Future<String?> showInputDialog(
  BuildContext context, {
  required String title,
  String? initialValue,
  String hintText = '',
  int? maxLength,
  String confirmText = '保存',
}) async {
  final controller = TextEditingController(text: initialValue ?? '');
  try {
    return await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: maxLength,
          decoration: InputDecoration(hintText: hintText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  } finally {
    // 对话框关闭后释放临时 controller
    controller.dispose();
  }
}
