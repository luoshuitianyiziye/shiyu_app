import 'dart:convert';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/ai_client.dart';
import '../../../core/ai/ai_config.dart';
import '../../../core/db/database.dart';
import '../../../core/domain/stats.dart';
import '../data/task_draft.dart';
import 'ai_providers.dart';

/// AI 生成任务结果（含被丢弃的非法条目数）
class AiGenerateResult {
  const AiGenerateResult({required this.drafts, required this.ignored});

  final List<TaskDraft> drafts;

  /// 因格式非法被丢弃的条目数（0 = 全部合法）
  final int ignored;
}

/// 笔记摘要与标签
class NoteSummary {
  const NoteSummary({required this.summary, required this.tags});

  final String summary;
  final List<String> tags;
}

final aiServiceProvider = Provider<AiService>((ref) => AiService(ref));

/// AI 应用服务：构造提示词、调用模型、解析并校验结果。
///
/// 失败统一抛 [AiException]（message 可直接展示给用户）。
class AiService {
  AiService(this._ref);

  final Ref _ref;

  /// 单次输入最大字符数
  static const int maxInputLength = 2000;

  /// 单次生成最大任务条数
  static const int maxDrafts = 20;

  // ---------- 生成任务（自然语言 / 批量拆解 / 目标拆分） ----------

  Future<AiGenerateResult> generateTasks(String input) async {
    final text = _validateInput(input);
    return _generateFrom(text);
  }

  /// 从笔记正文提取任务（截取前 2000 字）
  Future<AiGenerateResult> generateTasksFromNote(String noteText) async {
    final text = noteText.trim();
    if (text.isEmpty) {
      throw const AiException('笔记是空的，先写点内容吧', kind: AiErrorKind.empty);
    }
    final truncated = text.length > maxInputLength
        ? text.substring(0, maxInputLength)
        : text;
    return _generateFrom('从下面这篇笔记中提取待办任务：\n$truncated');
  }

  Future<AiGenerateResult> _generateFrom(String userPrompt) async {
    final profile = await _requireProfile();
    final now = DateTime.now();
    final content = await _ref
        .read(aiClientProvider)
        .chatJson(
          profile: profile,
          systemPrompt: buildSystemPrompt(now),
          userPrompt: userPrompt,
        );
    return parseDrafts(content, now: now);
  }

  // ---------- 每日复盘建议（只发送聚合数字） ----------

  Future<String> reviewToday(StatsSnapshot stats) async {
    final profile = await _requireProfile();
    final rate = (stats.todayRate * 100).round();
    final content = await _ref
        .read(aiClientProvider)
        .chatJson(
          profile: profile,
          systemPrompt: '你是时屿 App 的 AI 小助手「小屿」，语气温柔简短，只输出 JSON。',
          userPrompt:
              '今日完成率 $rate%，完成 ${stats.todayDone}/${stats.todayTotal} 项任务，'
              '本周番茄 ${stats.weekPomodoros} 个，连续打卡 ${stats.streakDays} 天。'
              '请给用户一句 40 字以内的鼓励或建议（中文，不要罗列数字）。'
              '只输出 JSON：{"text":"..."}',
        );
    return _extractText(content);
  }

  // ---------- 笔记摘要与标签 ----------

  Future<NoteSummary> summarizeNote(String noteText) async {
    final text = noteText.trim();
    if (text.isEmpty) {
      throw const AiException('笔记是空的，先写点内容吧', kind: AiErrorKind.empty);
    }
    final truncated = text.length > maxInputLength
        ? text.substring(0, maxInputLength)
        : text;
    final profile = await _requireProfile();
    final content = await _ref
        .read(aiClientProvider)
        .chatJson(
          profile: profile,
          systemPrompt: '你是时屿 App 的笔记助手，只输出 JSON。',
          userPrompt:
              '请为下面这篇笔记生成摘要（80 字以内）和 3-5 个标签（每个标签 2-6 字）。\n'
              '只输出 JSON：{"summary":"...","tags":["..."]}\n\n笔记内容：\n$truncated',
        );
    return parseSummary(content);
  }

  // ---------- 任务优化建议（只发送任务标题/象限/时段） ----------

