// 时屿 · AI 多配置与添加结果汇总测试（纯逻辑，不依赖插件）
import 'package:flutter_test/flutter_test.dart';

import 'package:shiyu_app/core/ai/ai_config.dart';
import 'package:shiyu_app/features/ai/data/added_summary.dart';
import 'package:shiyu_app/features/ai/data/task_draft.dart';

void main() {
  group('AiProfile', () {
    test('元信息 JSON 往返（API Key 不参与序列化）', () {
      const profile = AiProfile(
        id: 'p1',
        name: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-chat',
        apiKey: 'sk-1',
      );
      final meta = profile.toMetaJson();
      expect(meta.containsKey('apiKey'), isFalse);

      final restored = AiProfile.fromMetaJson(meta, apiKey: 'sk-2');
      expect(restored.id, 'p1');
      expect(restored.name, 'DeepSeek');
      expect(restored.baseUrl, 'https://api.deepseek.com');
      expect(restored.model, 'deepseek-chat');
      expect(restored.apiKey, 'sk-2');
    });

    test('copyWith 保留 id 与未修改字段', () {
      const profile = AiProfile(
        id: 'p1',
        name: 'A',
        baseUrl: 'https://a',
        model: 'm',
        apiKey: 'k',
      );
      final changed = profile.copyWith(name: 'B');
      expect(changed.id, 'p1');
      expect(changed.name, 'B');
      expect(changed.baseUrl, 'https://a');
    });
  });

  group('AiConfig', () {
    AiConfig configWith({bool enabled = true, String activeId = 'p2'}) {
      return AiConfig(
        enabled: enabled,
        profiles: const [
          AiProfile(
            id: 'p1',
            name: 'A',
            baseUrl: 'https://a',
            model: 'm1',
            apiKey: 'k1',
          ),
          AiProfile(
            id: 'p2',
            name: 'B',
            baseUrl: 'https://b',
            model: 'm2',
            apiKey: 'k2',
          ),
        ],
        activeId: activeId,
      );
    }

    test('active 按 activeId 选取，找不到时回退第一个', () {
      expect(configWith().active?.name, 'B');
      expect(configWith(activeId: 'missing').active?.name, 'A');
      expect(
        const AiConfig(enabled: true, profiles: [], activeId: '').active,
        isNull,
      );
    });

    test('isConfigured 需要启用 + 当前配置完整', () {
      expect(configWith().isConfigured, isTrue);
      final noKey = configWith().copyWith(
        profiles: const [
          AiProfile(
            id: 'p2',
            name: 'B',
            baseUrl: 'https://b',
            model: 'm2',
            apiKey: '',
          ),
        ],
      );
      expect(noKey.isConfigured, isFalse);
      expect(configWith(enabled: false).isConfigured, isFalse);
      expect(configWith(activeId: 'missing').isConfigured, isTrue);
    });

    test('copyWith 切换 activeId 不影响配置列表', () {
      final switched = configWith().copyWith(activeId: 'p1');
      expect(switched.activeId, 'p1');
      expect(switched.profiles.length, 2);
      expect(switched.active?.name, 'A');
    });
  });

  group('summarizeAddedTasks', () {
    test('按日期统计今天与其它日期', () {
      final drafts = [
        TaskDraft(title: '今天1', date: DateTime(2026, 10, 21)),
        TaskDraft(title: '今天2', date: DateTime(2026, 10, 21)),
        TaskDraft(title: '明天', date: DateTime(2026, 10, 22)),
        TaskDraft(title: '下周', date: DateTime(2026, 10, 27)),
      ];
      final text = summarizeAddedTasks(drafts, now: DateTime(2026, 10, 21));
      expect(text, '已添加 4 个任务（今天 2 个、10月22日 1 个、10月27日 1 个）');
    });

    test('全部是今天时只提示今天', () {
      final text = summarizeAddedTasks([
        TaskDraft(title: 'A', date: DateTime(2026, 10, 21)),
        TaskDraft(title: 'B', date: DateTime(2026, 10, 21)),
      ], now: DateTime(2026, 10, 21));
      expect(text, '已添加 2 个任务（今天 2 个）');
    });
  });
}
