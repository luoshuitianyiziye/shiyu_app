import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 自定义白噪音条目（用户上传的音频文件，存放在应用文档目录）
class CustomNoiseItem {
  const CustomNoiseItem({required this.path, required this.name});

  /// 应用文档目录内的绝对路径（当前会话有效，可直接用于播放）
  final String path;
  /// 显示名（原文件名去扩展名）
  final String name;

  Map<String, dynamic> toJson() => {'file': p.basename(path), 'name': name};
}

/// 自定义白噪音的存取：SharedPreferences 只记录**文件名**（不记绝对路径，
/// 避免 iOS 更新/重装、Android 换机恢复后文档目录路径变化导致清单全部失效），
/// 文件复制到 <应用文档>/custom_noise/ 下，读取时用当前目录重新拼接绝对路径。
class CustomNoiseStore {
  CustomNoiseStore._();

  static const _prefsKey = 'custom_noise_list';

  static Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'custom_noise'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 读取全部自定义音轨（自动清理已不存在的文件条目；坏条目逐条跳过）
  static Future<List<CustomNoiseItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return [];
    final dir = await _dir();
    final result = <CustomNoiseItem>[];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      for (final e in list) {
        try {
          final m = e as Map<String, dynamic>;
          final file = m['file'] as String?;
          final name = m['name'] as String?;
          // 兼容旧版存储（旧格式存的是绝对路径）：绝对路径直接使用
          final String path;
          if (file != null && !file.contains(Platform.pathSeparator)) {
            path = p.join(dir.path, file);
          } else {
            final legacy = m['path'] as String?;
            if (legacy == null || legacy.isEmpty) continue;
            path = legacy;
          }
          if (name != null && await File(path).exists()) {
            result.add(CustomNoiseItem(path: path, name: name));
          }
        } catch (_) {
          // 单条格式异常 → 跳过该条，保留其余合法条目
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<CustomNoiseItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode([for (final i in items) i.toJson()]),
    );
  }

  /// 选择音频文件并复制到应用文档目录；取消或失败返回 null。
  static Future<CustomNoiseItem?> pickAndAdd() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.audio);
      final srcPath = file?.path;
      if (srcPath == null) return null;
      final src = File(srcPath);
      if (!await src.exists()) return null;

      final dir = await _dir();
      final ext = p.extension(srcPath).toLowerCase();
      final name = p.basenameWithoutExtension(srcPath);
      final dest = File(
        p.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}$ext'),
      );
      await src.copy(dest.path);

      final item = CustomNoiseItem(path: dest.path, name: name);
      await _save([...await load(), item]);
      return item;
    } catch (_) {
      // 存储权限拒绝 / 文件不可读 / 复制失败等：返回 null 由调用方提示
      return null;
    }
  }

  /// 删除一条自定义音轨（文件 + 清单）
  static Future<void> remove(String path) async {
    final items = await load();
    await _save(items.where((i) => i.path != path).toList());
    try {
      final f = File(path);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {
      // 文件可能已被占用，忽略
    }
  }
}
