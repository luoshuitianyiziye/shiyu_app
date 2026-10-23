import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 形象控制句柄（供 Flutter 层触发动作/表情）
class WhalePetController extends ChangeNotifier {
  _WhalePetViewState? _state;

  void _attach(_WhalePetViewState state) => _state = state;

  void _detach(_WhalePetViewState state) {
    if (_state == state) _state = null;
  }

  Future<void> randomAction() async => _state?.randomAction();

  Future<void> dragged(bool on) async => _state?.dragged(on);

  Future<void> setExpr(String id, {double seconds = 1.5}) async =>
      _state?.setExpr(id, seconds: seconds);

  Future<void> doWord(String id) async => _state?.doWord(id);
}

/// 基于 WebView 的鲸鱼女仆 Live2D 形象（渲染器来自 Coopanion whale 形象包）。
///
/// 页面（assets/ai/whale/index.html）是自包含单文件：贴图 base64 内嵌、
/// 模型内联、kit 渲染器内联合并，因此无需网络、无 CORS 问题。
///
/// 与 Flutter 的桥：JS 通过 `WhaleBridge.postMessage(JSON)` 上报
/// ready / poke / error 事件。
class WhalePetView extends StatefulWidget {
  const WhalePetView({
    super.key,
    this.controller,
    this.mood = WhalePetMood.idle,
    this.line,
    this.fill = true,
    this.height = 300,
    this.scale = 1.0,
    this.skin = 'deepseek',
    this.autoAction = true,
    this.onPoke,
    this.onReady,
    this.onError,
  });

  final WhalePetController? controller;
  final WhalePetMood mood;

  /// 要显示的台词（通过 WebView 内气泡显示；null = 不说）
  final String? line;

  /// true = 填满父级；false = 固定高度
  final bool fill;
  final double height;

  /// 形象大小系数（窗口由父级控制时保持 1.0）
  final double scale;

  /// 皮肤 id：deepseek / harness / claude
  final String skin;

  /// 是否定时随机做小动作（让待机更灵动）
  final bool autoAction;
  final VoidCallback? onPoke;
  final VoidCallback? onReady;
  final void Function(String error)? onError;

  @override
  State<WhalePetView> createState() => _WhalePetViewState();
}

enum WhalePetMood { idle, thinking, happy, sad }

class _WhalePetViewState extends State<WhalePetView> {
  late final WebViewController _controller;
  Timer? _autoActionTimer;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'WhaleBridge',
        onMessageReceived: (msg) {
          final text = msg.message;
          if (text.contains('"ready"')) {
            _ready = true;
            _applyScale();
            _applySkin(initial: true);
            _applyMood();
            _say(widget.line);
            widget.onReady?.call();
          } else if (text.contains('"poke"')) {
            widget.onPoke?.call();
          } else if (text.contains('"error"')) {
            widget.onError?.call(text);
          }
        },
      )
      ..loadFlutterAsset('assets/ai/whale/index.html');
    _scheduleAutoAction();
  }

  @override
  void didUpdateWidget(covariant WhalePetView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
    if (oldWidget.mood != widget.mood) {
      _applyMood();
    }
    if (oldWidget.line != widget.line) {
      _say(widget.line);
    }
    if (oldWidget.scale != widget.scale) {
      _applyScale();
    }
    if (oldWidget.skin != widget.skin) {
      _applySkin();
    }
    if (oldWidget.autoAction != widget.autoAction) {
      _autoActionTimer?.cancel();
      _scheduleAutoAction();
    }
  }

  @override
  void dispose() {
    _autoActionTimer?.cancel();
    widget.controller?._detach(this);
    super.dispose();
  }

  /// 每 8~19 秒触发一次 kit 的随机小动作（待机灵动感）
  void _scheduleAutoAction() {
    if (!widget.autoAction) return;
    final delay = 8 + math.Random().nextInt(12);
    _autoActionTimer = Timer(Duration(seconds: delay), () {
      if (!mounted) return;
      if (_ready) _call('window.petApi && window.petApi.randomAction()');
      _scheduleAutoAction();
    });
  }

  Future<void> _call(String js) async {
    if (!_ready) return;
    try {
      await _controller.runJavaScript(js);
    } catch (_) {
      // 页面尚未就绪/已被销毁：忽略
    }
  }

  void _applyMood() {
    final mood = switch (widget.mood) {
      WhalePetMood.thinking => 'thinking',
      WhalePetMood.happy => 'happy',
      WhalePetMood.sad => 'sad',
      WhalePetMood.idle => 'idle',
    };
    _call("window.petApi && window.petApi.setMood('$mood')");
  }

  void _applyScale() {
    final value = widget.scale.clamp(0.3, 1.6);
    _call('window.petApi && window.petApi.setScale($value)');
  }

  void _applySkin({bool initial = false}) {
    final skin = widget.skin;
    if (initial && skin == 'deepseek') return; // 默认皮肤已加载
    _call("window.petApi && window.petApi.setScheme('$skin')");
  }

  void _say(String? text) {
    if (text == null) return;
    _call('window.petApi && window.petApi.say(${jsonEncode(text)})');
  }

  /// 触发一个动作词（如 'jump' / 'nod'）
  Future<void> doWord(String id) =>
      _call("window.petApi && window.petApi.doWord('$id')");

  /// 触发一次随机小动作
  Future<void> randomAction() =>
      _call('window.petApi && window.petApi.randomAction()');

  /// 设置表情（如 'happy' / 'surprised' / 'dragged'）
  Future<void> setExpr(String id, {double seconds = 1.5}) =>
      _call("window.petApi && window.petApi.setExpr('$id', $seconds)");

  /// 拖动开始/结束：被拎起表情 ↔ 恢复当前情绪
  Future<void> dragged(bool on) {
    if (on) return setExpr('dragged', seconds: 1.2);
    _applyMood();
    return Future.value();
  }

  @override
  Widget build(BuildContext context) {
    final web = WebViewWidget(controller: _controller);
    if (widget.fill) return web;
    return SizedBox(height: widget.height, width: double.infinity, child: web);
  }
}
