import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../app/theme/morandi_theme.dart';
import '../../../core/db/db_providers.dart';
import '../../../core/feedback/feedback_debouncer.dart';
import '../../../core/notifications/notification_service.dart';
import '../../growth/data/ranks.dart';
import '../data/custom_noise.dart';
import '../data/white_noise.dart';

/// 番茄钟：专注 / 短休 / 长休 循环 + 白噪音
class FocusPage extends ConsumerStatefulWidget {
  const FocusPage({super.key});

  @override
  ConsumerState<FocusPage> createState() => _FocusPageState();
}

enum _Phase { focus, shortBreak, longBreak }

class _FocusPageState extends ConsumerState<FocusPage> {
  Timer? _timer;
  _Phase _phase = _Phase.focus;
  int _rounds = 0; // 已完成专注轮数
  bool _running = false;
  Duration _remaining = const Duration(minutes: 25);
  Duration _total = const Duration(minutes: 25);

  final AudioPlayer _player = AudioPlayer();
  WhiteNoiseTrack? _currentNoise;
  double _volume = 0.7;
  bool _noiseInitialized = false; // 首次点击「开始」时按设置自动播放默认白噪音
  bool _starting = false; // 防连点：_start 异步读设置期间忽略重复点击
  bool _completing = false; // 阶段结算防重入：倒计时归零瞬间与「跳过」互斥
  int _noiseOp = 0; // 白噪音操作代号：快速切换音轨时旧加载完成不覆盖新选择
  int _startEpoch = 0; // 开始代号：加载白噪音期间被重置/暂停则丢弃本次开始

  @override
  void dispose() {
    _timer?.cancel();
    _player.dispose();
    super.dispose();
  }

  // ---------- 计时（与白噪音联动）----------

  Future<void> _start() async {
    if (_running || _starting) return; // 防连点导致重复计时器/重复弹提示
    _starting = true;
    final epoch = ++_startEpoch; // 记录本次开始代号
    try {
      // 白噪音与番茄钟同步：开始/继续 → 白噪音播放
      await _syncNoise(started: true);
      if (!mounted) return;
      // 加载白噪音期间用户点了重置/暂停 → 丢弃本次异步结果，不再启动计时器
      if (epoch != _startEpoch || _running) return;
      setState(() => _running = true);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } finally {
      _starting = false;
    }
  }

  void _pause() {
    _timer?.cancel();
    // 白噪音同步暂停（保留选中音轨，继续后恢复）
    unawaited(_syncNoise(started: false));
    setState(() => _running = false);
  }

  void _reset() {
    _startEpoch++; // 使进行中的 _start 异步结果失效（不再启动计时器/播放）
    _timer?.cancel();
    if (_player.playing) unawaited(_player.pause());
    setState(() {
      _running = false;
      _remaining = _total;
    });
  }

  /// 白噪音与计时联动：开始/继续 → 播放；暂停 → 暂停。
  /// 首次开始直接读数据库设置，避免 StreamProvider 懒加载时 .value 为空导致不播放。
  Future<void> _syncNoise({required bool started}) async {
    if (!started) {
      if (_player.playing) unawaited(_player.pause());
      return;
    }
    if (_currentNoise != null) {
      // 已有选中音轨 → 继续播放（自定义文件若被删除，播放失败静默忽略）
      unawaited(_player.play().catchError((_) {}));
      return;
    }
    if (_noiseInitialized) return;
    final s = await ref.read(databaseProvider).ensureSettings();
    if (!mounted) return;
    // 读设置成功后才标记已初始化：若读取失败（异常/中途销毁），
    // 下次开始仍会重新尝试按设置自动播放默认音轨
    _noiseInitialized = true;
    if (s.whiteNoiseId != 'none') {
      if (s.whiteNoiseId.startsWith('custom:')) {
        // 默认音轨是用户上传的自定义音频
        final path = s.whiteNoiseId.substring('custom:'.length);
        final items = await ref.read(customNoiseProvider.future);
        if (!mounted) return;
        for (final item in items) {
          if (item.path == path) {
            await _playTrack(_customTrack(item));
            break;
          }
        }
      } else {
        await _playTrack(whiteNoiseById(s.whiteNoiseId));
      }
    }
  }

