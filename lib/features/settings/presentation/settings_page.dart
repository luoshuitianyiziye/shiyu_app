import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/morandi_theme.dart';
import '../../../app/widgets/morandi_picker.dart';
import '../../../app/widgets/morandi_time_picker.dart';
import '../../../core/ai/ai_client.dart';
import '../../../core/ai/ai_config.dart';
import '../../../core/db/database.dart';
import '../../../core/db/db_providers.dart';
import '../../../core/feedback/feedback_debouncer.dart';
import '../../../core/storage/custom_noise.dart';
import '../../../core/utils/confirm_dialog.dart';
import '../../../core/utils/format.dart';
import '../../ai/application/ai_providers.dart';
import '../../focus/data/white_noise.dart';
import '../application/settings_service.dart';

/// 设置页：番茄钟参数 / 每日收尾提醒时间 / 默认白噪音
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final settingsAsync = ref.watch(settingsStreamProvider);
    final customNoise =
        ref.watch(customNoiseProvider).value ?? const <CustomNoiseItem>[];

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (s) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ===== 番茄钟参数 =====
            const _GroupTitle('番茄钟参数'),
            Card(
              child: Column(
                children: [
                  _StepperRow(
                    icon: Icons.timer_outlined,
                    label: '专注时长',
                    value: s.focusMinutes,
                    min: 15,
                    max: 60,
                    step: 5,
                    onChanged: (v) => ref
                        .read(settingsServiceProvider)
                        .update(focusMinutes: v),
                  ),
                  _Divider(palette),
                  _StepperRow(
                    icon: Icons.self_improvement_outlined,
                    label: '短休息',
                    value: s.shortBreakMinutes,
                    min: 5,
                    max: 20,
                    step: 5,
                    onChanged: (v) => ref
                        .read(settingsServiceProvider)
                        .update(shortBreakMinutes: v),
                  ),
                  _Divider(palette),
                  _StepperRow(
                    icon: Icons.bedtime_outlined,
                    label: '长休息',
                    value: s.longBreakMinutes,
                    min: 10,
                    max: 40,
                    step: 5,
                    onChanged: (v) => ref
                        .read(settingsServiceProvider)
                        .update(longBreakMinutes: v),
                  ),
                ],
              ),
            ),
            const _Hint(text: '每完成一个番茄 +5 XP · 每 4 个番茄进入一次长休息'),

            // ===== 提醒 =====
            const _GroupTitle('提醒'),
            Card(
              child: ListTile(
                onTap: () => _pickEndOfDayTime(context, ref, s),
                leading: Icon(
                  Icons.notifications_outlined,
                  color: palette.primaryDark,
                  size: 26,
                ),
                title: const Text('每日收尾提醒'),
                subtitle: const Text('每天固定时间提醒未完成任务'),
                trailing: Text(
                  formatHm(s.endOfDayHour, s.endOfDayMinute),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: palette.primaryDark,
                  ),
                ),
              ),
            ),
            const _Hint(text: '点击时间可修改，修改后系统通知会同步更新'),

            // ===== 白噪音 =====
            const _GroupTitle('白噪音'),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.graphic_eq,
                          color: palette.primaryDark,
                          size: 26,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '默认白噪音',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: palette.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '首次开始专注时自动播放',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: palette.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    MorandiOptionField(
                      icon: Icons.music_note_outlined,
                      label: '音轨',
                      valueText: _noiseLabel(s.whiteNoiseId, customNoise),
                      onTap: () => _pickDefaultNoise(
                        context,
                        ref,
                        s.whiteNoiseId,
                        customNoise,
                      ),
                      dense: true,
                    ),
                  ],
                ),
              ),
            ),

            // ===== AI 助手 =====
            const _GroupTitle('AI 助手'),
            const _AiSettingsCard(),

            // ===== 数据备份 =====
            const _GroupTitle('数据备份'),
            const _BackupCard(),

            // ===== 关于 =====
            const _GroupTitle('关于'),
            const Card(
              child: ListTile(
                leading: Icon(Icons.auto_awesome_outlined, size: 26),
                title: Text('时屿'),
                subtitle: Text('版本 1.0.0 · 数据保存在本机'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// 选择每日收尾提醒时间并重新调度系统通知
  Future<void> _pickEndOfDayTime(
    BuildContext context,
    WidgetRef ref,
    SettingsRow s,
  ) async {
    final picked = await showMorandiTimePicker(
      context: context,
      initial: TimeOfDay(hour: s.endOfDayHour, minute: s.endOfDayMinute),
      title: '收尾提醒时间',
      titleIcon: Icons.nightlight_outlined,
    );
    if (picked == null || !context.mounted) return;

    // 更新时间并用最新未完成数重建系统通知（编排在 SettingsService 内）
    await ref
        .read(settingsServiceProvider)
        .updateEndOfDay(hour: picked.hour, minute: picked.minute);
    if (context.mounted) {
      FeedbackDebouncer.toast(
        context,
        '收尾提醒已设为每天 ${formatHm(picked.hour, picked.minute)}',
      );
    }
  }

  /// 默认白噪音显示名（含自定义音轨）
  static String _noiseLabel(String id, List<CustomNoiseItem> custom) {
    if (id == 'none') return '不自动播放';
    for (final t in kWhiteNoiseTracks) {
      if (t.id == id) return t.name;
    }
    if (id.startsWith('custom:')) {
      final path = id.substring('custom:'.length);
      for (final c in custom) {
        if (c.path == path) return c.name;
      }
    }
    return kWhiteNoiseTracks.first.name;
  }

  /// 选择默认白噪音（莫兰迪小窗，与重复规则/分类一致，含自定义音轨）
  Future<void> _pickDefaultNoise(
    BuildContext context,
    WidgetRef ref,
    String current,
    List<CustomNoiseItem> custom,
  ) async {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final picked = await showMorandiPicker<String>(
      context: context,
      title: '默认白噪音',
      titleIcon: Icons.graphic_eq,
      selected: current,
      items: [
        for (final t in kWhiteNoiseTracks)
          PickerItem(value: t.id, label: t.name, icon: t.icon),
        for (final c in custom)
          PickerItem(
            value: 'custom:${c.path}',
            label: c.name,
            icon: Icons.audiotrack,
            color: palette.primaryDark,
          ),
        const PickerItem(
          value: 'none',
          label: '不自动播放',
          icon: Icons.notifications_off_outlined,
        ),
      ],
    );
    if (picked != null && picked != current) {
      await ref.read(settingsServiceProvider).updateWhiteNoise(picked);
      if (context.mounted) {
        FeedbackDebouncer.toast(context, '默认白噪音已更新', group: 'settings');
      }
    }
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
          color: palette.textSecondary,
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: palette.textSecondary),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider(this.palette);

  final MorandiPalette palette;

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, indent: 54, color: palette.accent);
  }
}

