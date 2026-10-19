import 'package:flutter/material.dart';

import '../../../app/theme/morandi_theme.dart';
import '../../growth/data/ranks.dart';

/// 晋段庆祝弹窗：展示新解锁的段位插画
Future<void> showRankUpDialog(BuildContext context, RankInfo rank) {
  final palette = Theme.of(context).extension<MorandiPalette>()!;

  return showDialog(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      backgroundColor: palette.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      // 入场动画：0.9→1.0 回弹放大 + 淡入
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutBack,
        builder: (context, t, child) => Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(scale: 0.9 + 0.1 * t, child: child),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, size: 40, color: palette.primaryDark),
              const SizedBox(height: 8),
              Text(
                '晋段成功！',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: palette.primaryDark,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '恭喜晋升「${rank.name}」段位',
                style: TextStyle(fontSize: 15, color: palette.textSecondary),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 380),
                  child: AspectRatio(
                    aspectRatio: 9 / 16,
                    child: Image.asset(
                      rank.assetPath,
                      fit: BoxFit.cover,
                      cacheWidth: 400,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '已解锁段位插画 ${rank.index}/9，继续加油！',
                style: TextStyle(fontSize: 13, color: palette.textSecondary),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('太棒了'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
