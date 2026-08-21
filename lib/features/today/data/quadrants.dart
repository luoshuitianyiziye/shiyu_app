/// 四象限定义
class QuadrantInfo {
  const QuadrantInfo(this.id, this.name, this.motto);

  final int id;
  final String name;
  final String motto;
}

const List<QuadrantInfo> kQuadrants = [
  QuadrantInfo(1, '重要紧急', '立即去做'),
  QuadrantInfo(2, '重要不紧急', '制定计划'),
  QuadrantInfo(3, '紧急不重要', '授权他人'),
  QuadrantInfo(4, '不重要不紧急', '尽量不做'),
];

QuadrantInfo quadrantById(int id) =>
    kQuadrants.firstWhere((q) => q.id == id, orElse: () => kQuadrants[0]);
