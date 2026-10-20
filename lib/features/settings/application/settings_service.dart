import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/providers.dart';
import '../../../core/backup/backup_service.dart';
import '../../../core/db/database.dart';
import '../../../core/db/db_providers.dart';
import '../../../core/notifications/notification_service.dart';

final settingsServiceProvider = Provider<SettingsService>(
  (ref) => SettingsService(ref),
);

/// 设置应用服务：封装「设置表写入 + 主题三写（notifier/prefs/DB）+ 系统通知重建」。
class SettingsService {
  SettingsService(this._ref);

  final Ref _ref;

  AppDatabase get _db => _ref.read(databaseProvider);

  /// 更新番茄/休息时长等设置
  Future<void> update({
    int? focusMinutes,
    int? shortBreakMinutes,
    int? longBreakMinutes,
  }) {
    return _db.updateSettings(
      focusMinutes: focusMinutes,
      shortBreakMinutes: shortBreakMinutes,
      longBreakMinutes: longBreakMinutes,
    );
  }

  /// 切换主题：notifier（立即生效）+ prefs（启动缓存）+ 设置表（单一事实来源）
  Future<void> selectTheme(String themeId) async {
    _ref.read(themeIdNotifierProvider).value = themeId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_id', themeId);
    await _db.updateSettings(themeId: themeId);
  }

  /// 更新每日收尾提醒时间，并用最新未完成数重建系统通知
  Future<void> updateEndOfDay({required int hour, required int minute}) async {
    await _db.updateSettings(endOfDayHour: hour, endOfDayMinute: minute);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final count = await _db.unfinishedCountForDate(today);
    await NotificationService.instance.scheduleDailyEndOfDay(
      hour: hour,
      minute: minute,
      unfinishedCount: count,
    );
  }

  /// 读取设置（确保设置行存在；供同步快照未就绪时的兜底使用）
  Future<SettingsRow> loadSettings() => _db.ensureSettings();

  /// 更新默认白噪音
  Future<void> updateWhiteNoise(String whiteNoiseId) =>
      _db.updateSettings(whiteNoiseId: whiteNoiseId);

  /// 导出备份到用户选择的位置（取消返回 false）
  Future<bool> exportBackup() => BackupService.exportToFile(_db);

  /// 从备份文件恢复（覆盖式），返回恢复摘要
  Future<String> restoreBackup(File file) async {
    final summary = await BackupService.restoreFromFile(_db, file);
    // 统计快照手动刷新（各列表由 drift watch 流自动刷新）
    _ref.invalidate(statsSnapshotProvider);
    return summary;
  }
}
