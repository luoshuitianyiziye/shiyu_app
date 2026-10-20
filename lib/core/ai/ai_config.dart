import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 单个 AI 服务配置（一个服务商 / Key 组合），支持配置多套并一键切换。
class AiProfile {
  const AiProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });

  final String id;

  /// 显示名称（如「DeepSeek」「OpenAI」）
  final String name;

  /// OpenAI 兼容接口地址（如 https://api.deepseek.com）
  final String baseUrl;

  /// 模型名（如 deepseek-chat）
  final String model;

  /// 用户 API Key（空 = 未配置）
  final String apiKey;

  AiProfile copyWith({
    String? name,
    String? baseUrl,
    String? model,
    String? apiKey,
  }) {
    return AiProfile(
      id: id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      apiKey: apiKey ?? this.apiKey,
    );
  }

  /// 元信息（不含 Key，Key 单独存加密存储）
  Map<String, dynamic> toMetaJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'model': model,
  };

  factory AiProfile.fromMetaJson(
    Map<String, dynamic> json, {
    String apiKey = '',
  }) {
    return AiProfile(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '未命名配置',
      baseUrl: (json['baseUrl'] as String?) ?? AiConfig.defaultBaseUrl,
      model: (json['model'] as String?) ?? AiConfig.defaultModel,
      apiKey: apiKey,
    );
  }
}

/// AI 配置集合：支持多套配置（服务商/Key），可一键切换当前使用的配置。
class AiConfig {
  const AiConfig({
    required this.enabled,
    required this.profiles,
    required this.activeId,
  });

  final bool enabled;
  final List<AiProfile> profiles;

  /// 当前使用的配置 id
  final String activeId;

  /// 当前配置（列表为空返回 null）
  AiProfile? get active {
    if (profiles.isEmpty) return null;
    for (final p in profiles) {
      if (p.id == activeId) return p;
    }
    return profiles.first;
  }

  bool get isConfigured {
    final a = active;
    return enabled &&
        a != null &&
        a.apiKey.isNotEmpty &&
        a.baseUrl.isNotEmpty &&
        a.model.isNotEmpty;
  }

  AiConfig copyWith({
    bool? enabled,
    List<AiProfile>? profiles,
    String? activeId,
  }) {
    return AiConfig(
      enabled: enabled ?? this.enabled,
      profiles: profiles ?? this.profiles,
      activeId: activeId ?? this.activeId,
    );
  }

  static const defaultBaseUrl = 'https://api.deepseek.com';
  static const defaultModel = 'deepseek-chat';

  static const _kEnabled = 'ai_enabled';
  static const _kProfiles = 'ai_profiles';
  static const _kActiveId = 'ai_active_id';

  // 旧版单配置键（用于自动迁移）
  static const _kLegacyBaseUrl = 'ai_base_url';
  static const _kLegacyModel = 'ai_model';
  static const _kLegacyApiKey = 'ai_api_key';

  static const _kApiKeyPrefix = 'ai_api_key_';

  static final _secure = FlutterSecureStorage();

  static String keyFor(String profileId) => '$_kApiKeyPrefix$profileId';

  /// 从本地读取配置（含旧版单配置自动迁移）
  static Future<AiConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kEnabled) ?? false;
    final raw = prefs.getString(_kProfiles);
    final savedActive = prefs.getString(_kActiveId) ?? '';

    final profiles = <AiProfile>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        for (final item in list) {
          if (item is! Map) continue;
          final meta = item.map((k, v) => MapEntry('$k', v));
          final id = meta['id'] as String?;
          if (id == null || id.isEmpty) continue;
          profiles.add(
            AiProfile.fromMetaJson(meta, apiKey: await _readKey(id)),
          );
        }
      } catch (_) {
        // 存储损坏：视为未配置
      }
    }

    // 旧版迁移：新结构为空但有旧单配置 → 生成「默认配置」
    if (profiles.isEmpty) {
      final legacyBase = prefs.getString(_kLegacyBaseUrl);
      final legacyModel = prefs.getString(_kLegacyModel);
      final legacyKey = await _readKeyLegacy();
      if (legacyBase != null || legacyModel != null || legacyKey.isNotEmpty) {
        profiles.add(
          AiProfile(
            id: 'default',
            name: '默认配置',
            baseUrl: legacyBase ?? defaultBaseUrl,
            model: legacyModel ?? defaultModel,
            apiKey: legacyKey,
          ),
        );
        await prefs.setString(
          _kProfiles,
          jsonEncode([profiles.first.toMetaJson()]),
        );
        await prefs.setString(_kActiveId, 'default');
        if (legacyKey.isNotEmpty) {
          try {
            await _secure.write(key: keyFor('default'), value: legacyKey);
          } catch (_) {}
        }
      }
    }

    final activeId = profiles.isEmpty
        ? ''
        : (profiles.any((p) => p.id == savedActive)
              ? savedActive
              : profiles.first.id);

    return AiConfig(enabled: enabled, profiles: profiles, activeId: activeId);
  }

  /// 保存配置：元信息进 SharedPreferences，API Key 进加密存储；
  /// 已删除配置的 Key 一并清理。
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();

    // 先收集旧配置 id（用于清理被删除配置的 Key）
    final oldIds = <String>[];
    final oldRaw = prefs.getString(_kProfiles);
    if (oldRaw != null && oldRaw.isNotEmpty) {
      try {
        final list = jsonDecode(oldRaw) as List;
        for (final item in list) {
          if (item is Map && item['id'] is String) {
            final id = item['id'] as String;
            if (id.isNotEmpty) oldIds.add(id);
          }
        }
      } catch (_) {}
    }

    await prefs.setBool(_kEnabled, enabled);
    await prefs.setString(
      _kProfiles,
      jsonEncode([for (final p in profiles) p.toMetaJson()]),
    );
    await prefs.setString(_kActiveId, activeId);

    try {
      for (final p in profiles) {
        if (p.apiKey.isEmpty) {
          await _secure.delete(key: keyFor(p.id));
        } else {
          await _secure.write(key: keyFor(p.id), value: p.apiKey);
        }
      }
      final newIds = profiles.map((p) => p.id).toSet();
      for (final id in oldIds) {
        if (!newIds.contains(id)) {
          await _secure.delete(key: keyFor(id));
        }
      }
    } catch (_) {
      // 加密存储不可用：忽略（Key 不落盘）
    }
  }

  static Future<String> _readKey(String id) async {
    try {
      return await _secure.read(key: keyFor(id)) ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<String> _readKeyLegacy() async {
    try {
      return await _secure.read(key: _kLegacyApiKey) ?? '';
    } catch (_) {
      return '';
    }
  }
}
