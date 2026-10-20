// 时屿 · 日程笔记 —— 冒烟测试
import 'package:drift/drift.dart' hide Column;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
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

    await tester.pumpWidget(_buildApp(nickname: nickname, themeId: themeId));
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

  testWidgets('今日页正常显示已添加的任务', (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await db.addTask(
      TasksCompanion.insert(
        title: '可见性测试任务',
        date: today,
        quadrant: const Value(2),
      ),
    );

    final nickname = ValueNotifier<String?>('小屿');
    final themeId = ValueNotifier<String>('mist_green');

    await tester.pumpWidget(
      _buildApp(nickname: nickname, themeId: themeId, db: db),
    );
    await tester.pumpAndSettle();

    expect(find.text('可见性测试任务'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('新建笔记保存后出现在笔记列表', (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());

    final nickname = ValueNotifier<String?>('小屿');
    final themeId = ValueNotifier<String>('mist_green');

    await tester.pumpWidget(
      _buildApp(nickname: nickname, themeId: themeId, db: db),
    );
    await tester.pumpAndSettle();

    // 进入笔记页
    await tester.tap(find.text('笔记'));
    await tester.pumpAndSettle();

    // 打开新建笔记编辑器（取当前可见的 FAB）
    await tester.tap(find.byType(FloatingActionButton).hitTestable());
    await tester.pumpAndSettle();

    // 输入标题并「完成」（保存 + 进入浏览模式）
    await tester.enterText(find.byType(TextField).first, '自动化测试笔记');
    await tester.pump();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    // 保存后停在浏览态（仍在编辑页，无「完成」按钮）
    expect(find.text('完成'), findsNothing);
    // 数据层已落库
    final notes = await (db.select(db.notes)).get();
    expect(notes.where((n) => n.title == '自动化测试笔记'), hasLength(1));

    // 返回列表应能看到（模拟系统返回键）
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('自动化测试笔记'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('笔记正文可以应用标题格式并保存', (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());

    final nickname = ValueNotifier<String?>('小屿');
    final themeId = ValueNotifier<String>('mist_green');

    await tester.pumpWidget(
      _buildApp(nickname: nickname, themeId: themeId, db: db),
    );
    await tester.pumpAndSettle();

    // 进入笔记页 → 新建笔记
    await tester.tap(find.text('笔记'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton).hitTestable());
    await tester.pumpAndSettle();

    // 填写笔记标题
    await tester.enterText(find.byType(TextField).first, '标题格式测试');
    await tester.pump();
    expect(find.text('完成'), findsOneWidget, reason: '编辑态应有完成按钮');

    // 空行点「标题」按钮（正文 → 标题1），验证点击后仍处于编辑态
    await tester.tap(find.byIcon(Icons.title));
    await tester.pumpAndSettle();
    expect(find.text('完成'), findsOneWidget, reason: '点标题后仍应处于编辑态');

    // 「完成」保存并检查落库正文带 header 属性
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    final notes = await (db.select(db.notes)).get();
    final body = notes.firstWhere((n) => n.title == '标题格式测试').body;
    expect(body, contains('"header":1'));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('浏览态点击标题栏可以进入编辑并修改标题', (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await db.addNote(NotesCompanion.insert(title: '原标题'));

    final nickname = ValueNotifier<String?>('小屿');
    final themeId = ValueNotifier<String>('mist_green');

    await tester.pumpWidget(
      _buildApp(nickname: nickname, themeId: themeId, db: db),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('笔记'));
    await tester.pumpAndSettle();
    // 打开已有笔记（浏览态）
    await tester.tap(find.text('原标题'));
    await tester.pumpAndSettle();

    // 浏览态点击标题栏 → 进入编辑并聚焦标题输入框
    await tester.tap(find.text('原标题'));
    await tester.pumpAndSettle();
    expect(find.text('完成'), findsOneWidget, reason: '点标题后应进入编辑态');

    // 修改标题并「完成」（保存 + 回到浏览态）
    await tester.enterText(find.byType(TextField).first, '新标题');
    await tester.pump();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    final notes = await (db.select(db.notes)).get();
    expect(notes.first.title, '新标题');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('「完成」保存后进入浏览态，再次完成不会重复创建', (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());

    final nickname = ValueNotifier<String?>('小屿');
    final themeId = ValueNotifier<String>('mist_green');

    await tester.pumpWidget(
      _buildApp(nickname: nickname, themeId: themeId, db: db),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('笔记'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton).hitTestable());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '只创建一次');
    await tester.pump();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    var notes = await (db.select(db.notes)).get();
    expect(notes.where((n) => n.title == '只创建一次'), hasLength(1));

    // 再次进入编辑再「完成」：应走更新而不是新建
    await tester.tap(find.text('只创建一次'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    notes = await (db.select(db.notes)).get();
    expect(notes.where((n) => n.title == '只创建一次'), hasLength(1));

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
