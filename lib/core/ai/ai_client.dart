import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'ai_config.dart';

/// AI 请求失败原因（用于 UI 提示与测试断言）
enum AiErrorKind {
  notConfigured,
  network,
  auth,
  rateLimit,
  server,
  parse,
  empty,
  unknown,
}

/// AI 请求异常（message 为用户可读文案）
class AiException implements Exception {
  const AiException(this.message, {this.kind = AiErrorKind.unknown});

  final String message;
  final AiErrorKind kind;

  @override
  String toString() => message;
}

/// 聊天补全接口（抽象，便于测试注入假实现）
abstract class AiChat {
  Future<String> chatJson({
    required AiConfig config,
    required String systemPrompt,
    required String userPrompt,
  });
}

/// OpenAI 兼容 Chat Completions 客户端（DeepSeek / OpenAI / 兼容服务均可）
class AiClient implements AiChat {
  AiClient({
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
  }) : _http = httpClient ?? http.Client();

  final http.Client _http;
  final Duration timeout;

  @override
  Future<String> chatJson({
    required AiConfig config,
    required String systemPrompt,
    required String userPrompt,
  }) async {
    final uri = Uri.parse('${_normalizeBase(config.baseUrl)}/chat/completions');
    final body = jsonEncode({
      'model': config.model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
      'temperature': 0.2,
      'max_tokens': 1200,
      'response_format': {'type': 'json_object'},
    });

    try {
      final resp = await _http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${config.apiKey}',
            },
            body: body,
          )
          .timeout(timeout);

      if (resp.statusCode == 401 || resp.statusCode == 403) {
        throw const AiException(
          'API Key 无效或没有权限，请检查设置',
          kind: AiErrorKind.auth,
        );
      }
      if (resp.statusCode == 429) {
        throw const AiException(
          '请求太频繁或额度不足，请稍后再试',
          kind: AiErrorKind.rateLimit,
        );
      }
      if (resp.statusCode >= 500) {
        throw AiException(
          'AI 服务暂时不可用（${resp.statusCode}），请稍后重试',
          kind: AiErrorKind.server,
        );
      }
      if (resp.statusCode != 200) {
        throw AiException(
          '请求失败（${resp.statusCode}），请检查接口地址与模型名',
          kind: AiErrorKind.server,
        );
      }

      final decoded = jsonDecode(resp.body);
      final choices = decoded is Map ? decoded['choices'] : null;
      final message = (choices is List && choices.isNotEmpty)
          ? (choices.first is Map ? (choices.first as Map)['message'] : null)
          : null;
      final content = (message is Map) ? message['content'] : null;
      if (content is! String || content.trim().isEmpty) {
        throw const AiException('AI 没有返回内容，请重试', kind: AiErrorKind.empty);
      }
      return content;
    } on AiException {
      rethrow;
    } on TimeoutException {
      throw const AiException('请求超时，请检查网络后重试', kind: AiErrorKind.network);
    } on SocketException {
      throw const AiException('网络不可用，请检查网络连接', kind: AiErrorKind.network);
    } on FormatException {
      throw const AiException('AI 返回格式异常，请重试', kind: AiErrorKind.parse);
    } on http.ClientException {
      throw const AiException('网络请求失败，请检查网络', kind: AiErrorKind.network);
    } catch (e) {
      throw AiException('请求失败：$e', kind: AiErrorKind.unknown);
    }
  }

  static String _normalizeBase(String base) {
    var b = base.trim();
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    return b;
  }
}
