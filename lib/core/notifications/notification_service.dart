import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../db/database.dart';

/// 任务列表变化（新增/完成/恢复/删除）后调用：用最新未完成数重建每日收尾提醒。
///
/// 并发安全：连续快速变化（如连点完成多个任务）时多个调用交错执行，
/// 用单调递增版本号做 last-write-wins —— 只有最新一次调用的结果会被保留，
/// 旧的（可能读取到过期计数）结果会被丢弃。
Future<void> rescheduleEndOfDay(AppDatabase db) async {
  final version = ++_endOfDayVersion;
  final s = await db.ensureSettings();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final count = await db.unfinishedCountForDate(today);
  // 已有更新的重建请求 → 本次结果过期，丢弃（避免旧计数覆盖新计数）
  if (version != _endOfDayVersion) return;
  await NotificationService.instance.scheduleDailyEndOfDay(
    hour: s.endOfDayHour,
    minute: s.endOfDayMinute,
    unfinishedCount: count,
  );
}

/// 收尾提醒重建版本号（last-write-wins 串行化用）
int _endOfDayVersion = 0;

/// 本地通知服务：任务开始提醒 / 事件当天提醒 / 每日收尾提醒
///
/// 平台注意：
/// - Android 需在 Manifest 声明权限与接收器，并在 build.gradle.kts 开启 desugaring
/// - iOS 单 App 待发通知上限 64 条：目前任务/事件提醒直接逐条调度，
///   超限后系统会静默丢弃新增的本地通知（待办：实现「未来 7 天滚动窗口」
///   或提醒数量上限控制后再上架 iOS）
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const int _endOfDayId = 999001;
  static const int _taskIdBase = 100000;
  static const int _eventIdBase = 200000;

  /// 初始化：加载时区、创建渠道、请求权限
  Future<void> init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
    );

    // 设置设备本地时区（用于 zonedSchedule 精确触发）
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // 取不到时区时保持默认（UTC），提醒时间可能偏移，但不会崩溃
    }
    _initialized = true;

    // 权限
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  bool get initialized => _initialized;

  /// 任务开始提醒（id = 基础值 + 任务 id）
  Future<void> scheduleTaskReminder({
    required int taskId,
    required String title,
    required DateTime at,
  }) async {
    if (!_initialized) return;
    if (at.isBefore(DateTime.now())) return;
    await _plugin.zonedSchedule(
      id: _taskIdBase + taskId,
      title: '任务开始',
      body: '「$title」时间到啦，开始专注吧',
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: _taskDetails('task', '任务提醒'),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// 取消任务提醒
  Future<void> cancelTaskReminder(int taskId) async {
    if (!_initialized) return;
    await _plugin.cancel(id: _taskIdBase + taskId);
  }

  /// 事件当天提醒（id = 基础值 + 事件 id）
  Future<void> scheduleEventReminder({
    required int eventId,
    required String title,
    required DateTime at,
  }) async {
    if (!_initialized) return;
    if (at.isBefore(DateTime.now())) return;
    await _plugin.zonedSchedule(
      id: _eventIdBase + eventId,
      title: '重要事件',
      body: '「$title」就是今天',
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: _taskDetails('event', '事件提醒'),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// 取消事件提醒
  Future<void> cancelEventReminder(int eventId) async {
    if (!_initialized) return;
    await _plugin.cancel(id: _eventIdBase + eventId);
  }

  /// 立即展示一条通知（番茄完成等）
  Future<void> showNow({required int id, required String title, required String body}) async {
    if (!_initialized) return;
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: _taskDetails('pomodoro', '番茄钟'),
    );
  }

  /// 每日收尾提醒：每天固定时间提醒未完成任务（[unfinishedCount] 实时数量）
  Future<void> scheduleDailyEndOfDay({
    required int hour,
    required int minute,
    required int unfinishedCount,
  }) async {
    if (!_initialized) return;
    final body = unfinishedCount > 0
        ? '今日还有 $unfinishedCount 个任务未完成，来收个尾吧～'
        : '今天辛苦了，明天继续加油～';
    await _plugin.zonedSchedule(
      id: _endOfDayId,
      title: '时屿 · 今日收尾',
      body: body,
      scheduledDate: _nextInstanceOf(hour, minute),
      notificationDetails: _taskDetails('endofday', '每日收尾提醒'),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  NotificationDetails _taskDetails(String channelId, String channelName) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: '时屿提醒',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(),
    );
  }

  /// 下一个指定时刻（用于每日重复）
  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
