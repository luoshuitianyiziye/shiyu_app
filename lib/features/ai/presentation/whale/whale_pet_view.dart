import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
    this.height = 300,
    this.mood = WhalePetMood.idle,
    this.onPoke,
    this.onReady,
    this.onError,
  });

  final double height;
  final WhalePetMood mood;
  final VoidCallback? onPoke;
  final VoidCallback? onReady;
  final void Function(String error)? onError;

  @override
  State<WhalePetView> createState() => _WhalePetViewState();
}

enum WhalePetMood { idle, thinking, happy, sad }

class _WhalePetViewState extends State<WhalePetView> {
  late final WebViewController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'WhaleBridge',
        onMessageReceived: (msg) {
          final text = msg.message;
          if (text.contains('"ready"')) {
            _ready = true;
            _applyMood();
            widget.onReady?.call();
          } else if (text.contains('"poke"')) {
            widget.onPoke?.call();
          } else if (text.contains('"error"')) {
            widget.onError?.call(text);
          }
        },
      )
      ..loadFlutterAsset('assets/ai/whale/index.html');
  }

  @override
  void didUpdateWidget(covariant WhalePetView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mood != widget.mood) {
      _applyMood();
    }
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
    switch (widget.mood) {
      case WhalePetMood.thinking:
        _call('window.petApi && window.petApi.setThinking(true)');
      case WhalePetMood.happy:
        _call('window.petApi && window.petApi.setThinking(false)');
        _call("window.petApi && window.petApi.setExpr('happy', 2.5)");
      case WhalePetMood.sad:
        _call('window.petApi && window.petApi.setThinking(false)');
        _call("window.petApi && window.petApi.setExpr('sad', 2.5)");
      case WhalePetMood.idle:
        _call('window.petApi && window.petApi.setThinking(false)');
    }
  }

  /// 供父组件调用：说出一个动作/表情（如 'surprised'）
  Future<void> poke() =>
      _call("window.petApi && window.petApi.setExpr('surprised', 1.2)");

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: WebViewWidget(controller: _controller),
    );
  }
}
