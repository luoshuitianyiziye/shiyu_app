import 'package:flutter/material.dart';

import '../../../app/theme/morandi_theme.dart';

/// 模块开发中的占位页
class PlaceholderBody extends StatelessWidget {
  const PlaceholderBody({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.features = const [],
  });

  final IconData icon;
  final String title;
  final String description;
  final List<String> features;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>();

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: (palette?.accent ?? const Color(0xFFC4D6B0)).withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 44,
                color: palette?.primaryDark ?? const Color(0xFF7A9B78),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: palette?.textPrimary ?? Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: palette?.textSecondary ?? Colors.black54,
              ),
            ),
            if (features.isNotEmpty) ...[
              const SizedBox(height: 20),
              ...features.map(
                (f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 16,
                        color: palette?.primary ?? const Color(0xFF9DBB9B),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          f,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: palette?.textSecondary ?? Colors.black54,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: (palette?.accent ?? const Color(0xFFC4D6B0)).withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '开发中 · 敬请期待',
                style: TextStyle(
                  fontSize: 12,
                  color: palette?.primaryDark ?? const Color(0xFF7A9B78),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
