import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../../core/db/db_providers.dart';
import '../../../core/notifications/reminder_coordinator.dart';

final eventServiceProvider = Provider<EventService>((ref) => EventService(ref));

/// 日历事件应用服务：封装「DB 写入 + 当天提醒同步」的编排。
class EventService {
  EventService(this._ref);

  final Ref _ref;

  AppDatabase get _db => _ref.read(databaseProvider);

  /// 新建事件并调度提醒
  Future<int> create(
    EventsCompanion entry, {
    required String title,
    required DateTime remindAt,
  }) async {
    final id = await _db.addEvent(entry);
    await ReminderCoordinator.syncEventReminder(
      eventId: id,
      title: title,
      at: remindAt,
    );
    return id;
  }

  /// 编辑事件并重建提醒
  Future<void> update(
    int id,
    EventsCompanion entry, {
    required String title,
    required DateTime remindAt,
  }) async {
    await _db.updateEvent(id, entry);
    await ReminderCoordinator.syncEventReminder(
      eventId: id,
      title: title,
      at: remindAt,
    );
  }

  /// 软删除事件并取消提醒
  Future<void> delete(EventRow event) async {
    await _db.softDeleteEvent(event.id);
    await ReminderCoordinator.cancelEventReminder(event.id);
  }
}
