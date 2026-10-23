import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AI 形象设置（大小 / 皮肤 / 音效），持久化到 SharedPreferences。
class AiMascotSettings {
  const AiMascotSettings({
    this.scale = 1.0,
    this.skin = 'deepseek',
    this.soundOn = true,
  });

  /// 形象大小系数（0.6 ~ 1.5）
  final double scale;

  /// 皮肤 id（见 [skins]）
  final String skin;

  /// 音效开关（小黄鸭等）
  final bool soundOn;

  static const skins = <String, String>{
    'deepseek': 'DeepSeek 蓝',
    'harness': 'Harness 黑',
    'claude': 'Claude 橙',
  };

  AiMascotSettings copyWith({double? scale, String? skin, bool? soundOn}) {
    return AiMascotSettings(
      scale: scale ?? this.scale,
      skin: skin ?? this.skin,
      soundOn: soundOn ?? this.soundOn,
    );
  }

  static const _kScale = 'ai_mascot_scale';
  static const _kSkin = 'ai_mascot_skin';
  static const _kSound = 'ai_mascot_sound';

  static Future<AiMascotSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final scale = (prefs.getDouble(_kScale) ?? 1.0).clamp(0.6, 1.5);
    final skin = prefs.getString(_kSkin) ?? 'deepseek';
    return AiMascotSettings(
      scale: scale,
      skin: skins.containsKey(skin) ? skin : 'deepseek',
      soundOn: prefs.getBool(_kSound) ?? true,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kScale, scale);
    await prefs.setString(_kSkin, skin);
    await prefs.setBool(_kSound, soundOn);
  }
}

class AiMascotSettingsNotifier extends Notifier<AiMascotSettings> {
  @override
  AiMascotSettings build() => const AiMascotSettings();

  Future<void> load() async {
    state = await AiMascotSettings.load();
  }

  /// 拖动滑块时实时预览（不落盘）
  void previewScale(double scale) {
    state = state.copyWith(scale: scale.clamp(0.6, 1.5));
  }

  Future<void> setScale(double scale) async {
    state = state.copyWith(scale: scale.clamp(0.6, 1.5));
    await state.save();
  }

  Future<void> setSkin(String skin) async {
    if (!AiMascotSettings.skins.containsKey(skin)) return;
    state = state.copyWith(skin: skin);
    await state.save();
  }

  Future<void> setSoundOn(bool on) async {
    state = state.copyWith(soundOn: on);
    await state.save();
  }
}

final aiMascotSettingsProvider =
    NotifierProvider<AiMascotSettingsNotifier, AiMascotSettings>(
      AiMascotSettingsNotifier.new,
    );
