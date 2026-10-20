import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AI 服务配置（BYOK：用户填写自己的 API Key）。
///
/// - API Key 存 Android Keystore 加密存储（flutter_secure_storage）；
/// - 其余配置（开关/地址/模型）存 SharedPreferences。
class AiConfig {
  const AiConfig({
    required this.enabled,
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });

  final bool enabled;

  /// OpenAI 兼容接口地址（如 https://api.deepseek.com）
  final String baseUrl;

  /// 模型名（如 deepseek-chat）
  final String model;

  /// 用户 API Key（空 = 未配置）
  final String apiKey;

  bool get isConfigured =>
      enabled && apiKey.isNotEmpty && baseUrl.isNotEmpty && model.isNotEmpty;

  AiConfig copyWith({
    bool? enabled,
    String? baseUrl,
    String? model,
    String? apiKey,
  }) {
    return AiConfig(
      enabled: enabled ?? this.enabled,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      apiKey: apiKey ?? this.apiKey,
    );
  }

  static const defaultBaseUrl = 'https://api.deepseek.com';
  static const defaultModel = 'deepseek-chat';

  static const _kEnabled = 'ai_enabled';
  static const _kBaseUrl = 'ai_base_url';
  static const _kModel = 'ai_model';
  static const _kApiKey = 'ai_api_key';

  static final _secure = FlutterSecureStorage();

  /// 从本地读取配置（未配置时返回默认值 + 空 Key）
  static Future<AiConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    String apiKey = '';
    try {
      apiKey = await _secure.read(key: _kApiKey) ?? '';
    } catch (_) {
      // 加密存储不可用（如模拟器无 Keystore）：视为未配置
    }
    return AiConfig(
      enabled: prefs.getBool(_kEnabled) ?? false,
      baseUrl: prefs.getString(_kBaseUrl) ?? defaultBaseUrl,
      model: prefs.getString(_kModel) ?? defaultModel,
      apiKey: apiKey,
    );
  }

  /// 保存配置（Key 写入加密存储）
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, enabled);
    await prefs.setString(_kBaseUrl, baseUrl);
    await prefs.setString(_kModel, model);
    try {
      if (apiKey.isEmpty) {
        await _secure.delete(key: _kApiKey);
      } else {
        await _secure.write(key: _kApiKey, value: apiKey);
      }
    } catch (_) {
      // 加密存储不可用：忽略（Key 不落盘，视为未配置）
    }
  }
}
