import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../../core/db/db_providers.dart';
import '../data/note_body.dart';
import '../data/note_image_store.dart';

final noteServiceProvider = Provider<NoteService>((ref) => NoteService(ref));

/// 笔记应用服务：封装「DB 写入 + 图片文件清理 + 分类管理」的编排。
class NoteService {
  NoteService(this._ref);

  final Ref _ref;

  AppDatabase get _db => _ref.read(databaseProvider);

  /// 新建笔记，返回新笔记 id
  Future<int> create(NotesCompanion entry) => _db.addNote(entry);

  /// 更新笔记
  Future<void> update(int id, NotesCompanion entry) =>
      _db.updateNote(id, entry);

  /// 软删除笔记，并清理正文内嵌图片的本地文件
  Future<void> delete(NoteRow note) async {
    await _db.softDeleteNote(note.id);
    for (final path in extractImagePaths(note.body)) {
      await NoteImageStore.deleteFile(path);
    }
  }

  /// 新建分类
  Future<int> addCategory(String name) => _db.addNoteCategory(name);

  /// 重命名分类
  Future<void> renameCategory(int id, String name) =>
      _db.updateNoteCategory(id, name: name);

  /// 删除分类（该分类下笔记变为未分类）
  Future<void> deleteCategory(int id) => _db.deleteNoteCategory(id);
}
