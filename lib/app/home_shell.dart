import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../core/utils/confirm_dialog.dart';

/// 底部五 Tab 主壳：今日 / 专注 / 日历 / 笔记 / 我的
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// 仅 Android 需要「再按一次退出」确认：
  /// iOS 无系统返回键/退出概念，不拦截（否则弹窗后 SystemNavigator.pop 无效）。
  bool get _needsExitConfirm => defaultTargetPlatform == TargetPlatform.android;

  Future<bool> _confirmExit(BuildContext context) => showConfirmDialog(
        context,
        title: '退出时屿',
        content: '确定要退出应用吗？',
        confirmText: '退出',
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 拦截系统返回键：弹确认框，避免误触直接退出
      canPop: !_needsExitConfirm,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !_needsExitConfirm) return;
        final exit = await _confirmExit(context);
        if (exit && context.mounted) {
          // 确认退出：结束应用
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: navigationShell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: (index) => navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          ),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.today_outlined),
              selectedIcon: Icon(Icons.today),
              label: '今日',
            ),
            NavigationDestination(
              icon: Icon(Icons.timer_outlined),
              selectedIcon: Icon(Icons.timer),
              label: '专注',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month),
              label: '日历',
            ),
            NavigationDestination(
              icon: Icon(Icons.edit_note_outlined),
              selectedIcon: Icon(Icons.edit_note),
              label: '笔记',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: '我的',
            ),
          ],
        ),
      ),
    );
  }
}
