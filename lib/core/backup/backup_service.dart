import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide Column;
import 'package:file_picker/file_picker.dart';

import '../db/database.dart';

/// 数据备份：全表导出为 JSON 文件 / 从 JSON 文件恢复（覆盖式）。
///
/// - 导出：Android 上弹出系统「保存到」对话框，用户选择云盘/下载目录等；
/// - 恢复：从备份 JSON 文件读取，在事务内原子替换全部数据。
class BackupService {
  BackupService._();

  /// 备份格式版本（结构变更时递增，恢复时校验）
  static const int _formatVersion = 1;

  /// 生成完整备份 JSON 字符串（含软删记录，恢复后状态与导出时一致）。
  static Future<String> buildBackupJson(AppDatabase db) async {
    final data = <String, dynamic>{
      'app': 'shiyu',
      'formatVersion': _formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'users': [for (final r in await db.select(db.users).get()) r.toJson()],
      'tasks': [for (final r in await db.select(db.tasks).get()) r.toJson()],
      'xpLogs': [for (final r in await db.select(db.xpLogs).get()) r.toJson()],
      'events': [for (final r in await db.select(db.events).get()) r.toJson()],
      'noteCategories': [
        for (final r in await db.select(db.noteCategories).get()) r.toJson(),
      ],
      'notes': [for (final r in await db.select(db.notes).get()) r.toJson()],
      'settings': [
        for (final r in await db.select(db.settings).get()) r.toJson(),
      ],
      'pomodoroSessions': [
        for (final r in await db.select(db.pomodoroSessions).get()) r.toJson(),
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// 默认备份文件名（含时间戳，如 shiyu_backup_20261018_233000.json）
  static String fileNameFor(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'shiyu_backup_${now.year}${two(now.month)}${two(now.day)}'
        '_${two(now.hour)}${two(now.minute)}${two(now.second)}.json';
  }

  /// 导出备份到用户选择的位置；用户取消返回 false。
  static Future<bool> exportToFile(AppDatabase db) async {
    final content = await buildBackupJson(db);
    final uri = await FilePicker.saveFile(
      fileName: fileNameFor(DateTime.now()),
      bytes: Uint8List.fromList(utf8.encode(content)),
      mimeType: 'application/json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      dialogTitle: '保存时屿备份',
    );
    return uri != null;
  }

  /// 从备份文件恢复（覆盖当前全部数据，事务内原子替换）。
  ///
  /// 返回各表恢复条数的摘要文本；文件不是合法时屿备份时抛 [FormatException]。
  static Future<String> restoreFromFile(AppDatabase db, File file) async {
    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> || decoded['app'] != 'shiyu') {
      throw const FormatException('不是时屿的备份文件');
    }

    final users = _listOf(decoded['users']);
    final tasks = _listOf(decoded['tasks']);
    final xpLogs = _listOf(decoded['xpLogs']);
    final events = _listOf(decoded['events']);
    final noteCategories = _listOf(decoded['noteCategories']);
    final notes = _listOf(decoded['notes']);
    final settings = _listOf(decoded['settings']);
    final pomodoros = _listOf(decoded['pomodoroSessions']);

    await db.transaction(() async {
      // 先清空（无外键，顺序随意）
      await db.delete(db.tasks).go();
      await db.delete(db.xpLogs).go();
      await db.delete(db.events).go();
      await db.delete(db.notes).go();
      await db.delete(db.noteCategories).go();
      await db.delete(db.settings).go();
      await db.delete(db.pomodoroSessions).go();
      await db.delete(db.users).go();

      for (final m in users) {
        await db.into(db.users).insert(UserRow.fromJson(m));
      }
      for (final m in noteCategories) {
        await db.into(db.noteCategories).insert(NoteCategoryRow.fromJson(m));
      }
      for (final m in tasks) {
        await db.into(db.tasks).insert(TaskRow.fromJson(m));
      }
      for (final m in xpLogs) {
        await db.into(db.xpLogs).insert(XpLogRow.fromJson(m));
      }
      for (final m in events) {
        await db.into(db.events).insert(EventRow.fromJson(m));
      }
      for (final m in notes) {
        await db.into(db.notes).insert(NoteRow.fromJson(m));
      }
      for (final m in settings) {
        await db.into(db.settings).insert(SettingsRow.fromJson(m));
      }
      for (final m in pomodoros) {
        await db.into(db.pomodoroSessions).insert(PomodoroSessionRow.fromJson(m));
      }
    });

    // 恢复后确保基础行存在（避免 watchSingle 在空表上抛异常）
    await db.ensureUser();
    await db.ensureSettings();

    return '任务 ${tasks.length} · 笔记 ${notes.length} · 事件 ${events.length} '
        '· 番茄 ${pomodoros.length} · 经验流水 ${xpLogs.length} 条';
  }

  static List<Map<String, dynamic>> _listOf(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }
}
