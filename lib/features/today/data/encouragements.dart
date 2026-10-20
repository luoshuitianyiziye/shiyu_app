import 'dart:math' as math;

/// 今日复盘鼓励文案（本地预置，不调用 AI）。
///
/// 按今日完成情况分档挑选，点击卡片上的按钮可「换一句」。
class Encouragements {
  Encouragements._();

  /// 今日无任务
  static const noTasks = [
    '今天还没有任务，先定一个小目标吧～',
    '空空的今日页，等你来填满～',
    '慢慢来，先写下一件想做的事',
  ];

  /// 今日全部完成
  static const allDone = [
    '全部完成，今天超棒的！',
    '今日任务清零，奖励自己一下吧～',
    '效率满分，继续保持！',
    '一天辛苦啦，好好休息～',
  ];

  /// 完成过半
  static const overHalf = ['已经完成一大半了，再加把劲！', '进展不错，收个尾就完美了～', '就差一点点了，你可以的！'];

  /// 刚起步 / 完成少量
  static const started = ['开始了就是胜利，慢慢来～', '每完成一件，都离目标更近一步', '不着急，专注眼前这一件'];

  /// 本周有番茄专注
  static const pomodoro = ['专注的样子最可爱，继续保持～', '番茄一个接一个，状态在线！', '今天的专注时光很珍贵～'];

  /// 连续打卡
  static const streak = ['连续打卡好多天啦，坚持得真好～', '每天的坚持都在积累，继续加油！'];

  /// 根据今日统计挑一句；[previous] 用于避免连续两次相同
  static String pick({
    required int todayDone,
    required int todayTotal,
    required int weekPomodoros,
    required int streakDays,
    String? previous,
  }) {
    final pool = <String>[];
    if (todayTotal <= 0) {
      pool.addAll(noTasks);
    } else if (todayDone >= todayTotal) {
      pool.addAll(allDone);
    } else if (todayDone * 2 >= todayTotal) {
      pool.addAll(overHalf);
    } else {
      pool.addAll(started);
    }
    if (weekPomodoros > 0) pool.addAll(pomodoro);
    if (streakDays >= 3) pool.addAll(streak);
    if (pool.isEmpty) return '今天也辛苦了～';

    final random = math.Random();
    var result = pool[random.nextInt(pool.length)];
    var attempts = 0;
    while (result == previous && pool.length > 1 && attempts < 5) {
      result = pool[random.nextInt(pool.length)];
      attempts++;
    }
    return result;
  }
}
