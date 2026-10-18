import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

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

  /// 番茄专注完成提醒（固定 id，调用方无需关心编号）
  Future<void> showPomodoroDone() => showNow(
        id: 888001,
        title: '专注完成',
        body: '干得漂亮！休息一下吧（+5 XP）',
      );

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
