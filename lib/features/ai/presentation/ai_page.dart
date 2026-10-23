import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/morandi_theme.dart';
import '../application/ai_providers.dart';
import '../data/ai_mascot_settings.dart';
import '../data/mascot_sounds.dart';
import 'whale/whale_pet_view.dart';

/// AI 助手页：底部活动窗口里的 Live2D 桌宠。
///
/// - 形象初始居中（窗口底部中央）
/// - 待机时自己在窗口内来回走动、随机小动作（kit 原生 roam + 动画链）
/// - 按住拖动：被拎起（悬空表情），松手受重力下落、落地回弹（kit 原生物理）
/// - 点击：摸头反应 + 小黄鸭音效
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          // 活动窗口：宽度限制在 ~460*scale（保证 WebGL 渲染面积可控，真机流畅），
          // 高度 ~620*scale；形象占窗口高度 85%，可在窗口内走动/拖拽落地。
          final winH = 620 * mascot.scale;
          final winW = math.min(
            constraints.maxWidth,
            math.max(240.0, 460 * mascot.scale),
          );
          return Stack(
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
              Positioned(
                left: (constraints.maxWidth - winW) / 2,
                bottom: 0,
                width: winW,
                height: winH,
                child: WhalePetView(
                  scale: 1.0,
                  skin: mascot.skin,
                  autoAction: true,
                  onPoke: _onPoke,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
