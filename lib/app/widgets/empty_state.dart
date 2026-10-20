import 'package:flutter/material.dart';

import '../theme/morandi_theme.dart';

/// 统一空状态：品牌插画（岛屿 + 波纹 + 晨光）+ 标题 + 副标题 + 可选操作按钮。
///
/// 用于「今天还没有任务」「还没有笔记」「还没有倒数日」等场景。
/// [compact] 为 true 时使用圆形图标（用于页面内局部区域）。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// 非空且 [onAction] 非空时显示操作按钮
  final String? actionLabel;
  final VoidCallback? onAction;

  /// 紧凑模式：圆形图标 + 更小字号（用于页面内局部区域）
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (compact)
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 26, color: palette.primaryDark),
              )
            else
              // 品牌插画：晨雾中的岛屿与波纹
              SizedBox(
                width: 168,
                height: 116,
                child: CustomPaint(painter: _EmptyIllustrationPainter(palette)),
              ),
            SizedBox(height: compact ? 12 : 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: compact ? 15 : 16,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: compact ? 12 : 13,
                  color: palette.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: compact ? 14 : 18),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add, size: 18),
                label: Text(actionLabel!),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 46),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 空状态插画：低饱和山丘 + 波纹 + 晨光，随主题配色
class _EmptyIllustrationPainter extends CustomPainter {
  _EmptyIllustrationPainter(this.palette);

  final MorandiPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 晨光光晕
    canvas.drawCircle(
      Offset(w * 0.5, h * 0.34),
      w * 0.2,
      Paint()
        ..color = palette.gold.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );

    // 远山（两座，低透明度）
    final farHill = Paint()..color = palette.primary.withValues(alpha: 0.16);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.3, h * 0.86),
        width: w * 0.78,
        height: h * 0.46,
      ),
      farHill,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.72, h * 0.9),
        width: w * 0.66,
        height: h * 0.4,
      ),
      Paint()..color = palette.primary.withValues(alpha: 0.1),
    );

    // 波纹（三条弧线，越远越淡）
    for (var i = 0; i < 3; i++) {
      final y = h * (0.64 + i * 0.11);
      final wave = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = palette.primaryDark.withValues(alpha: 0.3 - i * 0.08);
      final path = Path()
        ..moveTo(w * (0.14 + i * 0.03), y)
        ..quadraticBezierTo(w * 0.4, y - 7, w * 0.5, y)
        ..quadraticBezierTo(w * 0.6, y + 7, w * (0.86 - i * 0.03), y);
      canvas.drawPath(path, wave);
    }

    // 晨光圆点
    canvas.drawCircle(
      Offset(w * 0.5, h * 0.32),
      5,
      Paint()..color = palette.gold,
    );

    // 点缀星光
    final star = Paint()..color = palette.gold.withValues(alpha: 0.7);
    canvas.drawCircle(Offset(w * 0.2, h * 0.36), 1.8, star);
    canvas.drawCircle(Offset(w * 0.82, h * 0.26), 1.4, star);
    canvas.drawCircle(Offset(w * 0.64, h * 0.12), 1.2, star);
  }

  @override
  bool shouldRepaint(covariant _EmptyIllustrationPainter oldDelegate) =>
      oldDelegate.palette != palette;
}
