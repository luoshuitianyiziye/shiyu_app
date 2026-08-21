import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 全局可覆写的状态：在 main() 中用 shared_preferences 初始化后注入。
/// 昵称（null = 未登录）
///
/// 未 override 时提供安全默认值（不抛错），避免 widget 测试/独立预览/
/// 未来新增入口在构建 ShiyuApp 时直接崩溃。
final nicknameNotifierProvider = Provider<ValueNotifier<String?>>(
  (_) => ValueNotifier<String?>(null),
);

/// 当前主题 id（如 mist_green）
final themeIdNotifierProvider = Provider<ValueNotifier<String>>(
  (_) => ValueNotifier<String>('mist_green'),
);
