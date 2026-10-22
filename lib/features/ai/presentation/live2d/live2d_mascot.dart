import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 情绪（沿用现有枚举，新增 shy 由长按内部触发）
enum Live2DMood { idle, thinking, happy, sad, shy }

/// 图层几何常量（基于原图 512×716）
class Live2DLayers {
  Live2DLayers._();

  static const imgWidth = 512.0;
  static const imgHeight = 716.0;

  /// 左眼层位置（原图坐标）
  static const eyeLeft = Rect.fromLTWH(153, 304, 64, 48);

  /// 右眼层位置（原图坐标）
  static const eyeRight = Rect.fromLTWH(284, 304, 64, 48);

  /// 视线最大偏移（原图像素）
  static const lookMaxX = 9.0;
  static const lookMaxY = 4.0;
}

/// 分情绪参数
class _MoodStyle {
  const _MoodStyle({
    required this.lookY,
    required this.eyeSquash,
    required this.blush,
    required this.headTilt,
    required this.blinkMin,
    required this.blinkMax,
  });

  /// 视线垂直倾向（-1 上 / 0 平 / 1 下）
  final double lookY;

  /// 眼睛基础缩放（0.6 = 眯眼）
  final double eyeSquash;

  /// 腮红强度 0~1
  final double blush;

  /// 头部倾斜（度）
  final double headTilt;

  /// 眨眼间隔（秒）
  final double blinkMin;
  final double blinkMax;

  static const idle = _MoodStyle(
    lookY: 0,
    eyeSquash: 1,
    blush: 0.18,
    headTilt: 0,
    blinkMin: 2.4,
    blinkMax: 5.5,
  );

  static const thinking = _MoodStyle(
    lookY: -0.75,
    eyeSquash: 0.95,
    blush: 0.12,
    headTilt: 1.4,
    blinkMin: 4,
    blinkMax: 8,
  );

  static const happy = _MoodStyle(
    lookY: 0,
    eyeSquash: 0.72,
    blush: 0.55,
    headTilt: -0.8,
    blinkMin: 3,
    blinkMax: 6,
  );

  static const sad = _MoodStyle(
    lookY: 0.8,
    eyeSquash: 0.82,
    blush: 0.25,
    headTilt: 0.8,
    blinkMin: 3.5,
    blinkMax: 7,
  );

  static const shy = _MoodStyle(
    lookY: 0.35,
    eyeSquash: 0.6,
    blush: 0.95,
    headTilt: -1.6,
    blinkMin: 3,
    blinkMax: 6,
  );
}

/// 分层伪 Live2D 形象：呼吸 / 眨眼 / 视线跟随 / 头部微动 / 情绪表情 / 点击互动。
///
/// 图层：body.png（底图，眼球区域已挖空补肤色）+ eye_left/right.png（眼球层）。
/// 眼球层独立平移实现视线，垂直压扁实现眨眼（底图的眼皮/睫毛保持不动）。
class Live2DMascot extends StatefulWidget {
  const Live2DMascot({
    super.key,
    this.mood = Live2DMood.idle,
    this.size = 120,
    this.onTap,
    this.onLongPress,
  });

  final Live2DMood mood;
  final double size;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<Live2DMascot> createState() => _Live2DMascotState();
}

