import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/db_providers.dart';
import '../../../core/notifications/notification_service.dart';

final focusServiceProvider = Provider<FocusService>((ref) => FocusService(ref));

/// 专注应用服务：番茄完成结算（XP + 流水 + 专注记录 + 通知 + 统计刷新）。
class FocusService {
  FocusService(this._ref);

  final Ref _ref;

  /// 完成一个番茄：结算经验并通知
  Future<void> awardPomodoro({required int focusMinutes}) async {
    await _ref
        .read(databaseProvider)
        .awardPomodoroXp(focusMinutes: focusMinutes);
    await NotificationService.instance.showPomodoroDone();
    _ref.invalidate(statsSnapshotProvider);
  }
}
