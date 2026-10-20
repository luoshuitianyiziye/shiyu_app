// 时屿 · AI 服务测试：JSON 解析/校验/提示词（不触网，注入假客户端）
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shiyu_app/core/ai/ai_client.dart';
import 'package:shiyu_app/core/ai/ai_config.dart';
import 'package:shiyu_app/features/ai/application/ai_providers.dart';
import 'package:shiyu_app/features/ai/application/ai_service.dart';

/// 假聊天实现：返回固定 JSON，记录入参
class _FakeChat implements AiChat {
  _FakeChat(this.response);

  final String response;
  AiConfig? lastConfig;
  String? lastSystem;
  String? lastUser;

  @override
  Future<String> chatJson({
    required AiConfig config,
    required String systemPrompt,
    required String userPrompt,
  }) async {
    lastConfig = config;
    lastSystem = systemPrompt;
    lastUser = userPrompt;
    return response;
  }
}

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
      final content = '{"tasks":['
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
      expect(
        result.drafts.firstWhere((d) => d.title == '象限越界').quadrant,
        2,
      );
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
      final tasks = [
        for (var i = 0; i < 25; i++) '{"title":"任务$i"}',
      ].join(',');
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
          aiConfigProvider.overrideWith(
            (ref) async => const AiConfig(
              enabled: true,
              baseUrl: 'https://api.deepseek.com',
              model: 'deepseek-chat',
              apiKey: 'sk-test',
            ),
          ),
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
      expect(fake.lastConfig?.apiKey, 'sk-test');
    });

    test('未配置时抛 notConfigured 异常', () async {
      final container = ProviderContainer(
        overrides: [
          aiConfigProvider.overrideWith(
            (ref) async => const AiConfig(
              enabled: false,
              baseUrl: '',
              model: '',
              apiKey: '',
            ),
          ),
          aiClientProvider.overrideWithValue(_FakeChat('{}')),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(aiServiceProvider).generateTasks('测试'),
        throwsA(
          isA<AiException>()
              .having((e) => e.kind, 'kind', AiErrorKind.notConfigured),
        ),
      );
    });

    test('输入超长时抛异常（不调用模型）', () async {
      final fake = _FakeChat('{}');
      final container = ProviderContainer(
        overrides: [
          aiConfigProvider.overrideWith(
            (ref) async => const AiConfig(
              enabled: true,
              baseUrl: 'https://api.deepseek.com',
              model: 'deepseek-chat',
              apiKey: 'sk-test',
            ),
          ),
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
}
