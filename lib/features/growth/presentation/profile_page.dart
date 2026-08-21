import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/providers.dart';
import '../../../app/theme/morandi_theme.dart';
import '../../../core/db/db_providers.dart';
import '../data/ranks.dart';

/// 个人资料页：头像（当前段位图）/ 昵称修改 / 成长信息 / 退出登录
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  late final TextEditingController _nicknameController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final nickname = ref.read(nicknameNotifierProvider).value ?? '';
    _nicknameController = TextEditingController(text: nickname);
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _saveNickname() async {
    final name = _nicknameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('昵称不能为空')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      // 先写 DB（单一事实来源），成功后再写 prefs/更新 notifier，
      // 避免 DB 失败时 prefs 已改导致重启后状态分叉
      await ref.read(databaseProvider).updateUserNickname(name);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('nickname', name);
      ref.read(nicknameNotifierProvider).value = name;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('昵称已更新')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _logout() async {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后数据仍保留在本机，重新输入昵称即可回来'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: palette.danger),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('nickname');
    ref.read(nicknameNotifierProvider).value = null;
    // router redirect 会自动跳转登录页
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final userAsync = ref.watch(userStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('个人资料')),
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (user) {
          final level = levelFromXp(user.xpTotal);
          final rank = rankForLevel(level);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 头像 + 昵称
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(40),
                        child: Image.asset(
                          rank.assetPath,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          cacheWidth: 160,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Lv.$level · ${rank.name}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: palette.primaryDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${user.xpTotal} XP · 连续 ${user.streakDays} 天',
                        style: TextStyle(fontSize: 12, color: palette.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // 昵称修改
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '昵称',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: palette.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _nicknameController,
                        maxLength: 16,
                        decoration: const InputDecoration(
                          hintText: '输入新昵称',
                          prefixIcon: Icon(Icons.person_outline),
                          counterText: '',
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _saveNickname(),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _saving ? null : _saveNickname,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: Text(_saving ? '保存中…' : '保存昵称'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // 成长信息
              Card(
                child: Column(
                  children: [
                    _InfoRow(
                      icon: Icons.stars_outlined,
                      label: '当前段位',
                      value: rank.name,
                    ),
                    _divider(palette),
                    _InfoRow(
                      icon: Icons.local_fire_department_outlined,
                      label: '连续打卡',
                      value: '${user.streakDays} 天',
                    ),
                    _divider(palette),
                    _InfoRow(
                      icon: Icons.task_alt_outlined,
                      label: '加入时屿',
                      value: DateFormat('yyyy年M月d日', 'zh_CN').format(user.createdAt),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // 退出登录
              Card(
                child: ListTile(
                  onTap: _logout,
                  leading: Icon(Icons.logout, color: palette.danger, size: 26),
                  title: Text(
                    '退出登录',
                    style: TextStyle(color: palette.danger, fontSize: 15),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  '时屿 v1.0.0',
                  style: TextStyle(fontSize: 11, color: palette.textSecondary),
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _divider(MorandiPalette palette) {
    return Divider(height: 1, indent: 56, color: palette.accent);
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;

    return ListTile(
      leading: Icon(icon, color: palette.primaryDark, size: 24),
      title: Text(label, style: TextStyle(fontSize: 14, color: palette.textSecondary)),
      trailing: Text(
        value,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: palette.textPrimary,
        ),
      ),
    );
  }
}
