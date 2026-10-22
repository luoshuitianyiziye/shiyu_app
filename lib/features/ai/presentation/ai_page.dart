import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/morandi_theme.dart';
import '../../../core/ai/ai_client.dart';
import '../../../core/ai/ai_config.dart';
import '../application/ai_providers.dart';
import '../application/ai_service.dart';
import '../data/task_draft.dart';
import 'ai_draft_list.dart';
import 'ai_mascot.dart';

/// AI 助手页面：Q 版形象 + 自然语言生成任务（预览确认后批量创建）
class AiPage extends ConsumerStatefulWidget {
  const AiPage({super.key});

  @override
  ConsumerState<AiPage> createState() => _AiPageState();
}

class _AiPageState extends ConsumerState<AiPage> {
  final _inputController = TextEditingController();
  bool _loading = false;
  List<TaskDraft> _drafts = [];
  String? _error;
  int _ignored = 0;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  AiMascotMood get _mood {
    if (_loading) return AiMascotMood.thinking;
    if (_error != null) return AiMascotMood.sad;
    if (_drafts.isNotEmpty) return AiMascotMood.happy;
    return AiMascotMood.idle;
  }

  Future<void> _generate() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _ignored = 0;
    });
    try {
      final result = await ref
          .read(aiServiceProvider)
          .generateTasks(_inputController.text);
      if (!mounted) return;
      setState(() {
        _drafts = result.drafts;
        _ignored = result.ignored;
        if (result.drafts.isEmpty) {
          _error = '没有识别到任务，换个说法再试试？';
        }
      });
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '出错了：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fillExample(String text) {
    _inputController.text = text;
    _inputController.selection = TextSelection.collapsed(offset: text.length);
    setState(() {});
  }

  /// 当前 AI 配置（点击一键切换）
  Widget _profileChip(MorandiPalette palette, AiConfig config) {
    final active = config.active;
    return ActionChip(
      avatar: Icon(Icons.hub_outlined, size: 16, color: palette.primaryDark),
      label: Text(
        config.profiles.length > 1
            ? '${active?.name ?? '未配置'} · 点击切换'
            : (active?.name ?? '未配置'),
        style: const TextStyle(fontSize: 11),
      ),
      backgroundColor: palette.card,
      side: BorderSide(color: palette.outline),
      onPressed: () => _switchProfile(config),
    );
  }

  Future<void> _switchProfile(AiConfig config) async {
    if (config.profiles.length <= 1) {
      // 只有一套配置：直接去设置里管理
      if (mounted) context.push('/settings');
      return;
    }
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: palette.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                '切换 AI 配置',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: palette.textPrimary,
                ),
              ),
            ),
            for (final p in config.profiles)
              ListTile(
                leading: Icon(
                  p.id == config.activeId
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: p.id == config.activeId
                      ? palette.primaryDark
                      : palette.outline,
                  size: 22,
                ),
                title: Text(p.name),
                subtitle: Text(
                  p.model,
                  style: TextStyle(fontSize: 11, color: palette.textSecondary),
                ),
                trailing: p.id == config.activeId
                    ? Text(
                        '使用中',
                        style: TextStyle(
                          fontSize: 11,
                          color: palette.primaryDark,
                        ),
                      )
                    : null,
                onTap: () => Navigator.of(ctx).pop(p.id),
              ),
            ListTile(
              leading: Icon(
                Icons.settings_outlined,
                color: palette.primaryDark,
              ),
              title: const Text('管理配置'),
              onTap: () {
                Navigator.of(ctx).pop();
                if (mounted) context.push('/settings');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || picked == config.activeId || !mounted) return;
    await config.copyWith(activeId: picked).save();
    ref.invalidate(aiConfigProvider);
    if (!mounted) return;
    setState(() {});
    final name = config.profiles.firstWhere((p) => p.id == picked).name;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已切换到 $name')));
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final config = ref.watch(aiConfigProvider).value;
    final configured = config?.isConfigured ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 助手'),
        actions: [
          IconButton(
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'AI 设置',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Center(child: AiMascot(mood: _mood)),
            const SizedBox(height: 6),
            if (config != null && config.profiles.isNotEmpty)
              Center(child: _profileChip(palette, config)),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _inputController,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        hintText: '例如：明天下午 3 点写周报\n或粘贴一段待办/会议文字，让 AI 帮你拆成任务',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _exampleChip('明天下午 3 点写周报', palette),
                        _exampleChip('把「准备期末考试」拆成任务', palette),
                        _exampleChip('整理待办：买牛奶、交话费、预约体检', palette),
                        _exampleChip('帮我排下周一到周五每天 1 小时复习', palette),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _loading ? null : _generate,
                        icon: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.auto_awesome, size: 18),
                        label: Text(_loading ? 'AI 正在思考…' : '让 AI 帮我生成'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!configured) ...[
              const SizedBox(height: 10),
              _banner(
                palette,
                icon: Icons.key_outlined,
                text: '还没有配置 AI：去设置里填写 API Key 后就能使用啦',
                actionLabel: '去设置',
                onTap: () => context.push('/settings'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              _banner(
                palette,
                icon: Icons.error_outline,
                text: _error!,
                danger: true,
                actionLabel: '重试',
                onTap: _loading ? null : _generate,
              ),
            ],
            if (_drafts.isNotEmpty) ...[
              const SizedBox(height: 16),
              if (_ignored > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '（已忽略 $_ignored 条 AI 返回的格式异常内容）',
                    style: TextStyle(
                      fontSize: 11,
                      color: palette.textSecondary,
                    ),
                  ),
                ),
              AiDraftList(
                key: ObjectKey(_drafts),
                drafts: _drafts,
                onAdded: () => setState(() => _drafts = []),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _exampleChip(String text, MorandiPalette palette) {
    return ActionChip(
      label: Text(text, style: const TextStyle(fontSize: 11)),
      backgroundColor: palette.accent.withValues(alpha: 0.35),
      side: BorderSide(color: palette.outline),
      onPressed: () => _fillExample(text),
    );
  }

  Widget _banner(
    MorandiPalette palette, {
    required IconData icon,
    required String text,
    String? actionLabel,
    VoidCallback? onTap,
    bool danger = false,
  }) {
    final color = danger ? palette.danger : palette.primaryDark;
    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: 12, color: palette.textPrimary),
              ),
            ),
            if (actionLabel != null)
              TextButton(
                onPressed: onTap,
                child: Text(actionLabel, style: TextStyle(color: color)),
              ),
          ],
        ),
      ),
    );
  }
}
