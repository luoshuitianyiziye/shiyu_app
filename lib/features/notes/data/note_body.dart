import 'dart:convert';

/// 从 Delta JSON 中提取本地图片路径列表（缩略图 / 清理用）
List<String> extractImagePaths(String bodyJson) {
  if (bodyJson.isEmpty) return [];
  try {
    final delta = jsonDecode(bodyJson) as List;
    final paths = <String>[];
    for (final op in delta) {
      final data = (op as Map)['insert'];
      if (data is Map && data.containsKey('image')) {
        final url = data['image'] as String;
        if (url.startsWith('file://')) {
          paths.add(Uri.decodeComponent(url.substring('file://'.length)));
        }
      }
    }
    return paths;
  } catch (_) {
    return [];
  }
}

/// 本地文件 → quill 可存储的 URL
String localFileUrl(String path) => 'file://${path.replaceAll('\\', '/')}';
