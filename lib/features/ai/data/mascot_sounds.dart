import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';

/// AI 形象音效（小黄鸭 / 点击 / 生成状态）。
///
/// 短音效：不抢音频焦点，失败静默（音效失败不影响功能）。
class MascotSounds {
  MascotSounds._();

  static final AudioPlayer _player = AudioPlayer(playerId: 'mascot_sfx');
  static bool enabled = true;
  static bool _prepared = false;

  static Future<void> _ensure() async {
    if (_prepared) return;
    _prepared = true;
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setVolume(0.8);
    } catch (_) {
      // 播放器初始化失败时不影响后续调用（每次 play 都有 try/catch）
    }
  }

  static Future<void> play(String asset, {double volume = 0.8}) async {
    if (!enabled) return;
    try {
      await _ensure();
      await _player.stop();
      await _player.setVolume(volume);
      await _player.play(AssetSource(asset));
    } catch (_) {
      // 静默失败
    }
  }

  /// 点击形象：小黄鸭（随机两只，默认 60% 概率触发，避免每次响）
  static void duck({double probability = 0.6}) {
    if (math.Random().nextDouble() > probability) return;
    final n = math.Random().nextBool() ? 1 : 2;
    play('sounds/duck/Ya$n.mp3', volume: 0.85);
  }

  static void click() => play('sounds/click.wav', volume: 0.6);
  static void start() => play('sounds/agent/start.wav', volume: 0.7);
  static void done() => play('sounds/agent/done.wav', volume: 0.75);
  static void error() => play('sounds/agent/error.wav', volume: 0.7);
}