/// 加减步进行：专注/休息时长
class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: palette.primaryDark, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 15, color: palette.textPrimary),
            ),
          ),
          IconButton(
            onPressed: value > min ? () => onChanged(value - step) : null,
            icon: const Icon(Icons.remove_circle_outline),
            color: palette.textSecondary,
            tooltip: '减少',
          ),
          SizedBox(
            width: 34,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: palette.textPrimary,
              ),
            ),
          ),
          Text(
            '分钟',
            style: TextStyle(fontSize: 12, color: palette.textSecondary),
          ),
          IconButton(
            onPressed: value < max ? () => onChanged(value + step) : null,
            icon: const Icon(Icons.add_circle_outline),
            color: palette.textSecondary,
            tooltip: '增加',
          ),
        ],
      ),
    );
  }
}

/// 数据备份卡片：导出 JSON 备份文件 / 从备份恢复（覆盖式）
class _BackupCard extends ConsumerStatefulWidget {
  const _BackupCard();

  @override
  ConsumerState<_BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends ConsumerState<_BackupCard> {
  bool _busy = false;

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await ref.read(settingsServiceProvider).exportBackup();
      if (!mounted) return;
      if (ok) {
        FeedbackDebouncer.toast(context, '备份已导出，恢复时选择该文件即可');
      }
    } catch (e) {
      if (mounted) FeedbackDebouncer.toast(context, '导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
      dialogTitle: '选择时屿备份文件',
    );
    if (picked == null || !mounted) return;
    final ok = await showConfirmDialog(
      context,
      title: '恢复备份',
      content: '将从「${picked.name}」恢复数据，当前全部数据会被覆盖。确定继续？',
      confirmText: '恢复',
      danger: true,
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final path = picked.path;
      if (path == null) throw const FormatException('无法读取所选文件');
      final summary = await ref
          .read(settingsServiceProvider)
          .restoreBackup(File(path));
      if (mounted) {
        FeedbackDebouncer.toast(context, '恢复成功：$summary');
      }
    } catch (e) {
      if (mounted) FeedbackDebouncer.toast(context, '恢复失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              Icons.upload_file_outlined,
              color: palette.primaryDark,
              size: 26,
            ),
            title: const Text('导出备份'),
            subtitle: const Text('保存为 JSON 文件，可放到云盘/聊天工具长期保存'),
            trailing: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _busy ? null : _export,
          ),
          Divider(height: 1, indent: 56, color: palette.accent),
          ListTile(
            leading: Icon(
              Icons.download_outlined,
              color: palette.primaryDark,
              size: 26,
            ),
            title: const Text('从备份恢复'),
            subtitle: const Text('选择备份文件恢复（会覆盖当前全部数据）'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy ? null : _restore,
          ),
        ],
      ),
    );
  }
}

