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
import '../../ai/data/ai_mascot_settings.dart';
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
            const _AiMascotSettingsCard(),
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

/// AI 助手设置卡片：启用开关 + 多配置管理（新增/编辑/删除/一键切换）+ 测试连接
class _AiSettingsCard extends ConsumerStatefulWidget {
  const _AiSettingsCard();

  @override
  ConsumerState<_AiSettingsCard> createState() => _AiSettingsCardState();
}

class _AiSettingsCardState extends ConsumerState<_AiSettingsCard> {
  AiConfig? _config;
  bool _busy = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await ref.read(aiConfigProvider.future);
    if (mounted) setState(() => _config = config);
  }

  Future<void> _persist(AiConfig next) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await next.save();
      ref.invalidate(aiConfigProvider);
      if (mounted) setState(() => _config = next);
    } catch (e) {
      if (mounted) FeedbackDebouncer.toast(context, '保存失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleEnabled(bool value) async {
    final config = _config;
    if (config == null) return;
    await _persist(config.copyWith(enabled: value));
  }

  Future<void> _switchTo(String id) async {
    final config = _config;
    if (config == null || config.activeId == id) return;
    await _persist(config.copyWith(activeId: id));
    if (mounted) FeedbackDebouncer.toast(context, '已切换 AI 配置');
  }

  Future<void> _addProfile() async {
    final config = _config;
    if (config == null) return;
    final created = await _openEditor(title: '新增配置');
    if (created == null || !mounted) return;
    final next = config.copyWith(
      profiles: [...config.profiles, created],
      activeId: config.profiles.isEmpty ? created.id : config.activeId,
    );
    await _persist(next);
  }

  Future<void> _editProfile(AiProfile profile) async {
    final config = _config;
    if (config == null) return;
    final edited = await _openEditor(title: '编辑配置', profile: profile);
    if (edited == null || !mounted) return;
    final next = config.copyWith(
      profiles: [
        for (final p in config.profiles) p.id == edited.id ? edited : p,
      ],
    );
    await _persist(next);
  }

  Future<AiProfile?> _openEditor({required String title, AiProfile? profile}) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    return showModalBottomSheet<AiProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AiProfileEditorSheet(title: title, profile: profile),
    );
  }

  Future<void> _deleteProfile(AiProfile profile) async {
    final config = _config;
    if (config == null) return;
    final ok = await showConfirmDialog(
      context,
      title: '删除配置',
      content: '删除「${profile.name}」后，其 API Key 也会从本机清除',
      confirmText: '删除',
      danger: true,
    );
    if (ok != true || !mounted) return;
    final remaining = [
      for (final p in config.profiles)
        if (p.id != profile.id) p,
    ];
    final nextActive = config.activeId == profile.id
        ? (remaining.isEmpty ? '' : remaining.first.id)
        : config.activeId;
    await _persist(config.copyWith(profiles: remaining, activeId: nextActive));
  }

  Future<void> _test() async {
    final profile = _config?.active;
    if (profile == null || profile.apiKey.isEmpty) {
      FeedbackDebouncer.toast(context, '请先添加配置并填写 API Key');
      return;
    }
    setState(() => _testing = true);
    try {
      await ref
          .read(aiClientProvider)
          .chatJson(
            profile: profile,
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
    final config = _config;

    if (config == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

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
              value: config.enabled,
              activeTrackColor: palette.primary,
              onChanged: _busy ? null : _toggleEnabled,
            ),
            if (config.profiles.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '还没有配置，点下面「添加配置」填写服务商与 API Key',
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
              )
            else
              for (final profile in config.profiles)
                _profileTile(profile, config.activeId == profile.id, palette),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.add_circle_outline,
                color: palette.primaryDark,
              ),
              title: const Text('添加配置'),
              subtitle: const Text('可添加多个服务商，随时一键切换'),
              onTap: _busy ? null : _addProfile,
            ),
            const SizedBox(height: 4),
            Text(
              'API Key 通过加密存储保存在本机；只有你输入的文本会发送给所选服务商。',
              style: TextStyle(fontSize: 11, color: palette.textSecondary),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _testing || config.active == null ? null : _test,
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering, size: 18),
                label: Text(_testing ? '测试中…' : '测试当前配置'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileTile(AiProfile profile, bool active, MorandiPalette palette) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: active ? palette.primaryDark : palette.outline,
        size: 22,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              profile.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: palette.textPrimary,
              ),
            ),
          ),
          if (active) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: palette.accent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '使用中',
                style: TextStyle(fontSize: 10, color: palette.primaryDark),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        '${profile.model} · ${profile.baseUrl}',
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: palette.textSecondary),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: _busy ? null : () => _editProfile(profile),
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: '编辑',
          ),
          IconButton(
            onPressed: _busy ? null : () => _deleteProfile(profile),
            icon: Icon(Icons.delete_outline, size: 18, color: palette.danger),
            tooltip: '删除',
          ),
        ],
      ),
      onTap: _busy || active ? null : () => _switchTo(profile.id),
    );
  }
}