class _Live2DMascotState extends State<Live2DMascot>
    with TickerProviderStateMixin {
  late final AnimationController _breath;
  late final AnimationController _bounce;

  Timer? _blinkTimer;
  Timer? _lookTimer;

  /// 0=睁眼 1=闭眼（用 TweenAnimationBuilder 过渡）
  double _blink = 0;

  /// 视线目标（-1..1）
  Offset _lookTarget = Offset.zero;

  /// 长按害羞状态（3 秒后自动恢复）
  bool _shy = false;
  Timer? _shyTimer;

  _MoodStyle get _style {
    if (_shy) return _MoodStyle.shy;
    return switch (widget.mood) {
      Live2DMood.thinking => _MoodStyle.thinking,
      Live2DMood.happy => _MoodStyle.happy,
      Live2DMood.sad => _MoodStyle.sad,
      Live2DMood.shy => _MoodStyle.shy,
      Live2DMood.idle => _MoodStyle.idle,
    };
  }

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
    _bounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _scheduleBlink();
    _scheduleLook();
  }

  @override
  void didUpdateWidget(covariant Live2DMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mood != widget.mood) {
      _scheduleBlink();
      _scheduleLook();
    }
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _lookTimer?.cancel();
    _shyTimer?.cancel();
    _breath.dispose();
    _bounce.dispose();
    super.dispose();
  }

  /// 随机眨眼（间隔按情绪）
  void _scheduleBlink() {
    _blinkTimer?.cancel();
    final style = _style;
    final seconds =
        style.blinkMin +
        math.Random().nextDouble() * (style.blinkMax - style.blinkMin);
    _blinkTimer = Timer(Duration(milliseconds: (seconds * 1000).round()), () {
      if (!mounted) return;
      setState(() => _blink = 1);
      Timer(const Duration(milliseconds: 110), () {
        if (!mounted) return;
        setState(() => _blink = 0);
        _scheduleBlink();
      });
    });
  }

  /// 视线随机游移
  void _scheduleLook() {
    _lookTimer?.cancel();
    final style = _style;
    _lookTimer = Timer(
      Duration(milliseconds: 1500 + math.Random().nextInt(2200)),
      () {
        if (!mounted) return;
        setState(() {
          _lookTarget = Offset(
            -0.8 + math.Random().nextDouble() * 1.6,
            style.lookY + (-0.35 + math.Random().nextDouble() * 0.7),
          );
        });
        _scheduleLook();
      },
    );
  }

  void _handleTap() {
    _bounce.forward(from: 0);
    // 看向外侧随机方向 + 立即眨眼一次
    setState(() {
      _lookTarget = Offset(
        math.Random().nextBool() ? 0.9 : -0.9,
        -0.2 + math.Random().nextDouble() * 0.4,
      );
      _blink = 1;
    });
    Timer(const Duration(milliseconds: 90), () {
      if (mounted) setState(() => _blink = 0);
    });
    widget.onTap?.call();
  }

  void _handleLongPress() {
    _shyTimer?.cancel();
    setState(() => _shy = true);
    widget.onLongPress?.call();
    _shyTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _shy = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = _style;
    final scale = widget.size / Live2DLayers.imgWidth;
    final height = widget.size * Live2DLayers.imgHeight / Live2DLayers.imgWidth;

    return RepaintBoundary(
      child: GestureDetector(
        onTap: _handleTap,
        onLongPress: _handleLongPress,
        child: SizedBox(
          width: widget.size,
          height: height,
          child: AnimatedBuilder(
            animation: Listenable.merge([_breath, _bounce]),
            builder: (context, child) {
              final t = _breath.value;
              final wave = math.sin(t * math.pi * 2);
              final bounce = _bounce.isAnimating
                  ? math.sin(_bounce.value * math.pi)
                  : 0.0;
              final breathScale = 1 + 0.008 * wave;
              final dy = wave * 2.2 - bounce * 9;
              final tilt = (style.headTilt * math.pi / 180) + wave * 0.006;
              final sway = math.sin(t * math.pi * 2 + math.pi / 3) * 1.2;

              return Transform.translate(
                offset: Offset(sway, dy),
                child: Transform.rotate(
                  angle: tilt,
                  child: Transform.scale(
                    scale: breathScale,
                    alignment: Alignment.bottomCenter,
                    child: child,
                  ),
                ),
              );
            },
            child: _buildLayers(scale, style),
          ),
        ),
      ),
    );
  }

  Widget _buildLayers(double scale, _MoodStyle style) {
    final look = _lookTarget;
    final eyeScale = style.eyeSquash;

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/ai/live2d/body.png',
          fit: BoxFit.fill,
          gaplessPlayback: true,
        ),
        // 腮红（代码绘制，情绪控制透明度）
        Positioned(
          left: (112 - 4) * scale,
          top: (338 - 2) * scale,
          child: _blush(style.blush, 26 * scale, 12 * scale),
        ),
        Positioned(
          left: (372 - 4) * scale,
          top: (338 - 2) * scale,
          child: _blush(style.blush, 26 * scale, 12 * scale),
        ),
        _eyeLayer(
          path: 'assets/ai/live2d/eye_left.png',
          rect: Live2DLayers.eyeLeft,
          scale: scale,
          look: look,
          eyeScale: eyeScale,
        ),
        _eyeLayer(
          path: 'assets/ai/live2d/eye_right.png',
          rect: Live2DLayers.eyeRight,
          scale: scale,
          look: look,
          eyeScale: eyeScale,
        ),
      ],
    );
  }

  Widget _eyeLayer({
    required String path,
    required Rect rect,
    required double scale,
    required Offset look,
    required double eyeScale,
  }) {
    return Positioned(
      left: rect.left * scale,
      top: rect.top * scale,
      width: rect.width * scale,
      height: rect.height * scale,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: _blink),
        duration: const Duration(milliseconds: 95),
        curve: Curves.easeInOut,
        builder: (context, blink, child) {
          return Transform.translate(
            offset: Offset(
              look.dx * Live2DLayers.lookMaxX * scale,
              look.dy * Live2DLayers.lookMaxY * scale,
            ),
            child: Transform.scale(
              scaleY: (1 - blink * 0.88) * eyeScale,
              alignment: Alignment.topCenter,
              child: child,
            ),
          );
        },
        child: Image.asset(path, fit: BoxFit.fill, gaplessPlayback: true),
      ),
    );
  }

  Widget _blush(double strength, double w, double h) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: strength.clamp(0, 1),
        duration: const Duration(milliseconds: 350),
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: const Color(0xFFF7A8B8).withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(h),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF7A8B8).withValues(alpha: 0.35),
                blurRadius: 6,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
