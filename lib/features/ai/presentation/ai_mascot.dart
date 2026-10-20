import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/morandi_theme.dart';

/// 小屿（鲸鱼少女）情绪状态
enum AiMascotMood { idle, thinking, happy, sad }

/// Q 版 AI 形象：浮动 + 呼吸 + 点击互动 + 气泡台词
///
/// 素材来自设计三视图（assets/ai/mascot_front.png，透明背景）。
class AiMascot extends StatefulWidget {
  const AiMascot({
    super.key,
    this.mood = AiMascotMood.idle,
    this.bubbleText,
    this.size = 120,
    this.onTap,
  });

  final AiMascotMood mood;

  /// 自定义气泡文字；null 时按情绪随机台词
  final String? bubbleText;
  final double size;
  final VoidCallback? onTap;

  @override
  State<AiMascot> createState() => _AiMascotState();
}

class _AiMascotState extends State<AiMascot>
    with TickerProviderStateMixin {
  late final AnimationController _idleController;
  late final AnimationController _reactController;
  late String _line;
  int _lineSeed = 0;

  static const _idleLines = [
    '今天也一起加油吧～',
    '有什么想做的，说给我听～',
    '我在这儿呢！',
    '要不要让我帮你排任务？',
  ];
  static const _thinkingLines = ['让我想想…', '翻翻我的小本子…', '马上就好～'];
  static const _happyLines = ['给你列好啦，看看对不对～', '搞定！要不要调整一下？', '都安排上了！'];
  static const _sadLines = ['呜…没想出来，再试一次好不好？', '好像卡住了…', '网络有点不听话…'];

  @override
  void initState() {
    super.initState();
    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
    _reactController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    _line = _pickLine();
  }

  @override
  void didUpdateWidget(covariant AiMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mood != widget.mood) {
      _line = _pickLine();
      if (widget.mood == AiMascotMood.happy ||
          widget.mood == AiMascotMood.sad) {
        _reactController.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _idleController.dispose();
    _reactController.dispose();
    super.dispose();
  }

  String _pickLine() {
    final pool = switch (widget.mood) {
      AiMascotMood.thinking => _thinkingLines,
      AiMascotMood.happy => _happyLines,
      AiMascotMood.sad => _sadLines,
      AiMascotMood.idle => _idleLines,
    };
    _lineSeed = (_lineSeed + 1 + math.Random().nextInt(pool.length)) %
        pool.length;
    return pool[_lineSeed];
  }

  void _onTap() {
    setState(() => _line = _pickLine());
    _reactController.forward(from: 0);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final shownText = widget.bubbleText ?? _line;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (shownText.isNotEmpty)
          _SpeechBubble(text: shownText, palette: palette),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: _onTap,
          child: AnimatedBuilder(
            animation: Listenable.merge([_idleController, _reactController]),
            builder: (context, _) {
              final idle = _idleController.value;
              final wave = math.sin(idle * math.pi * 2);
              final t = _reactController.value;
              var dy = wave * (widget.mood == AiMascotMood.thinking ? 5 : 4);
              var dx = 0.0;
              var scale = 1 + 0.012 * wave;
              var angle = 0.0;

              if (widget.mood == AiMascotMood.thinking) {
                angle = math.sin(idle * math.pi * 4) * 0.025;
              }
              if (widget.mood == AiMascotMood.happy &&
                  _reactController.isAnimating) {
                scale = 1 + 0.13 * math.sin(t * math.pi);
                dy -= 10 * math.sin(t * math.pi);
              }
              if (widget.mood == AiMascotMood.sad &&
                  _reactController.isAnimating) {
                dx = math.sin(t * math.pi * 8) * 4 * (1 - t);
              }

              return Transform.translate(
                offset: Offset(dx, dy),
                child: Transform.rotate(
                  angle: angle,
                  child: Transform.scale(
                    scale: scale,
                    child: Image.asset(
                      'assets/ai/mascot_front.png',
                      width: widget.size,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 气泡对话框（圆角卡片 + 小尖角）
class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({required this.text, required this.palette});

  final String text;
  final MorandiPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 220),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.outline),
            boxShadow: [
              BoxShadow(
                color: palette.primaryDark.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: palette.textPrimary),
          ),
        ),
        CustomPaint(
          size: const Size(14, 7),
          painter: _BubbleTailPainter(
            color: palette.card,
            borderColor: palette.outline,
          ),
        ),
      ],
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  _BubbleTailPainter({required this.color, required this.borderColor});

  final Color color;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.borderColor != borderColor;
}