  Future<String> suggestTasks(List<TaskRow> tasks) async {
    if (tasks.isEmpty) {
      throw const AiException('今天还没有任务，先添加几个吧', kind: AiErrorKind.empty);
    }
    final profile = await _requireProfile();
    final brief = tasks
        .take(20)
        .map((t) {
          final time = t.startTime == null
              ? '无时段'
              : '${t.startTime!.hour}:${t.startTime!.minute.toString().padLeft(2, '0')}';
          return '- ${t.title}（象限${t.quadrant}，难度${t.difficulty}，$time，'
              '${t.isDone ? '已完成' : '未完成'}）';
        })
        .join('\n');
    final content = await _ref
        .read(aiClientProvider)
        .chatJson(
          profile: profile,
          systemPrompt: '你是时屿 App 的任务规划助手，只输出 JSON。',
          userPrompt:
              '以下是用户今天的一些任务：\n$brief\n\n'
              '请给出 2-3 条简短的任务优化建议（每条 30 字以内，如调整象限/拆分/安排时段），只建议不修改。'
              '只输出 JSON：{"text":"建议1\\n建议2"}',
        );
    return _extractText(content);
  }

  // ---------- 问答聊天（普通文本，非 JSON） ----------

  /// 与小屿聊天：普通文本回复，支持最近几轮对话历史
  Future<String> chat({
    required String message,
    List<Map<String, String>> history = const [],
  }) async {
    final text = message.trim();
    if (text.isEmpty) {
      throw const AiException('说点什么吧～', kind: AiErrorKind.empty);
    }
    final profile = await _requireProfile();
    final now = DateTime.now();
    final content = await _ref
        .read(aiClientProvider)
        .chatJson(
          profile: profile,
          systemPrompt: buildChatSystemPrompt(now),
          userPrompt: text,
          history: history,
          jsonMode: false,
        );
    return content.trim();
  }

  /// 聊天系统提示词（小屿人设）
  static String buildChatSystemPrompt(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    final date = '${now.year}-${two(now.month)}-${two(now.day)}';
    return '你是「时屿」App 里的 AI 伙伴「小屿」，一只有蓝色长发的鲸鱼女仆。\n'
        '性格温柔、活泼、偶尔卖萌。用户会和你聊天，请用中文简洁回答（一般 1~3 句，最多 120 字）。\n'
        '你可以陪用户聊天、给学习/工作建议；如果用户想建任务，可以提醒他用「让 AI 生成任务」。\n'
        '当前日期：$date。\n'
        '不要编造用户没提到的信息；不确定就说不确定。';
  }

  // ---------- 解析与校验 ----------

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

  /// 解析摘要 JSON
  static NoteSummary parseSummary(String content) {
    final map = _decodeJsonObject(content);
    final summary = (map['summary'] as String?)?.trim() ?? '';
    final tags = <String>[];
    final rawTags = map['tags'];
    if (rawTags is List) {
      for (final t in rawTags) {
        if (t is String && t.trim().isNotEmpty && tags.length < 6) {
          tags.add(t.trim());
        }
      }
    }
    if (summary.isEmpty) {
      throw const AiException('AI 没有返回摘要，请重试', kind: AiErrorKind.empty);
    }
    return NoteSummary(summary: summary, tags: tags);
  }

  /// 从 {"text": "..."} 中提取文案；非 JSON 时回退为纯文本
  static String _extractText(String content) {
    try {
      final map = _decodeJsonObject(content);
      final text = map['text'];
      if (text is String && text.trim().isNotEmpty) return text.trim();
    } catch (_) {
      // 非 JSON：回退为纯文本
    }
    return content.replaceAll('```json', '').replaceAll('```', '').trim();
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

  String _validateInput(String input) {
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
    return text;
  }

  Future<AiProfile> _requireProfile() async {
    final config = await _ref.read(aiConfigProvider.future);
    final profile = config.active;
    if (!config.enabled || profile == null) {
      throw const AiException(
        '请先在设置中启用 AI 并添加一个配置',
        kind: AiErrorKind.notConfigured,
      );
    }
    if (profile.apiKey.isEmpty) {
      throw const AiException(
        '当前 AI 配置缺少 API Key，请到设置里填写',
        kind: AiErrorKind.notConfigured,
      );
    }
    return profile;
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
3. date：用户说“今天/明天/后天/本周X/下周X”时按当前日期换算；没提日期用今天；要求多天计划时按天分配日期
4. startTime：只有用户明确说了时间才填 HH:mm，否则 null
5. repeatRule：none / daily / weekdays / weekly
6. 一段文字（会议纪要、待办清单）或一个目标（如“准备期末考试”）都可能拆出多条任务
7. 最多 20 条；不要编造用户没提到的任务；标题精炼（≤20 字）
8. 只输出 JSON，不要任何解释文字''';
  }
}