/// AI 助手设置卡片：启用开关 / 服务地址 / 模型 / API Key / 测试连接 / 保存
class _AiSettingsCard extends ConsumerStatefulWidget {
  const _AiSettingsCard();

  @override
  ConsumerState<_AiSettingsCard> createState() => _AiSettingsCardState();
}

class _AiSettingsCardState extends ConsumerState<_AiSettingsCard> {
  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController();
  final _keyController = TextEditingController();
  bool _enabled = false;
  bool _obscure = true;
  bool _saving = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await ref.read(aiConfigProvider.future);
    if (!mounted) return;
    setState(() {
      _enabled = config.enabled;
      _baseUrlController.text = config.baseUrl;
      _modelController.text = config.model;
      _keyController.text = config.apiKey;
    });
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _modelController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  AiConfig _currentConfig() => AiConfig(
        enabled: _enabled,
        baseUrl: _baseUrlController.text.trim(),
        model: _modelController.text.trim(),
        apiKey: _keyController.text.trim(),
      );

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _currentConfig().save();
      ref.invalidate(aiConfigProvider);
      if (mounted) FeedbackDebouncer.toast(context, 'AI 设置已保存');
    } catch (e) {
      if (mounted) FeedbackDebouncer.toast(context, '保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test() async {
    if (_testing) return;
    final config = _currentConfig();
    if (!config.isConfigured) {
      FeedbackDebouncer.toast(context, '请先填写服务地址、模型与 API Key');
      return;
    }
    setState(() => _testing = true);
    try {
      await ref.read(aiClientProvider).chatJson(
            config: config,
            systemPrompt: '你是测试助手，只回复 JSON：{"ok":true}',
            userPrompt: '测试连接',
          );
      if (mounted) FeedbackDebouncer.toast(context, '连接成功，AI 配置可用');
    } on AiException catch (e) {
      if (mounted) FeedbackDebouncer.toast(context, '连接失败：${e.message}');
    } catch (e) {
      if (mounted) FeedbackDebouncer.toast(context, '连接失败：$e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用 AI 助手'),
              subtitle: const Text('今日页「✨」按钮打开 AI 助手'),
              value: _enabled,
              activeTrackColor: palette.primary,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _baseUrlController,
              decoration: const InputDecoration(
                labelText: '服务地址',
                hintText: AiConfig.defaultBaseUrl,
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: '模型',
                hintText: AiConfig.defaultModel,
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _keyController,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: '在服务商控制台创建',
                isDense: true,
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Key 通过加密存储保存在本机；只有你输入的文本会发送给所选服务商。',
              style: TextStyle(fontSize: 11, color: palette.textSecondary),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _testing ? null : _test,
                    icon: _testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_tethering, size: 18),
                    label: Text(_testing ? '测试中…' : '测试连接'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('保存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
