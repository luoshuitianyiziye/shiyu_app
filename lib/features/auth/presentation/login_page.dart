import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/providers.dart';
import '../../../app/theme/morandi_theme.dart';

/// 昵称登录页（本地昵称，无密码；云账号绑定后续迭代）
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入昵称')),
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nickname', name);
    ref.read(nicknameNotifierProvider).value = name;
    // 路由 redirect 会自动跳转到主壳
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.eco_outlined, size: 72, color: palette.primary),
                const SizedBox(height: 16),
                Text(
                  '时屿',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: palette.primaryDark,
                    letterSpacing: 8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '日程笔记 · 番茄钟',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: palette.textSecondary),
                ),
                const SizedBox(height: 48),
                TextField(
                  controller: _controller,
                  maxLength: 16,
                  decoration: const InputDecoration(
                    hintText: '输入你的昵称',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('开始我的时屿', style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 16),
                Text(
                  '完成任务 · 专注番茄 · 解锁九段位',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: palette.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
