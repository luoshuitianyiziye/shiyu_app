import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/morandi_theme.dart';
import '../../../core/db/db_providers.dart';
import '../../../core/utils/format.dart';

/// 专注统计页：累计 / 本周 / 最近 7 天柱状图 / 今日完成率
class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final statsAsync = ref.watch(statsSnapshotProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('专注统计')),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (s) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 累计三格
            Row(
              children: [
                _StatTile(
                  icon: Icons.timer_outlined,
                  label: '累计番茄',
                  value: '${s.totalPomodoros}',
                ),
                const SizedBox(width: 10),
                _StatTile(
                  icon: Icons.schedule_outlined,
                  label: '累计专注',
                  value: '${s.totalMinutes}',
                  unit: '分钟',
                ),
                const SizedBox(width: 10),
                _StatTile(
                  icon: Icons.check_circle_outline,
                  label: '完成任务',
                  value: '${s.totalTasksDone}',
                ),
              ],
            ),
            const SizedBox(height: 20),
            // 本周
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.calendar_view_week_outlined,
                        color: palette.primaryDark, size: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '本周专注',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${s.weekPomodoros} 个番茄 · 约 ${s.weekMinutes} 分钟',
                            style: TextStyle(
                                fontSize: 12, color: palette.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${s.weekPomodoros}',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: palette.primaryDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            // 最近 7 天
            Text(
              '最近 7 天',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                child: _SevenDayChart(
                  counts: s.last7Days,
                  palette: palette,
                ),
              ),
            ),
            const SizedBox(height: 20),
            // 今日完成率
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.today_outlined,
                            color: palette.primaryDark, size: 26),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '今日完成率',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          s.todayTotal == 0
                              ? '今日暂无任务'
                              : '${s.todayDone}/${s.todayTotal}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: palette.primaryDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: s.todayRate,
                        minHeight: 8,
                        backgroundColor: palette.accent,
                        color: palette.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      s.todayTotal == 0
                          ? '去「今日」页添加任务开始记录吧'
                          : '已完成 ${(s.todayRate * 100).round()}%',
                      style: TextStyle(
                          fontSize: 12, color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '专注时长 = 番茄数 × 完成时的专注时长设置',
              style: TextStyle(fontSize: 11, color: palette.textSecondary),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.unit = '',
  });

  final IconData icon;
  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;

    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(icon, color: palette.primaryDark, size: 22),
              const SizedBox(height: 6),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: palette.textPrimary,
                ),
              ),
              if (unit.isNotEmpty)
                Text(
                  unit,
                  style: TextStyle(fontSize: 10, color: palette.textSecondary),
                ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: palette.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 最近 7 天番茄数柱状图（纯 Widget 绘制，无第三方图表库）
class _SevenDayChart extends StatelessWidget {
  const _SevenDayChart({required this.counts, required this.palette});

  final List<int> counts;
  final MorandiPalette palette;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final maxCount = counts.fold<int>(0, (a, c) => c > a ? c : a);
    final barMax = maxCount == 0 ? 1.0 : maxCount.toDouble();

    return SizedBox(
      height: 140,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 7; i++) ...[
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    counts[i] > 0 ? '${counts[i]}' : '',
                    style: TextStyle(
                      fontSize: 10,
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    height: (counts[i] / barMax) * 84,
                    decoration: BoxDecoration(
                      color: counts[i] > 0 ? palette.primary : palette.accent,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _dayLabel(today.subtract(Duration(days: 6 - i))),
                    style: TextStyle(
                      fontSize: 10,
                      color: i == 6 ? palette.primaryDark : palette.textSecondary,
                      fontWeight: i == 6 ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            if (i < 6) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  static String _dayLabel(DateTime day) {
    if (day.month == DateTime.now().month) return '周${kWeekdayNames[day.weekday - 1]}';
    return '${day.month}/${day.day}';
  }
}
