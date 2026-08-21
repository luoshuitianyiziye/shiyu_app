import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/morandi_theme.dart';

/// 全局提示：经验类提示按来源去抖合并（避免连点弹窗轰炸），
/// 普通提示立即显示（不做「共 N 项」合并，避免文案无意义）。
///
/// 关键设计：累计时立即解析并保存根级 [ScaffoldMessenger]（生命周期稳定），
/// 而不是保存可能随列表刷新被卸载的叶子 BuildContext ——
/// 这样任务完成导致 tile 卸载后，XP 提示仍能在 2 秒窗口结束时正常显示。
///
/// 用法：在任意页面调用 [FeedbackDebouncer.xp] / [FeedbackDebouncer.toast]。
class FeedbackDebouncer {
  FeedbackDebouncer._();

  /// 经验提示合并窗口：2 秒内同一来源的事件合并为一条
  static const Duration kDebounceWindow = Duration(seconds: 2);

  static Timer? _timer;
  static ScaffoldMessengerState? _messenger;
  static ThemeData? _theme;
  static int _pendingCount = 0;
  static int _pendingXp = 0;
  static String _baseText = '';
  static String _group = 'global';

  /// 记录一条"经验 +N"事件；窗口内同来源合并为"完成 N 项 · 共 +XP"
  static void xp(
    BuildContext context,
    int xp, {
    String action = '任务完成',
    String group = 'global',
  }) {
    _accumulate(context, xp: xp, baseText: action, group: group);
  }

  /// 记录一条普通提示（无经验）：立即显示、不做合并。
  static void toast(
    BuildContext context,
    String text, {
    String group = 'global',
  }) {
    final messenger = _messengerOf(context);
    if (messenger == null) return;

    // 先结算窗口内待合并的经验提示（flush 不会清空已显示的 SnackBar）
    final hadPendingXp = _pendingCount > 0 && _pendingXp > 0;
    if (hadPendingXp) {
      _flush();
    }
    _show(messenger, context, text, xp: 0, clearExisting: !hadPendingXp);
  }

  static void _accumulate(
    BuildContext context, {
    required int xp,
    required String baseText,
    required String group,
  }) {
    final messenger = _messengerOf(context);
    if (messenger == null) return;

    // 不同来源的经验提示先立即结算，避免跨页面合并成一条奇怪文案
    if (_pendingCount > 0 && group != _group) {
      _flush();
    }
    _messenger = messenger;
    _theme = Theme.of(context);
    _group = group;
    _pendingCount += 1;
    _pendingXp += xp;
    _baseText = baseText;

    _timer?.cancel();
    _timer = Timer(kDebounceWindow, _flush);
  }

  static void _flush() {
    _timer = null;
    final messenger = _messenger;
    if (messenger == null) return;

    final count = _pendingCount;
    final xp = _pendingXp;
    _pendingCount = 0;
    _pendingXp = 0;
    _baseText = '';
    _messenger = null;

    final text = count <= 1
        ? (xp > 0 ? '$_baseText +$xp XP 🎉' : _baseText)
        : (xp > 0 ? '完成 $count 项 · 共 +$xp XP 🎉' : '$_baseText（共 $count 项）');
    _show(messenger, null, text, xp: xp);
  }

  /// 解析稳定 messenger：优先从当前 context 找；找不到时复用累计时保存的
  /// messenger（累计路径已存好，这里主要服务 flush 后无 context 的情况）。
  static ScaffoldMessengerState? _messengerOf(BuildContext context) {
    if (!context.mounted) return _messenger;
    return ScaffoldMessenger.maybeOf(context) ?? _messenger;
  }

  /// 莫兰迪主题化浮层提示：圆角、浅色卡片、不遮挡底部导航。
  /// [theme] 为空时使用累计时保存的主题（flush 路径）。
  /// [clearExisting] 为 true 时先清空已有 SnackBar（普通 toast 即时替换）；
  /// 为 false 时保留现有条（flush 刚显示的 XP 条不被清掉，新条排队）。
  static void _show(
    ScaffoldMessengerState messenger,
    BuildContext? ctx,
    String text, {
    required int xp,
    bool clearExisting = false,
  }) {
    final theme = ctx != null ? Theme.of(ctx) : _theme;
    final palette = theme?.extension<MorandiPalette>();
    final snack = SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: palette?.card ?? Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      duration: const Duration(milliseconds: 2200),
      content: Row(
        children: [
          if (xp > 0) ...[
            Icon(Icons.emoji_events, size: 18, color: palette?.primaryDark),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: palette?.textPrimary ?? Colors.black87,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
    if (clearExisting) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(snack);
    } else {
      messenger.showSnackBar(snack);
    }
  }

  /// 立即清空未合并的待显示提示（页面销毁等场景）
  static void clear() {
    _timer?.cancel();
    _timer = null;
    _pendingCount = 0;
    _pendingXp = 0;
    _baseText = '';
    _messenger = null;
    _group = 'global';
  }
}
