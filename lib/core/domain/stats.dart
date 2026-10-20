import 'package:flutter/material.dart';

/// 统计快照（专注 + 任务汇总），供「我的」页、统计页与成就页共用。
/// 领域模型：core 层提供，features 只消费。
class StatsSnapshot {
  const StatsSnapshot({
    required this.totalPomodoros,
    required this.totalMinutes,
    required this.weekPomodoros,
    required this.weekMinutes,
    required this.last7Days,
    required this.totalTasksDone,
    required this.streakDays,
    required this.rankIndex,
    required this.todayTotal,
    required this.todayDone,
  });

  /// 累计番茄数
  final int totalPomodoros;

  /// 累计专注分钟数
  final int totalMinutes;

  /// 本周（周一起）番茄数
  final int weekPomodoros;

  /// 本周专注分钟数
  final int weekMinutes;

  /// 最近 7 天（含今天）每日番茄数，索引 0 = 6 天前
  final List<int> last7Days;

  /// 累计完成任务数
  final int totalTasksDone;

  /// 连续打卡天数
  final int streakDays;

  /// 当前段位（1-9，1 基）
  final int rankIndex;

  /// 今日任务总数
  final int todayTotal;

  /// 今日已完成数
  final int todayDone;

  double get todayRate => todayTotal == 0 ? 0 : todayDone / todayTotal;
}

/// 成就定义
class Achievement {
  const Achievement({
    required this.id,
    required this.name,
    required this.desc,
    required this.icon,
    required this.target,
    required this.current,
    this.specialUnlocked = false,
  });

  final String id;
  final String name;
  final String desc;
  final IconData icon;

  /// 目标值
  final int target;

  /// 当前进度值（由快照计算）
  final int current;

  /// 特殊解锁条件（如达到最高段位），满足时视为已解锁
  final bool specialUnlocked;

  bool get unlocked => specialUnlocked || current >= target;

  double get progress => (current / target).clamp(0.0, 1.0).toDouble();
}

/// 根据统计快照生成成就列表
List<Achievement> buildAchievements(StatsSnapshot s) => [
  Achievement(
    id: 'first',
    name: '初试锋芒',
    desc: '完成第 1 个任务',
    icon: Icons.emoji_events_outlined,
    target: 1,
    current: s.totalTasksDone,
  ),
  Achievement(
    id: 'tasks100',
    name: '勤学不辍',
    desc: '累计完成 100 个任务',
    icon: Icons.fact_check_outlined,
    target: 100,
    current: s.totalTasksDone,
  ),
  Achievement(
    id: 'streak7',
    name: '七日之约',
    desc: '连续打卡满 7 天',
    icon: Icons.local_fire_department_outlined,
    target: 7,
    current: s.streakDays,
  ),
  Achievement(
    id: 'pomo10',
    name: '初窥门径',
    desc: '累计 10 个番茄',
    icon: Icons.timer_outlined,
    target: 10,
    current: s.totalPomodoros,
  ),
  Achievement(
    id: 'pomo50',
    name: '专注达人',
    desc: '累计 50 个番茄',
    icon: Icons.bolt_outlined,
    target: 50,
    current: s.totalPomodoros,
  ),
  Achievement(
    id: 'pomo100',
    name: '千锤百炼',
    desc: '累计 100 个番茄',
    icon: Icons.military_tech_outlined,
    target: 100,
    current: s.totalPomodoros,
  ),
  Achievement(
    id: 'minutes1000',
    name: '心流大师',
    desc: '累计专注 1000 分钟',
    icon: Icons.auto_awesome_outlined,
    target: 1000,
    current: s.totalMinutes,
  ),
  Achievement(
    id: 'rank9',
    name: '登峰造极',
    desc: '解锁第九段位「时屿」',
    icon: Icons.workspace_premium_outlined,
    target: 9,
    current: s.rankIndex,
    specialUnlocked: s.rankIndex >= 9,
  ),
];
