import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/morandi_theme.dart';
import '../application/ai_providers.dart';
import '../data/ai_mascot_settings.dart';
import '../data/mascot_sounds.dart';
import 'whale/whale_pet_view.dart';

/// AI 助手页：可拖动摆放的 Live2D 形象。
///
/// - 初始居中；拖动到任意位置后**停留原地**（不落地、不自动走动）
/// - 点击：小黄鸭音效 + 随机动作 + Q 弹反馈
/// - 待机：kit 自带的呼吸/眨眼/视线 + 定时随机小动作
/// - 生成任务与聊天在「问答」页完成（AppBar 右侧入口）
class AiPage extends ConsumerStatefulWidget {
  const AiPage({super.key});

  @override
  ConsumerState<AiPage> createState() => _AiPageState();
}

class _AiPageState extends ConsumerState<AiPage> {
  final _pet = WhalePetController();

  /// 形象窗口左上角（null = 初始居中）
  Offset? _pos;

  /// 点击 Q 弹进度（0~1）
  double _pulse = 0;

  @override
  void dispose() {
    _pet.dispose();
    super.dispose();
  }

  void _onPetTap() {
    final soundOn = ref.read(aiMascotSettingsProvider).soundOn;
    if (soundOn) MascotSounds.duck();
    _pet.randomAction();
    setState(() => _pulse = 1);
    Future<void>.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _pulse = 0);
    });
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
          // 窗口大小随「形象大小」设置（0.4~1.2 → 120~360 高）
          final winH = 300 * mascot.scale;
          final winW = winH * 0.8;
          final maxX = math.max(0.0, constraints.maxWidth - winW);
          final maxY = math.max(0.0, constraints.maxHeight - winH);
          final base =
              _pos ??
              Offset(
                (constraints.maxWidth - winW) / 2,
                constraints.maxHeight * 0.45 - winH / 2,
              );
          final left = base.dx.clamp(0.0, maxX);
          final top = base.dy.clamp(0.0, maxY);

          return Stack(
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
                left: left,
                top: top,
                width: winW,
                height: winH,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _onPetTap,
                  onPanStart: (_) {
                    _pet.dragged(true);
                  },
                  onPanUpdate: (details) {
                    setState(() {
                      _pos = Offset(
                        (left + details.delta.dx).clamp(0.0, maxX),
                        (top + details.delta.dy).clamp(0.0, maxY),
                      );
                    });
                  },
                  onPanEnd: (_) {
                    // 松手停留在当前位置（不落地）
                    _pet.dragged(false);
                  },
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: _pulse),
                    duration: const Duration(milliseconds: 130),
                    curve: Curves.easeOut,
                    builder: (context, p, child) {
                      return Transform.scale(
                        scaleY: 1 - 0.06 * p,
                        scaleX: 1 + 0.03 * p,
                        alignment: Alignment.bottomCenter,
                        child: child,
                      );
                    },
                    child: IgnorePointer(
                      child: WhalePetView(
                        controller: _pet,
                        skin: mascot.skin,
                        mood: WhalePetMood.idle,
                        autoAction: true,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
