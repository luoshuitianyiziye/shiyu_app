import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/morandi_theme.dart';
import '../application/ai_providers.dart';
import '../data/ai_mascot_settings.dart';
import '../data/mascot_sounds.dart';
import 'shenshen/shenshen_pet_view.dart';

/// AI 助手页：帧动画桌宠（素材与行为方案来自参考项目 dsh-pet）。
///
/// - 待机时按概率决策：保持待机 / 转向 / 随机小动作 / 左右漫步
/// - 点击：随机点击回应动画 + 小黄鸭音效
/// - 按住拖动：被拎起（悬空动画），松手受重力下落、落地回弹
/// - 生成任务与聊天在「问答」页完成（AppBar 右侧入口）
class AiPage extends ConsumerStatefulWidget {
  const AiPage({super.key});

  @override
  ConsumerState<AiPage> createState() => _AiPageState();
}

class _AiPageState extends ConsumerState<AiPage> {
  void _onPoke() {
    final soundOn = ref.read(aiMascotSettingsProvider).soundOn;
    if (soundOn) MascotSounds.duck();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final mascot = ref.watch(aiMascotSettingsProvider);
    final config = ref.watch(aiConfigProvider).value;
    final configured = config?.isConfigured ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 助手'),
        actions: [
          if (!configured)
            IconButton(
              onPressed: () => context.push('/settings'),
              icon: const Icon(Icons.key_outlined),
              tooltip: '去配置 AI',
            ),
          IconButton(
            onPressed: () => context.push('/ai/chat'),
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: '问答',
          ),
          IconButton(
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'AI 设置',
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  palette.background,
                  palette.accent.withValues(alpha: 0.22),
                  palette.card,
                ],
              ),
            ),
          ),
          ShenshenPetView(
            scale: mascot.scale,
            autoAction: true,
            onTap: _onPoke,
          ),
        ],
      ),
    );
  }
}
