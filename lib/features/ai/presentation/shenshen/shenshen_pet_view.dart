import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart' show rootBundle;

/// dsh-pet 风格的帧动画桌宠（shenshen 角色，素材来自参考项目）。
///
/// 行为参考 dsh-pet：
/// - 待机时按概率决策：保持待机 / 转向 / 随机小动作 / 左右漫步
/// - 点击：随机点击回应动画（配合 Flutter 层小黄鸭音效）
/// - 按住拖动：被拎起悬空动画，松手后受重力下落、落地回弹
class ShenshenPetView extends StatefulWidget {
  const ShenshenPetView({
    super.key,
    this.scale = 0.7,
    this.autoAction = true,
    this.onTap,
  });

  /// 大小系数（0.4 ~ 1.2），形象高度 = 舞台高度 * 30% * scale
  final double scale;

  /// 是否自动做动作/漫步
  final bool autoAction;
  final VoidCallback? onTap;

  @override
  State<ShenshenPetView> createState() => _ShenshenPetViewState();
}

class _ShenshenPetViewState extends State<ShenshenPetView>
    with SingleTickerProviderStateMixin {
  // 帧图原始尺寸（248x294，来自 640x360 视频的身体框裁剪）
  static const _frameW = 248.0;
  static const _frameH = 294.0;

  final Map<String, int> _frameCount = {};
  final Map<String, double> _clipFps = {};
  final math.Random _random = math.Random();
  bool _loaded = false;
  int _randomCount = 0;
  int _clickCount = 0;
  int _moveCount = 0;
  int _balanceCount = 0;

  // 当前动画
  String _clip = 'idle';
  int _frame = 0;
  double _animT = 0;

  // 物理：_cx 脚底中心 x，_h 脚底距底部高度（0 = 地面）
  double? _cx;
  double _h = 0;
  double _vy = 0;
  double _facing = 1;
  bool _dragging = false;

  // 行为
  double _t = 0;
  double _nextDecision = 2.5;
  double _moveUntil = 0;
  double _areaW = 0;
  double _areaH = 0;
  double _petW = 0;
  double _petH = 0;

  late final Ticker _ticker;
  double _last = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final raw = await rootBundle.loadString('assets/pet/shenshen/clips.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final counts = <String, int>{};
      final fps = <String, double>{};
      for (final entry in data.entries) {
        final v = entry.value as Map;
        counts[entry.key] = (v['frames'] as num).toInt();
        fps[entry.key] = (v['fps'] as num).toDouble();
      }
      if (!mounted) return;
      int countOf(String prefix) =>
          counts.keys.where((k) => k.startsWith(prefix)).length;
      setState(() {
        _frameCount.addAll(counts);
        _clipFps.addAll(fps);
        _randomCount = countOf('random_');
        _clickCount = countOf('click_');
        _moveCount = countOf('move_');
        _balanceCount = countOf('balance_');
        _loaded = true;
      });
      // 预缓存常用动作帧（其余按需加载，避免一次性占用过多内存）
      for (final clip in _frameCount.keys) {
        if (!clip.startsWith('idle') &&
            !clip.startsWith('click_') &&
            !clip.startsWith('move_') &&
            !clip.startsWith('drag') &&
            !clip.startsWith('turn')) {
          continue;
        }
        for (var i = 0; i < _frameCount[clip]!; i++) {
          if (!mounted) return;
          await precacheImage(AssetImage(_path(clip, i)), context);
        }
      }
    } catch (_) {
      // 加载失败：保持空白（不影响其它功能）
    }
  }

  String _path(String clip, int index) =>
      'assets/pet/shenshen/frames/${clip}_$index.webp';

  void _play(String clip) {
    if (!_frameCount.containsKey(clip)) return;
    _clip = clip;
    _frame = 0;
    _animT = 0;
  }

  void _playOnce(String clip) {
    _play(clip);
  }

  bool get _clipIsLooping =>
      _clip == 'idle' || _clip == 'drag' || _clip.startsWith('move_');

  void _tick(Duration elapsed) {
    final now = elapsed.inMicroseconds / 1e6;
    final dt = (_last == 0 ? 0.016 : now - _last).clamp(0.0, 0.05);
    _last = now;
    if (!_loaded) return;
    _t += dt;

    _advanceFrames(dt);
    _stepPhysics(dt);
    _decideWhenIdle();
    if (mounted) setState(() {});
  }

  void _advanceFrames(double dt) {
    final fps = _clipFps[_clip] ?? 8;
    final frameDur = 1 / fps;
    _animT += dt;
    while (_animT >= frameDur) {
      _animT -= frameDur;
      _frame++;
      if (_frame >= (_frameCount[_clip] ?? 1)) {
        if (_clipIsLooping) {
          _frame = 0;
        } else {
          _frame = (_frameCount[_clip] ?? 1) - 1;
          // 非循环动作结束：回到待机
          if (_clip != 'drag') _play('idle');
          break;
        }
      }
    }
  }

  void _stepPhysics(double dt) {
    if (_dragging) return;

    // 重力下落 + 落地回弹
    if (_h > 0 || _vy.abs() > 0.1) {
      _vy -= 900 * dt;
      _h += _vy * dt;
      if (_h <= 0) {
        _h = 0;
        if (_vy < -80) {
          _vy = -_vy * 0.35; // 回弹
        } else {
          _vy = 0;
        }
      }
    }

    // 漫步移动
    if (_clip.startsWith('move_') && _t < _moveUntil) {
      final cx = _cx ?? _areaW / 2;
      _cx = (cx + _facing * 46 * dt).clamp(
        _petW / 2,
        math.max(_petW / 2, _areaW - _petW / 2),
      );
    }
    if (_clip.startsWith('move_') && _t >= _moveUntil) {
      _play('idle');
    }
  }

  void _decideWhenIdle() {
    if (!widget.autoAction) return;
    if (_dragging || _clip != 'idle' || _t < _nextDecision) return;
    final r = _random.nextDouble();
    if (r < 0.28) {
      // 继续待机
      _nextDecision = _t + 2.5 + _random.nextDouble() * 2.5;
    } else if (r < 0.38) {
      // 转向
      _facing *= -1;
      _playOnce('turn');
      _nextDecision = _t + 1.4;
    } else if (r < 0.78 && _randomCount > 0) {
      // 随机动作（全部收录）
      _playOnce('random_${_random.nextInt(_randomCount)}');
      _nextDecision = _t + 2.0 + _random.nextDouble() * 1.5;
    } else if (r < 0.84 && _balanceCount > 0) {
      // 余额事件动作
      _playOnce('balance_${_random.nextInt(_balanceCount)}');
      _nextDecision = _t + 2.0 + _random.nextDouble() * 1.5;
    } else if (_moveCount > 0) {
      // 漫步
      _facing = _random.nextBool() ? 1 : -1;
      _play('move_${_random.nextInt(_moveCount)}');
      final dur = 1.2 + _random.nextDouble() * 2.2;
      _moveUntil = _t + dur;
      _nextDecision = _t + dur + 0.4;
    } else {
      _nextDecision = _t + 3;
    }
  }

  void _onTap() {
    widget.onTap?.call();
    if (_clickCount > 0) {
      _playOnce('click_${_random.nextInt(_clickCount)}');
    }
  }

  void _onPanStart(DragStartDetails details) {
    _dragging = true;
    _vy = 0;
    _play('drag');
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _cx = ((_cx ?? _areaW / 2) + details.delta.dx).clamp(
        _petW / 2,
        math.max(_petW / 2, _areaW - _petW / 2),
      );
      _h = (_h - details.delta.dy).clamp(0.0, _areaH);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    _dragging = false;
    _vy = 0; // 从当前位置自由落体
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _areaW = constraints.maxWidth;
        _areaH = constraints.maxHeight;
        // 以原始帧分辨率（294）为基准按系数缩放：0.4~1.2 → 141~423px，
        // 默认 0.7 ≈ 247px（接近点对点，清晰）；调大时仅轻微放大。
        _petH = _frameH * widget.scale * 1.2;
        _petW = _petH * _frameW / _frameH;
        if (!_loaded) return const SizedBox.shrink();

        final cx = (_cx ?? constraints.maxWidth / 2)
            .clamp(
              _petW / 2,
              math.max(_petW / 2, constraints.maxWidth - _petW / 2),
            )
            .toDouble();
        final bottom = _h
            .clamp(0.0, math.max(0.0, constraints.maxHeight - _petH))
            .toDouble();

        return Stack(
          children: [
            Positioned(
              left: cx - _petW / 2,
              bottom: bottom,
              width: _petW,
              height: _petH,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _onTap,
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                child: Image.asset(
                  _path(_clip, _frame),
                  gaplessPlayback: true,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