  Future<void> _tick() async {
    if (_remaining.inSeconds <= 1) {
      _timer?.cancel();
      // 归零瞬间先同步置 running=false，防止倒计时窗口内「跳过」重入
      setState(() => _running = false);
      await _onPhaseComplete();
      return;
    }
    if (!mounted) return;
    setState(() => _remaining -= const Duration(seconds: 1));
  }

  Future<void> _onPhaseComplete({bool award = true, bool skipped = false}) async {
    if (_completing) return; // 防重入：结算期间忽略再次调用
    _completing = true;
    try {
      await _doPhaseComplete(award: award, skipped: skipped);
    } finally {
      _completing = false;
    }
  }

  Future<void> _doPhaseComplete({bool award = true, bool skipped = false}) async {
    final completedPhase = _phase; // 记录完成的是哪个阶段（切换后判断会颠倒提示）
    final noise = _currentNoise;
    final wasPlaying = _player.playing;
    if (completedPhase == _Phase.focus) {
      // 专注完成：+5 XP + 通知 + 记录专注（统计用）；跳过不结算
      if (award) {
        await ref.read(databaseProvider).awardPomodoroXp(
          focusMinutes: _total.inMinutes,
        );
        await NotificationService.instance.showNow(
          id: 888001,
          title: '专注完成',
          body: '干得漂亮！休息一下吧（+5 XP）',
        );
        ref.invalidate(statsSnapshotProvider);
        // 轮次只在真实完成时推进（跳过不占轮次、不推进长休节奏）
        setState(() => _rounds += 1);
      }
      if (!mounted) return;
      setState(() {
        _phase = _rounds % 4 == 0 ? _Phase.longBreak : _Phase.shortBreak;
      });
    } else {
      if (!mounted) return;
      setState(() => _phase = _Phase.focus);
    }
    final durations = _durations();
    if (!mounted) return;
    setState(() {
      _total = Duration(minutes: _phase == _Phase.focus ? durations[0] : (_phase == _Phase.shortBreak ? durations[1] : durations[2]));
      _remaining = _total;
      _running = false;
    });
    // 休息开始时白噪音继续（未在播放时才补一次，避免 play() 阻塞）
    if (noise != null && wasPlaying && !_player.playing) {
      unawaited(_player.play());
    }
    if (mounted) {
      if (completedPhase == _Phase.focus) {
        if (award) {
          // 专注完成 +5 XP（合并提示，避免连续多个番茄频繁弹窗）
          FeedbackDebouncer.xp(context, pomodoroXp, action: '番茄完成', group: 'focus');
        } else {
          FeedbackDebouncer.toast(context, '已跳过本次专注，不结算经验', group: 'focus');
        }
      } else {
        // 区分「自然结束」与「手动跳过」，文案不再误导
        FeedbackDebouncer.toast(
          context,
          skipped ? '已跳过休息，开始下一个专注！' : '休息结束，开始下一个专注！',
          group: 'focus',
        );
      }
    }
  }

  /// [focus, shortBreak, longBreak] 分钟
  List<int> _durations() {
    final s = ref.read(settingsStreamProvider).value;
    return [
      s?.focusMinutes ?? 25,
      s?.shortBreakMinutes ?? 5,
      s?.longBreakMinutes ?? 15,
    ];
  }

  void _skip() {
    if (!_running || _completing) return; // 未在计时中/正在结算跳过无意义
    _timer?.cancel();
    _onPhaseComplete(award: false, skipped: true);
  }

  // ---------- 白噪音 ----------

  /// 自定义音轨的运行时对象（id 前缀 custom: 便于与内置音轨区分）
  WhiteNoiseTrack _customTrack(CustomNoiseItem item) => WhiteNoiseTrack(
        id: 'custom:${item.path}',
        name: item.name,
        asset: '',
        icon: Icons.audiotrack,
        customPath: item.path,
      );

