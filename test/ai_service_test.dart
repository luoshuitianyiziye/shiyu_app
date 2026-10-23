// 时屿 · AI 服务测试：JSON 解析/校验/提示词（不触网，注入假客户端）
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shiyu_app/core/ai/ai_client.dart';
import 'package:shiyu_app/core/ai/ai_config.dart';
import 'package:shiyu_app/core/db/database.dart';
import 'package:shiyu_app/core/domain/stats.dart';
import 'package:shiyu_app/features/ai/application/ai_providers.dart';
import 'package:shiyu_app/features/ai/application/ai_service.dart';

/// 假聊天实现：返回固定 JSON，记录入参
class _FakeChat implements AiChat {
  _FakeChat(this.response);

  final String response;
  AiProfile? lastProfile;
  String? lastSystem;
  String? lastUser;
  List<Map<String, String>>? lastHistory;
  bool? lastJsonMode;

  @override
  Future<String> chatJson({
    required AiProfile profile,
    required String systemPrompt,
    required String userPrompt,
    List<Map<String, String>>? history,
    bool jsonMode = true,
  }) async {
    lastProfile = profile;
    lastSystem = systemPrompt;
    lastUser = userPrompt;
    lastHistory = history;
    lastJsonMode = jsonMode;
    return response;
  }
}

AiConfig _configured() => const AiConfig(
  enabled: true,
  profiles: [
    AiProfile(
      id: 'p1',
      name: '测试配置',
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-chat',
      apiKey: 'sk-test',
    ),
  ],
  activeId: 'p1',
);

AiConfig _unconfigured() =>
    const AiConfig(enabled: false, profiles: [], activeId: '');