/// 配置编辑弹层（新增/编辑共用）
class _AiProfileEditorSheet extends StatefulWidget {
  const _AiProfileEditorSheet({required this.title, this.profile});

  final String title;
  final AiProfile? profile;

  @override
  State<_AiProfileEditorSheet> createState() => _AiProfileEditorSheetState();
}

class _AiProfileEditorSheetState extends State<_AiProfileEditorSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _modelController;
  late final TextEditingController _keyController;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _nameController = TextEditingController(text: p?.name ?? '');
    _baseUrlController = TextEditingController(
      text: p?.baseUrl ?? AiConfig.defaultBaseUrl,
    );
    _modelController = TextEditingController(
      text: p?.model ?? AiConfig.defaultModel,
    );
    _keyController = TextEditingController(text: p?.apiKey ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      FeedbackDebouncer.toast(context, '给配置起个名字吧');
      return;
    }
    final baseUrl = _baseUrlController.text.trim();
    final model = _modelController.text.trim();
    if (baseUrl.isEmpty || model.isEmpty) {
      FeedbackDebouncer.toast(context, '请填写服务地址和模型');
      return;
    }
    final existing = widget.profile;
    Navigator.of(context).pop(
      AiProfile(
        id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        baseUrl: baseUrl,
        model: model,
        apiKey: _keyController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '配置名称',
                hintText: '例如：DeepSeek、OpenAI',
                isDense: true,
                prefixIcon: Icon(Icons.label_outline),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _baseUrlController,
              decoration: const InputDecoration(
                labelText: '服务地址',
                hintText: AiConfig.defaultBaseUrl,
                isDense: true,
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: '模型',
                hintText: AiConfig.defaultModel,
                isDense: true,
                prefixIcon: Icon(Icons.memory),
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
                prefixIcon: const Icon(Icons.key_outlined),
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
            const SizedBox(height: 12),
            Text(
              'Key 通过加密存储保存在本机；可以添加多个配置并在 AI 页一键切换。',
              style: TextStyle(fontSize: 11, color: palette.textSecondary),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                child: const Text('保存配置'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// AI 形象设置卡片：皮肤 / 大小 / 音效
class _AiMascotSettingsCard extends ConsumerWidget {
  const _AiMascotSettingsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final settings = ref.watch(aiMascotSettingsProvider);
    final notifier = ref.read(aiMascotSettingsProvider.notifier);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '形象皮肤',
              style: TextStyle(fontSize: 13, color: palette.textSecondary),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in AiMascotSettings.skins.entries)
                  ChoiceChip(
                    label: Text(
                      entry.value,
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: settings.skin == entry.key,
                    onSelected: (_) => notifier.setSkin(entry.key),
                    selectedColor: palette.accent,
                    labelStyle: TextStyle(
                      color: settings.skin == entry.key
                          ? palette.primaryDark
                          : palette.textSecondary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  '形象大小',
                  style: TextStyle(fontSize: 13, color: palette.textSecondary),
                ),
                const Spacer(),
                Text(
                  '${settings.scale.toStringAsFixed(1)}x',
                  style: TextStyle(fontSize: 12, color: palette.primaryDark),
                ),
              ],
            ),
            Slider(
              value: settings.scale,
              min: 0.4,
              max: 1.2,
              divisions: 16,
              activeColor: palette.primary,
              onChanged: notifier.previewScale,
              onChangeEnd: notifier.setScale,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('音效'),
              subtitle: const Text('点击形象时播放小黄鸭音效'),
              value: settings.soundOn,
              activeTrackColor: palette.primary,
              onChanged: notifier.setSoundOn,
            ),
          ],
        ),
      ),
    );
  }
}
