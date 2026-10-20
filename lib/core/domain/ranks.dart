/// 九段位成长体系配置（领域规则，供 core 与 features 共用）。
///
/// 命名贴合「时屿」品牌（屿 = 岛，成长如登岛）。
/// 图片按文件序号 1..9 一一对应段位 1..9（已获授权）。
library;

class RankInfo {
  const RankInfo({
    required this.index,
    required this.name,
    required this.minLevel,
    required this.assetPath,
  });

  /// 段位序号 1-9
  final int index;
  final String name;

  /// 达到该段位所需的最小等级
  final int minLevel;
  final String assetPath;
}

/// 每 N 级晋一段
const int kRankLevelStep = 5;

const List<RankInfo> kRanks = [
  RankInfo(index: 1, name: '雾芽', minLevel: 1, assetPath: 'assets/ranks/1.jpeg'),
  RankInfo(index: 2, name: '浅湾', minLevel: 6, assetPath: 'assets/ranks/2.jpeg'),
  RankInfo(
    index: 3,
    name: '青屿',
    minLevel: 11,
    assetPath: 'assets/ranks/3.jpeg',
  ),
  RankInfo(
    index: 4,
    name: '竹林',
    minLevel: 16,
    assetPath: 'assets/ranks/4.jpeg',
  ),
  RankInfo(index: 5, name: '松风', minLevel: 21, assetPath: 'assets/ranks/5.jpg'),
  RankInfo(index: 6, name: '远山', minLevel: 26, assetPath: 'assets/ranks/6.png'),
  RankInfo(index: 7, name: '星河', minLevel: 31, assetPath: 'assets/ranks/7.png'),
  RankInfo(
    index: 8,
    name: '沧海',
    minLevel: 36,
    assetPath: 'assets/ranks/8.jpeg',
  ),
  RankInfo(
    index: 9,
    name: '时屿',
    minLevel: 41,
    assetPath: 'assets/ranks/9.jpeg',
  ),
];

/// 升到 level 级所需的累计经验：50 * L * (L+1)
int xpNeededForLevel(int level) => 50 * level * (level + 1);

/// 由累计经验推算等级
int levelFromXp(int xp) {
  var level = 1;
  while (xpNeededForLevel(level + 1) <= xp) {
    level++;
  }
  return level;
}

/// 由等级推算当前段位
RankInfo rankForLevel(int level) {
  var result = kRanks.first;
  for (final rank in kRanks) {
    if (level >= rank.minLevel) result = rank;
  }
  return result;
}

/// 已解锁的段位数量（段位墙进度）
int unlockedRankCount(int level) =>
    kRanks.where((r) => level >= r.minLevel).length;

/// 完成任务所得经验：基础 10 × 难度系数 × 象限系数
/// 难度：1 简单(0.5) 2 普通(1.0) 3 困难(2.0)；象限 I(1.5) 其余(1.0)
int taskXp({required int difficulty, required int quadrant}) {
  final diff = switch (difficulty) {
    1 => 0.5,
    3 => 2.0,
    _ => 1.0,
  };
  final quad = quadrant == 1 ? 1.5 : 1.0;
  return (10 * diff * quad).round();
}

/// 完成一个番茄专注所得经验
const int pomodoroXp = 5;
