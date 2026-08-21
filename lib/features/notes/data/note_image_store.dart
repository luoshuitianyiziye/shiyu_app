import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 笔记图片：选择 → 压缩 → 存到应用文档目录 → 返回本地路径
class NoteImageStore {
  /// 从相册选一张图片并压缩保存，返回本地路径；取消返回 null
  static Future<String?> pickAndSave() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
    );
    if (picked == null) return null;

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'note_images'));
    await dir.create(recursive: true);

    final target = p.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}.jpg');
    String? result;
    try {
      result = (await FlutterImageCompress.compressAndGetFile(
        picked.path,
        target,
        quality: 80,
        minWidth: 1600,
        minHeight: 1600,
      ))
          ?.path;
    } catch (_) {
      result = null;
    }
    if (result == null) {
      // 压缩失败：把原图复制到文档目录（不要直接引用相册/临时路径，
      // iOS 临时目录可能被系统回收导致持久化引用失效）
      try {
        final src = File(picked.path);
        if (await src.exists()) {
          await src.copy(target);
          result = target;
        }
      } catch (_) {
        result = null;
      }
    }
    if (result == null) return null;
    // 清理相册/缓存临时文件（Android cache / iOS tmp），避免缓存垃圾
    try {
      final src = File(picked.path);
      if (await src.exists() && src.path != result) {
        await src.delete();
      }
    } catch (_) {
      // 删除失败（可能被占用）忽略，不影响主流程
    }
    return result;
  }

  /// 删除本地图片文件（笔记删除图片附件时调用）
  static Future<void> deleteFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // 文件不存在等错误忽略
    }
  }
}
