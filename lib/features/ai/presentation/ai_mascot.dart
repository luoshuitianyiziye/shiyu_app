import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/morandi_theme.dart';
import 'whale/whale_pet_view.dart';

/// 小屿（鲸鱼少女）情绪状态
enum AiMascotMood { idle, thinking, happy, sad }

/// AI 形象舞台：鲸鱼女仆 Live2D 渲染（WebView）+ 顶部气泡台词。
///
/// 形象渲染器与贴图来自开源项目 Coopanion（AGPL-3.0-or-later）的 whale
/// 形象包；页面为自包含单文件 `assets/ai/whale/index.html`。
/// 对外 API 保持不变（mood / bubbleText / onTap），尺寸由父级舞台决定。
class AiMascot extends StatefulWidget {
  const AiMascot({
    super.key,
    this.mood = AiMascotMood.idle,
    this.bubbleText,
    this.onTap,
  });

  final AiMascotMood mood;

  /// 自定义气泡文字；null 时按情绪随机台词
  final String? bubbleText;
  final VoidCallback? onTap;

  @override
  State<AiMascot> createState() => _AiMascotState();
}

class _AiMascotState extends State<AiMascot> {
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
    _line = _pickLine();
  }

  @override
  void didUpdateWidget(covariant AiMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mood != widget.mood) {
      _line = _pickLine();
    }
  }

  String _pickLine() {
    final pool = switch (widget.mood) {
      AiMascotMood.thinking => _thinkingLines,
      AiMascotMood.happy => _happyLines,
      AiMascotMood.sad => _sadLines,
      AiMascotMood.idle => _idleLines,
    };
    _lineSeed =
        (_lineSeed + 1 + math.Random().nextInt(pool.length)) % pool.length;
    return pool[_lineSeed];
  }

  void _onPoke() {
    setState(() => _line = _pickLine());
    widget.onTap?.call();
  }

  WhalePetMood get _whaleMood => switch (widget.mood) {
    AiMascotMood.thinking => WhalePetMood.thinking,
    AiMascotMood.happy => WhalePetMood.happy,
    AiMascotMood.sad => WhalePetMood.sad,
    AiMascotMood.idle => WhalePetMood.idle,
  };

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final shownText = widget.bubbleText ?? _line;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Live2D 形象（WebView 舞台，透明背景）
        WhalePetView(mood: _whaleMood, line: shownText, onPoke: _onPoke),
        // 台词气泡（Flutter 层，浮在舞台顶部，指向形象）
        Positioned(
          top: 6,
          left: 12,
          right: 12,
          child: Center(
            child: _SpeechBubble(text: shownText, palette: palette),
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
          constraints: const BoxConstraints(maxWidth: 260),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.outline),
            boxShadow: [
              BoxShadow(
                color: palette.primaryDark.withValues(alpha: 0.10),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: palette.textPrimary),
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