void main() {
  group('parseDrafts', () {
    test('解析合法 JSON（含代码块包裹）', () {
      const content =
          '```json\n{"tasks":[{"title":"写周报","quadrant":1,"difficulty":2,"date":"2026-10-21","startTime":"15:00","repeatRule":"none"}]}\n```';
      final result = AiService.parseDrafts(
        content,
        now: DateTime(2026, 10, 20),
      );
      expect(result.drafts, hasLength(1));
      final d = result.drafts.first;
      expect(d.title, '写周报');
      expect(d.quadrant, 1);
      expect(d.difficulty, 2);
      expect(d.date, DateTime(2026, 10, 21));
      expect(d.startTime, isNotNull);
      expect(d.startTime!.hour, 15);
      expect(d.startTime!.minute, 0);
    });

    test('缺标题的条目被丢弃，其余非法字段回退默认值', () {
      final content =
          '{"tasks":['
          '{"title":"合法任务"},'
          '{"quadrant":2},'
          '{"title":"象限越界","quadrant":9},'
          '{"title":"日期越界","date":"2020-01-01"},'
          '{"title":"时间非法","startTime":"25:99"},'
          '{"title":"重复非法","repeatRule":"monthly"}'
          ']}';
      final result = AiService.parseDrafts(
        content,
        now: DateTime(2026, 10, 20),
      );
      expect(result.drafts, hasLength(5));
      expect(result.ignored, 1);
      expect(result.drafts.firstWhere((d) => d.title == '象限越界').quadrant, 2);
      expect(result.drafts.firstWhere((d) => d.title == '日期越界').date, isNull);
      expect(
        result.drafts.firstWhere((d) => d.title == '时间非法').startTime,
        isNull,
      );
      expect(
        result.drafts.firstWhere((d) => d.title == '重复非法').repeatRule,
        'none',
      );
    });

    test('超过 20 条时截断并计数', () {
      final tasks = [for (var i = 0; i < 25; i++) '{"title":"任务$i"}'].join(',');
      final result = AiService.parseDrafts(
        '{"tasks":[$tasks]}',
        now: DateTime(2026, 10, 20),
      );
      expect(result.drafts, hasLength(20));
      expect(result.ignored, 5);
    });

    test('标题超长自动截断到 40 字', () {
      final longTitle = '长' * 60;
      final result = AiService.parseDrafts(
        '{"tasks":[{"title":"$longTitle"}]}',
        now: DateTime(2026, 10, 20),
      );
      expect(result.drafts.first.title.length, 40);
    });

    test('非法 JSON 抛 parse 异常', () {
      expect(
        () => AiService.parseDrafts('not-json'),
        throwsA(
          isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.parse),
        ),
      );
    });
  });

  group('generateTasks', () {
    test('调用假客户端并传入配置/提示词/用户输入', () async {
      final fake = _FakeChat(
        '{"tasks":[{"title":"测试任务","quadrant":3,"difficulty":1}]}',
      );
      final container = ProviderContainer(
        overrides: [
          aiConfigProvider.overrideWith((ref) async => _configured()),
          aiClientProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      final result = await container
          .read(aiServiceProvider)
          .generateTasks('明天下午三点写周报');
      expect(result.drafts, hasLength(1));
      expect(result.drafts.first.title, '测试任务');
      expect(result.drafts.first.quadrant, 3);
      expect(fake.lastUser, '明天下午三点写周报');
      expect(fake.lastSystem, contains('当前日期'));
      expect(fake.lastProfile?.apiKey, 'sk-test');
    });

    test('未配置时抛 notConfigured 异常', () async {
      final container = ProviderContainer(
        overrides: [
          aiConfigProvider.overrideWith((ref) async => _unconfigured()),
          aiClientProvider.overrideWithValue(_FakeChat('{}')),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(aiServiceProvider).generateTasks('测试'),
        throwsA(
          isA<AiException>().having(
            (e) => e.kind,
            'kind',
            AiErrorKind.notConfigured,
          ),
        ),
      );
    });

    test('输入超长时抛异常（不调用模型）', () async {
      final fake = _FakeChat('{}');
      final container = ProviderContainer(
        overrides: [
          aiConfigProvider.overrideWith((ref) async => _configured()),
          aiClientProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(aiServiceProvider)
            .generateTasks('x' * (AiService.maxInputLength + 1)),
        throwsA(isA<AiException>()),
      );
      expect(fake.lastUser, isNull); // 未发起请求
    });
  });

  group('复盘建议 / 摘要 / 任务建议 / 笔记转任务', () {
    ProviderContainer containerWith(AiChat fake) => ProviderContainer(
      overrides: [
        aiConfigProvider.overrideWith((ref) async => _configured()),
        aiClientProvider.overrideWithValue(fake),
      ],
    );

    test('reviewToday 提取 text 字段（只发送聚合数字）', () async {
      final fake = _FakeChat('{"text":"今天很棒，继续保持～"}');
      final container = containerWith(fake);
      addTearDown(container.dispose);

      final text = await container
          .read(aiServiceProvider)
          .reviewToday(
            const StatsSnapshot(
              totalPomodoros: 3,
              totalMinutes: 75,
              weekPomodoros: 3,
              weekMinutes: 75,
              last7Days: [0, 0, 0, 0, 0, 0, 3],
              totalTasksDone: 5,
              streakDays: 4,
              rankIndex: 2,
              todayTotal: 4,
              todayDone: 3,
            ),
          );
      expect(text, '今天很棒，继续保持～');
      expect(fake.lastUser, contains('75%')); // 完成率聚合
      expect(fake.lastUser, contains('连续打卡'));
    });

    test('summarizeNote 解析摘要与标签', () async {
      final fake = _FakeChat(
        '{"summary":"这是一篇关于考试复习的笔记","tags":["学习","考试","复习"]}',
      );
      final container = containerWith(fake);
      addTearDown(container.dispose);

      final summary = await container
          .read(aiServiceProvider)
          .summarizeNote('期末考试复习计划：每天两小时……');
      expect(summary.summary, '这是一篇关于考试复习的笔记');
      expect(summary.tags, ['学习', '考试', '复习']);
      expect(fake.lastUser, contains('期末考试复习计划'));
    });

    test('suggestTasks 提取建议文本', () async {
      final fake = _FakeChat('{"text":"把写周报移到上午\\n给复习任务加时段"}');
      final container = containerWith(fake);
      addTearDown(container.dispose);

      final text = await container.read(aiServiceProvider).suggestTasks([
        TaskRow(
          id: 1,
          title: '写周报',
          quadrant: 1,
          date: DateTime(2026, 10, 20),
          startTime: null,
          endTime: null,
          difficulty: 2,
          repeatRule: 'none',
          lastRepeatedDate: null,
          isDone: false,
          doneAt: null,
          xpAwarded: 0,
          pomodoroCount: 0,
          sort: 0,
          deleted: false,
          updatedAt: DateTime(2026, 10, 20),
        ),
      ]);
      expect(text, contains('把写周报移到上午'));
      expect(fake.lastUser, contains('写周报'));
    });

    test('generateTasksFromNote 截断超长笔记并包含笔记内容', () async {
      final fake = _FakeChat('{"tasks":[{"title":"复习笔记"}]}');
      final container = containerWith(fake);
      addTearDown(container.dispose);

      final longNote = '笔记内容' * 800; // 超过 2000 字
      final result = await container
          .read(aiServiceProvider)
          .generateTasksFromNote(longNote);
      expect(result.drafts, hasLength(1));
      expect(fake.lastUser, contains('从下面这篇笔记中提取待办任务'));
      expect(fake.lastUser!.length, lessThan(3000)); // 已截断
    });
  });

  group('问答聊天', () {
    ProviderContainer makeContainer(AiChat fake) => ProviderContainer(
      overrides: [
        aiConfigProvider.overrideWith((ref) async => _configured()),
        aiClientProvider.overrideWithValue(fake),
      ],
    );

    test('chat 发送历史并返回文本（非 JSON 模式）', () async {
      final fake = _FakeChat('今天也辛苦啦～');
      final container = makeContainer(fake);
      addTearDown(container.dispose);

      final reply = await container
          .read(aiServiceProvider)
          .chat(
            message: '陪我聊聊',
            history: [
              {'role': 'user', 'content': '你好'},
              {'role': 'assistant', 'content': '你好呀～'},
            ],
          );
      expect(reply, '今天也辛苦啦～');
      expect(fake.lastUser, '陪我聊聊');
      expect(fake.lastHistory, hasLength(2));
      expect(fake.lastJsonMode, isFalse);
      expect(fake.lastSystem, contains('小屿'));
    });

    test('空消息抛异常（不发请求）', () async {
      final fake = _FakeChat('x');
      final container = makeContainer(fake);
      addTearDown(container.dispose);

      await expectLater(
        container.read(aiServiceProvider).chat(message: '   '),
        throwsA(isA<AiException>()),
      );
      expect(fake.lastUser, isNull);
    });
  });
}
