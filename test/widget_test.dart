// 时屿 · 日程笔记 —— 冒烟测试
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shiyu_app/app/app.dart';
import 'package:shiyu_app/app/providers.dart';
import 'package:shiyu_app/core/db/database.dart';
import 'package:shiyu_app/core/db/db_providers.dart';

void main() {
  testWidgets('未设置昵称时显示登录页', (WidgetTester tester) async {
    final nickname = ValueNotifier<String?>(null);
    final themeId = ValueNotifier<String>('mist_green');

    await tester.pumpWidget(
      _buildApp(nickname: nickname, themeId: themeId),
    );
    await tester.pumpAndSettle();

    expect(find.text('时屿'), findsWidgets);
    expect(find.text('开始我的时屿'), findsOneWidget);
  });

  testWidgets('已有昵称时进入主壳', (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());

    final nickname = ValueNotifier<String?>('小屿');
    final themeId = ValueNotifier<String>('mist_green');

    await tester.pumpWidget(
      _buildApp(nickname: nickname, themeId: themeId, db: db),
    );
    await tester.pumpAndSettle();

    // 主壳底部导航五个 Tab
    expect(find.text('今日'), findsOneWidget);
    expect(find.text('专注'), findsOneWidget);
    expect(find.text('日历'), findsOneWidget);
    expect(find.text('笔记'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);

    // 清理：卸载组件，让 drift 流清理定时器在 fake_async 中跑完
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

Widget _buildApp({
  required ValueNotifier<String?> nickname,
  required ValueNotifier<String> themeId,
  AppDatabase? db,
}) {
  return ProviderScope(
    overrides: [
      nicknameNotifierProvider.overrideWithValue(nickname),
      themeIdNotifierProvider.overrideWithValue(themeId),
      // 测试用内存数据库，避免插件依赖
      if (db != null) databaseProvider.overrideWithValue(db),
    ],
    child: const ShiyuApp(),
  );
}
