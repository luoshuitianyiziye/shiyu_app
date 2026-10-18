import 'dart:convert';

/// 导入文本的自动切分（纯函数，UI 与测试共用同一实现）。
///
/// 识别规则（贴合密码管理器/清单的粘贴习惯）：
/// - 文本**含空行**：以空行分段，每段为一条（段内换行保留，适合长条目）；
/// - 文本**不含空行**：每行一条（适合「账号 密码」这类一行一条的清单）；
/// - `---`/`===`/`***` 等分隔线同样视为条目边界；
/// - 条目首尾空白裁剪，空条目丢弃。
List<String> splitImportText(String raw) {
  final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');
  final hasBlank = lines.any((l) => l.trim().isEmpty);
  final entries = <String>[];

  if (!hasBlank) {
    // 每行一条
    for (final line in lines) {
      final t = line.trim();
      if (t.isEmpty || _isSeparator(t)) continue;
      entries.add(t);
    }
    return entries;
  }

  // 空行分段
  final buffer = StringBuffer();
  void flush() {
    final v = buffer.toString().trim();
    if (v.isNotEmpty) entries.add(v);
    buffer.clear();
  }

  for (final line in lines) {
    final t = line.trim();
    if (t.isEmpty || _isSeparator(t)) {
      flush();
      continue;
    }
    if (buffer.isNotEmpty) buffer.write('\n');
    buffer.write(t);
  }
  flush();
  return entries;
}

/// 分隔线识别：3 个及以上的 - = * _ — ~ 组成
bool _isSeparator(String line) =>
    RegExp(r'^[-=*_—~]{3,}$').hasMatch(line);

/// 由条目列表构造笔记正文（Quill Delta JSON）：
/// 每条一段、条目之间用一个空段落分隔，阅读与搜索命中都更清晰。
String buildEntriesBody(List<String> entries) {
  final ops = <Map<String, dynamic>>[];
  for (var i = 0; i < entries.length; i++) {
    if (i > 0) ops.add({'insert': '\n'}); // 空段落分隔
    ops.add({'insert': entries[i]});
    ops.add({'insert': '\n'}); // 段落结束
  }
  if (ops.isEmpty) ops.add({'insert': '\n'});
  return jsonEncode(ops);
}
