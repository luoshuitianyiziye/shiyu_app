import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers.dart';
import 'router.dart';
import 'theme/morandi_theme.dart';

/// 「时屿 · 日程笔记」应用根组件
class ShiyuApp extends ConsumerStatefulWidget {
  const ShiyuApp({super.key});

  @override
  ConsumerState<ShiyuApp> createState() => _ShiyuAppState();
}

class _ShiyuAppState extends ConsumerState<ShiyuApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    // 路由只创建一次：登录后靠 refreshListenable(ValueNotifier) 自动重定向，
    // 主题切换时重建 MaterialApp 但复用同一 router，避免导航状态被重置。
    _router = AppRouter.create(ref.read(nicknameNotifierProvider));
  }

  @override
  Widget build(BuildContext context) {
    // 真正监听 ValueNotifier 的 value 变化（ref.watch 只监听 provider 本身）
    final themeNotifier = ref.watch(themeIdNotifierProvider);

    return ValueListenableBuilder<String>(
      valueListenable: themeNotifier,
      builder: (context, themeId, _) {
        final theme = morandiThemes.firstWhere(
          (t) => t.id == themeId,
          orElse: () => morandiThemes.first,
        );

        return MaterialApp.router(
          title: '时屿',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(theme),
          routerConfig: _router,
          // 状态栏/导航栏样式随主题（透明状态栏 + 图标深浅自适应）
          builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: theme.palette.overlayStyle,
            child: child ?? const SizedBox.shrink(),
          ),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            // flutter_quill 工具栏（撤销/重做等）需要，缺失会导致编辑器页崩溃
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
          locale: const Locale('zh', 'CN'),
        );
      },
    );
  }
}
