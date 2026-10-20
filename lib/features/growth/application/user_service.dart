import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/providers.dart';
import '../../../core/db/database.dart';
import '../../../core/db/db_providers.dart';

final userServiceProvider = Provider<UserService>((ref) => UserService(ref));

/// 用户应用服务：昵称修改与退出登录的三处状态（DB / prefs / notifier）收敛。
class UserService {
  UserService(this._ref);

  final Ref _ref;

  AppDatabase get _db => _ref.read(databaseProvider);

  /// 修改昵称：先写 DB（单一事实来源），成功后再写 prefs 与 notifier
  Future<void> updateNickname(String nickname) async {
    await _db.updateUserNickname(nickname);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nickname', nickname);
    _ref.read(nicknameNotifierProvider).value = nickname;
  }

  /// 退出登录：仅清除昵称登录态（本地数据保留）
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('nickname');
    _ref.read(nicknameNotifierProvider).value = null;
  }
}
