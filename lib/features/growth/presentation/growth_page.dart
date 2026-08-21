import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/morandi_theme.dart';
import '../../../core/db/database.dart';
import '../../../core/db/db_providers.dart';
import '../../settings/presentation/theme_picker_sheet.dart';
import '../data/ranks.dart';
import '../data/stats.dart';

/// 「我的」页：昵称 / 等级经验 / 段位墙入口 / 设置与统计（开发中）
class GrowthPage extends ConsumerWidget {
  const GrowthPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final userAsync = ref.watch(userStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (user) => _buildBody(context, ref, palette, user),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    MorandiPalette palette,
    UserRow user,
  ) {
    final nicknameNotifier = ref.watch(nicknameNotifierProvider);
    final level = levelFromXp(user.xpTotal);
    final currentRank = rankForLevel(level);
    final unlocked = unlockedRankCount(level);
    final nextXp = xpNeededForLevel(level + 1);
    // Lv.1 的经验区间下限是 0（而非 xpNeededForLevel(1)=100），
    // 否则新用户前 100 XP 进度条恒为 0
    final curXp = level == 1 ? 0 : xpNeededForLevel(level);
    final progress = ((user.xpTotal - curXp) / (nextXp - curXp))
        .clamp(0.0, 1.0)
        .toDouble();
    // 统计快照：专注/成就卡片实时数据（任务或番茄变化时由对应页面刷新）
    final stats = ref.watch(statsSnapshotProvider).value;
    final achievements = stats == null ? null : buildAchievements(stats);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 点击昵称区域 → 个人资料页；昵称在资料页修改后实时刷新
        ValueListenableBuilder<String?>(
          valueListenable: nicknameNotifier,
          builder: (context, nickname, _) => InkWell(
            onTap: () => context.push('/profile'),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: palette.accent,
                    child: Icon(Icons.person, color: palette.primaryDark, size: 30),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nickname ?? '时屿用户',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Lv.$level · ${currentRank.name} 段位 · 连续 ${user.streakDays} 天',
                          style: TextStyle(fontSize: 13, color: palette.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: palette.textSecondary),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '经验值',
                  style: TextStyle(color: palette.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: palette.accent,
                    color: palette.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${user.xpTotal} XP · 距 Lv.${level + 1} 还差 ${nextXp - user.xpTotal} XP',
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: InkWell(
            onTap: () => context.push('/rank-wall'),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      currentRank.assetPath,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      cacheWidth: 120,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '段位墙',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: palette.textPrimary,
                          ),
                        ),
                        Text(
                          '已解锁 $unlocked/9 · 收集你的九段位插画',
                          style: TextStyle(fontSize: 12, color: palette.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: palette.textSecondary),
                ],
              ),
            ),
          ),
        ),
        // ===== 个性化 =====
        const _SectionGroupTitle('个性化'),
        Card(
          child: InkWell(
            onTap: () => showThemePicker(context, ref),
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: _SectionCardContent(
                icon: Icons.palette_outlined,
                title: '主题',
                subtitle: '雾绿 / 藕粉 / 雾蓝 / 燕麦 / 香芋 / 墨夜',
              ),
            ),
          ),
        ),
        // ===== 数据与统计 =====
        const _SectionGroupTitle('数据与统计'),
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            onTap: () => context.push('/stats'),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _SectionCardContent(
                icon: Icons.bar_chart_outlined,
                title: '专注统计',
                subtitle: stats == null
                    ? '每周专注时长 · 完成率'
                    : '本周 ${stats.weekPomodoros} 番茄 · ${stats.weekMinutes} 分钟 · 累计 ${stats.totalPomodoros}',
              ),
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            onTap: () => context.push('/achievements'),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _SectionCardContent(
                icon: Icons.emoji_events_outlined,
                title: '成就',
                subtitle: achievements == null
                    ? '首次完成 · 连续 7 天 · 100 番茄'
                    : '已解锁 ${achievements.where((a) => a.unlocked).length}/${achievements.length}',
              ),
            ),
          ),
        ),
        // ===== 通用 =====
        const _SectionGroupTitle('通用'),
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            onTap: () => context.push('/settings'),
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: _SectionCardContent(
                icon: Icons.settings_outlined,
                title: '设置',
                subtitle: '番茄参数 · 提醒时间 · 默认白噪音',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 分组标题：用于「我的」页将不同功能区块分隔开
class _SectionGroupTitle extends StatelessWidget {
  const _SectionGroupTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
          color: palette.textSecondary,
        ),
      ),
    );
  }
}

class _SectionCardContent extends StatelessWidget {
  const _SectionCardContent({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;

    return Row(
      children: [
        Icon(icon, color: palette.primaryDark, size: 26),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: palette.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