  /// 播放指定音轨。
  /// 关键：just_audio 的 play() 返回的 Future 要等播放结束/停止才完成，
  /// 所以不能 await 它来更新 UI —— 先立即高亮图标，声音异步响起。
  /// 每次操作递增 [_noiseOp]：异步加载完成时若已不是最新操作（期间用户
  /// 又点了别的音轨/关闭），丢弃本次结果，避免 UI 高亮与实际播放脱节。
  Future<void> _playTrack(WhiteNoiseTrack track) async {
    final op = ++_noiseOp;
    setState(() => _currentNoise = track); // 立即更新图标/高亮
    try {
      if (track.isCustom) {
        await _player.setFilePath(track.customPath!);
      } else {
        await _player.setAsset(track.asset);
      }
      if (op != _noiseOp || !mounted) return; // 期间有更新的操作 → 丢弃
      await _player.setLoopMode(LoopMode.one);
      await _player.setVolume(_volume);
      unawaited(_player.play());
    } catch (_) {
      // 加载失败（含自定义文件被删除）：仅当仍是最新操作时回退未选中态
      if (op == _noiseOp && mounted && _currentNoise?.id == track.id) {
        setState(() => _currentNoise = null);
      }
    }
  }

  /// 点击音轨：未播放 → 播放；正在播放同一音轨 → 关闭（图标颜色随状态变化）
  Future<void> _toggleNoise(WhiteNoiseTrack track) async {
    final op = ++_noiseOp;
    if (_currentNoise?.id == track.id && _player.playing) {
      // 正在播放 → 关闭音效
      await _player.stop();
      if (op == _noiseOp && mounted) setState(() => _currentNoise = null);
      return;
    }
    await _playTrack(track);
  }

  Future<void> _stopNoise() async {
    final op = ++_noiseOp;
    await _player.stop();
    if (op == _noiseOp && mounted) setState(() => _currentNoise = null);
  }

  /// 选择并导入自定义白噪音音频，导入后立即播放
  Future<void> _uploadCustomNoise() async {
    final item = await CustomNoiseStore.pickAndAdd();
    if (item == null || !mounted) return;
    ref.invalidate(customNoiseProvider);
    await _playTrack(_customTrack(item));
  }

  /// 删除自定义音轨（正在播放则先停止）
  Future<void> _removeCustomNoise(CustomNoiseItem item) async {
    final track = _customTrack(item);
    if (_currentNoise?.id == track.id) {
      await _player.stop();
      if (mounted) setState(() => _currentNoise = null);
    }
    await CustomNoiseStore.remove(item.path);
    if (mounted) ref.invalidate(customNoiseProvider);
  }

