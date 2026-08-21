import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/morandi_theme.dart';
import '../../../core/db/db_providers.dart';
import '../data/ranks.dart';

/// 段位墙：9 张段位插画收集页（已解锁展示原图，未解锁显示剪影）
class RankWallPage extends ConsumerWidget {
  const RankWallPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final userAsync = ref.watch(userStreamProvider);
    final user = userAsync.value;
    final level = user == null ? 1 : levelFromXp(user.xpTotal);
    final unlocked = unlockedRankCount(level);
    final current = rankForLevel(level);

    return Scaffold(
      appBar: AppBar(title: const Text('段位墙')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    '当前段位',
                    style: TextStyle(color: palette.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    current.name,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: palette.primaryDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '已解锁 $unlocked / 9 个段位',
                    style: TextStyle(color: palette.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () => showRankPreview(
                      context,
                      rank: current,
                      unlocked: true,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: AspectRatio(
                        aspectRatio: 9 / 16,
                        child: Image.asset(
                          current.assetPath,
                          fit: BoxFit.cover,
                          cacheWidth: 1000,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '点击图片可放大',
                    style: TextStyle(color: palette.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 9 / 16,
            ),
            itemCount: kRanks.length,
            itemBuilder: (context, i) {
              final rank = kRanks[i];
              return _RankCard(
                rank: rank,
                unlocked: i < unlocked,
                current: rank.index == current.index,
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 全屏查看段位插画：支持双指缩放 / 拖动，点击背景关闭
Future<void> showRankPreview(
  BuildContext context, {
  required RankInfo rank,
  required bool unlocked,
}) {
  return showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          // 可缩放图片
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(ctx).pop(),
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: AspectRatio(
                            aspectRatio: 9 / 16,
                            child: ColorFiltered(
                              colorFilter: ColorFilter.mode(
                                unlocked
                                    ? const Color(0x00000000)
                                    : Colors.black.withValues(alpha: 0.65),
                                BlendMode.darken,
                              ),
                              child: Image.asset(
                                rank.assetPath,
                                fit: BoxFit.cover,
                                color: unlocked
                                    ? null
                                    : Colors.white.withValues(alpha: 0.12),
                                colorBlendMode: unlocked
                                    ? null
                                    : BlendMode.saturation,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 未解锁遮罩
          if (!unlocked)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline, color: Colors.white70),
                        SizedBox(width: 8),
                        Text(
                          '尚未解锁',
                          style: TextStyle(color: Colors.white70, fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // 顶部信息栏
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '${rank.index}. ${rank.name} · ${unlocked ? 'Lv.${rank.minLevel} 已解锁' : 'Lv.${rank.minLevel} 解锁'}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close, color: Colors.white),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.55),
                      ),
                      tooltip: '关闭',
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 底部提示
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Center(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    unlocked
                        ? '双指缩放 · 点击空白处关闭'
                        : '完成每日任务获取经验，升级解锁 · 点击空白处关闭',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _RankCard extends StatelessWidget {
  const _RankCard({
    required this.rank,
    required this.unlocked,
    required this.current,
  });

  final RankInfo rank;
  final bool unlocked;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;

    return GestureDetector(
      onTap: () => showRankPreview(
        context,
        rank: rank,
        unlocked: unlocked,
      ),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: current ? Border.all(color: palette.primary, width: 2.5) : null,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              rank.assetPath,
              fit: BoxFit.cover,
              cacheWidth: 360,
              color: unlocked
                  ? null
                  : Colors.white.withValues(alpha: 0.35),
              colorBlendMode: unlocked ? null : BlendMode.saturation,
            ),
            if (!unlocked) ...[
              Container(color: Colors.black.withValues(alpha: 0.5)),
              const Center(
                child: Icon(Icons.lock_outline, color: Colors.white70, size: 30),
              ),
            ],
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                color: Colors.black.withValues(alpha: unlocked ? 0.45 : 0.55),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${rank.index}. ${rank.name}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      unlocked ? 'Lv.${rank.minLevel} 已解锁' : 'Lv.${rank.minLevel} 解锁',
                      style: const TextStyle(color: Colors.white70, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
            if (current)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: palette.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    '当前',
                    style: TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
