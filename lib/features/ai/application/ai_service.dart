import 'dart:convert';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/ai_client.dart';
import '../data/task_draft.dart';
import 'ai_providers.dart';

/// AI 生成结果（含被丢弃的非法条目数）
class AiGenerateResult {
  const AiGenerateResult({required this.drafts, required this.ignored});

  final List<TaskDraft> drafts;

  /// 因格式非法被丢弃的条目数（0 = 全部合法）
  final int ignored;
}

final aiServiceProvider = Provider<AiService>((ref) => AiService(ref));

/// AI 应用服务：构造提示词、调用模型、解析并校验任务草案。
///
/// 失败统一抛 [AiException]（message 可直接展示给用户）。
class AiService {
  AiService(this._ref);

  final Ref _ref;

  /// 单次输入最大字符数
  static const int maxInputLength = 2000;

  /// 单次生成最大任务条数
  static const int maxDrafts = 20;

  Future<AiGenerateResult> generateTasks(String input) async {
    final text = input.trim();
    if (text.isEmpty) {
      throw const AiException('先说说你想做什么吧～', kind: AiErrorKind.empty);
    }
    if (text.length > maxInputLength) {
      throw const AiException(
        '输入太长啦，请分几次发送（最多 $maxInputLength 字）',
        kind: AiErrorKind.parse,
      );
    }
    final config = await _ref.read(aiConfigProvider.future);
    if (!config.isConfigured) {
      throw const AiException(
        '请先在设置中启用 AI 并填写 API Key',
        kind: AiErrorKind.notConfigured,
      );
    }
    final now = DateTime.now();
    final content = await _ref
        .read(aiClientProvider)
        .chatJson(
          config: config,
          systemPrompt: buildSystemPrompt(now),
          userPrompt: text,
        );
    return parseDrafts(content, now: now);
  }

  /// 解析模型输出的 JSON → 任务草案（严格校验，非法条目丢弃并计数）
  static AiGenerateResult parseDrafts(String content, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final map = _decodeJsonObject(content);
    final rawTasks = map['tasks'];
    final drafts = <TaskDraft>[];
    var ignored = 0;
    if (rawTasks is List) {
      for (final item in rawTasks) {
        final draft = _draftFrom(item, current);
        if (draft == null || drafts.length >= maxDrafts) {
          ignored++;
          continue;
        }
        drafts.add(draft);
      }
    }
    return AiGenerateResult(drafts: drafts, ignored: ignored);
  }

  static Map<String, dynamic> _decodeJsonObject(String content) {
    var text = content.trim();
    // 去掉 ```json ... ``` 代码块包裹
    if (text.startsWith('```')) {
      final firstNewline = text.indexOf('\n');
      if (firstNewline >= 0) text = text.substring(firstNewline + 1);
      if (text.endsWith('```')) {
        text = text.substring(0, text.length - 3);
      }
      text = text.trim();
    }
    // 容错：取第一个 { 到最后一个 }
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const AiException('AI 返回格式异常，请重试', kind: AiErrorKind.parse);
    }
    final decoded = jsonDecode(text.substring(start, end + 1));
    if (decoded is! Map<String, dynamic>) {
      throw const AiException('AI 返回格式异常，请重试', kind: AiErrorKind.parse);
    }
    return decoded;
  }

  static TaskDraft? _draftFrom(dynamic item, DateTime now) {
    if (item is! Map) return null;
    final rawTitle = item['title'];
    if (rawTitle is! String) return null;
    final title = rawTitle.trim();
    if (title.isEmpty) return null;

    final quadrant = _intInRange(item['quadrant'], 1, 4, 2);
    final difficulty = _intInRange(item['difficulty'], 1, 3, 2);
    final repeatRule = switch (item['repeatRule']) {
      'daily' || 'weekdays' || 'weekly' => item['repeatRule'] as String,
      _ => 'none',
    };

    DateTime? date;
    final rawDate = item['date'];
    if (rawDate is String) {
      final parsed = DateTime.tryParse(rawDate);
      if (parsed != null) {
        final day = DateTime(parsed.year, parsed.month, parsed.day);
        final today = DateTime(now.year, now.month, now.day);
        // 合理范围：不早于今天、不晚于 2 年后
        if (!day.isBefore(today) &&
            day.isBefore(DateTime(today.year + 2, today.month, today.day))) {
          date = day;
        }
      }
    }

    TimeOfDay? startTime;
    final rawTime = item['startTime'];
    if (rawTime is String && rawTime.contains(':')) {
      final parts = rawTime.split(':');
      final h = int.tryParse(parts[0]);
      final m = parts.length > 1 ? int.tryParse(parts[1]) : null;
      if (h != null && m != null && h >= 0 && h < 24 && m >= 0 && m < 60) {
        startTime = TimeOfDay(hour: h, minute: m);
      }
    }

    return TaskDraft(
      title: title.length > 40 ? title.substring(0, 40) : title,
      quadrant: quadrant,
      difficulty: difficulty,
      date: date,
      startTime: startTime,
      repeatRule: repeatRule,
    );
  }

  static int _intInRange(dynamic v, int min, int max, int fallback) {
    final n = v is int ? v : int.tryParse('$v');
    if (n == null || n < min || n > max) return fallback;
    return n;
  }

  /// 系统提示词（包含当前日期，帮助模型换算「今天/明天/下周三」）
  static String buildSystemPrompt(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    final date = '${now.year}-${two(now.month)}-${two(now.day)}';
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return '''你是「时屿」App 的 AI 任务助手。用户会给你一句话或一段文字，请从中提取待办事项并输出 JSON。
当前日期：$date（周${weekdays[now.weekday - 1]}）。

输出格式：{"tasks":[{"title":"任务标题","quadrant":1,"difficulty":2,"date":"yyyy-MM-dd","startTime":"HH:mm 或 null","repeatRule":"none"}]}

规则：
1. quadrant：1=重要紧急 2=重要不紧急 3=紧急不重要 4=不重要不紧急，默认 2
2. difficulty：1=简单 2=普通 3=困难，默认 2
3. date：用户说“今天/明天/后天/本周X/下周X”时按当前日期换算；没提日期用今天
4. startTime：只有用户明确说了时间才填 HH:mm，否则 null
5. repeatRule：none / daily / weekdays / weekly
6. 一段文字（会议纪要、待办清单）或一个目标（如“准备期末考试”）都可能拆出多条任务
7. 最多 20 条；不要编造用户没提到的任务；标题精炼（≤20 字）
8. 只输出 JSON，不要任何解释文字''';
  }
}