  /// 自定义音轨的芯片（带删除小叉）
  Widget _buildCustomChip(CustomNoiseItem item) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final track = _customTrack(item);
    final active = _currentNoise?.id == track.id;
    return InputChip(
      avatar: Icon(
        active ? Icons.volume_up : Icons.audiotrack,
        size: 16,
        color: active ? palette.primaryDark : palette.textSecondary,
      ),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 110),
        child: Text(
          item.name,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            color: active ? palette.primaryDark : palette.textSecondary,
          ),
        ),
      ),
      selected: active,
      onSelected: (_) => _toggleNoise(track),
      onDeleted: () => _removeCustomNoise(item),
      selectedColor: palette.accent,
      deleteIconColor: palette.textSecondary,
    );
  }

  String get _timeText {
    final m = _remaining.inMinutes.toString().padLeft(2, '0');
    final s = (_remaining.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    // 保持设置流活跃（默认白噪音/番茄时长就绪；修复首次开始时 .value 为空）
    ref.watch(settingsStreamProvider);
    // 用户上传的自定义音轨（上传/删除后 invalidate 自动刷新）
    final customNoise = ref.watch(customNoiseProvider).value ?? const <CustomNoiseItem>[];
    final progress = _total.inSeconds == 0 ? 0.0 : _remaining.inSeconds / _total.inSeconds;
    final isFocus = _phase == _Phase.focus;

    return Scaffold(
      appBar: AppBar(title: const Text('专注')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          const SizedBox(height: 8),
          // 阶段标签 + 轮次
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                switch (_phase) {
                  _Phase.focus => '专注中',
                  _Phase.shortBreak => '短休息',
                  _Phase.longBreak => '长休息',
                },
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isFocus ? palette.primaryDark : palette.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '第 ${_phase == _Phase.longBreak ? 4 : (_rounds % 4) + 1}/4 轮',
                style: TextStyle(fontSize: 13, color: palette.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // 圆形进度
          Center(
            child: SizedBox(
              width: 260,
              height: 260,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 260,
                    height: 260,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 12,
                      strokeCap: StrokeCap.round,
                      backgroundColor: palette.accent,
                      color: isFocus ? palette.primary : palette.primaryDark,
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _timeText,
                        style: TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.bold,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: palette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _running ? '保持专注…' : '点击开始',
                        style: TextStyle(fontSize: 14, color: palette.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          // 控制按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                onPressed: _reset,
                icon: const Icon(Icons.replay),
                tooltip: '重置',
                style: IconButton.styleFrom(backgroundColor: palette.accent),
              ),
              const SizedBox(width: 24),
              FilledButton(
                onPressed: _running ? _pause : _start,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(120, 56),
                  backgroundColor: isFocus ? palette.primary : palette.primaryDark,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                ),
                child: Text(
                  _running ? '暂停' : '开始',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
              const SizedBox(width: 24),
              IconButton.filledTonal(
                onPressed: _skip,
                icon: const Icon(Icons.skip_next),
                tooltip: '跳过',
                style: IconButton.styleFrom(backgroundColor: palette.accent),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '每完成一个番茄 +5 XP',
              style: TextStyle(fontSize: 12, color: palette.textSecondary),
            ),
          ),
          const SizedBox(height: 28),
          // 白噪音
          Row(
            children: [
              Text(
                '白噪音',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '与番茄钟同步：开始播放 · 暂停时暂停',
                style: TextStyle(fontSize: 11, color: palette.textSecondary),
              ),
              const Spacer(),
              if (_currentNoise != null)
                TextButton.icon(
                  onPressed: _stopNoise,
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: const Text('停止'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...kWhiteNoiseTracks.map((track) {
                // 高亮 = 正在播放该音轨；图标颜色随播放状态变化
                final active = _currentNoise?.id == track.id;
                return ChoiceChip(
                  avatar: Icon(
                    active ? Icons.volume_up : track.icon,
                    size: 16,
                    color: active ? palette.primaryDark : palette.textSecondary,
                  ),
                  label: Text(track.name),
                  selected: active,
                  onSelected: (_) => _toggleNoise(track),
                  selectedColor: palette.accent,
                  labelStyle: TextStyle(
                    color: active ? palette.primaryDark : palette.textSecondary,
                  ),
                );
              }),
              for (final item in customNoise) _buildCustomChip(item),
              ActionChip(
                avatar: Icon(Icons.upload_file, size: 16, color: palette.primaryDark),
                label: const Text('上传音频'),
                onPressed: _uploadCustomNoise,
                backgroundColor: palette.accent.withValues(alpha: 0.3),
                side: BorderSide(color: palette.primaryDark.withValues(alpha: 0.4)),
                labelStyle: TextStyle(fontSize: 13, color: palette.primaryDark),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 音量
          Row(
            children: [
              Icon(Icons.volume_down, size: 18, color: palette.textSecondary),
              Expanded(
                child: Slider(
                  value: _volume,
                  min: 0,
                  max: 1,
                  activeColor: palette.primary,
                  inactiveColor: palette.accent,
                  onChanged: (v) {
                    setState(() => _volume = v);
                    _player.setVolume(v);
                  },
                ),
              ),
              Icon(Icons.volume_up, size: 18, color: palette.textSecondary),
            ],
          ),
        ],
      ),
    );
  }
}
