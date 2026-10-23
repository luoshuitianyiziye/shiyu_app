import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/morandi_theme.dart';
import '../application/ai_providers.dart';
import '../data/ai_mascot_settings.dart';
import 'ai_mascot.dart';

/// AI 助手页：全屏 Live2D 形象（点击互动 / 拖拽 / 自由活动）。
///
/// 生成任务与聊天统一在「问答」页完成（AppBar 右侧入口）。
class AiPage extends ConsumerStatefulWidget {
  const AiPage({super.key});

  @override
  ConsumerState<AiPage> createState() => _AiPageState();
}

class _AiPageState extends ConsumerState<AiPage> {
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
          AiMascot(
            scale: mascot.scale,
            skin: mascot.skin,
            soundOn: mascot.soundOn,
            showBubble: false,
          ),
        ],
      ),
    );
  }
}
