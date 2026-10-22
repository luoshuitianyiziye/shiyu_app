import 'dart:convert';

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
    this.mood = WhalePetMood.idle,
    this.line,
    this.fill = true,
    this.height = 300,
    this.onPoke,
    this.onReady,
    this.onError,
  });

  final WhalePetMood mood;

  /// 要显示的台词（通过 WebView 内气泡显示；null = 不说）
  final String? line;

  /// true = 填满父级；false = 固定高度
  final bool fill;
  final double height;
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
  }

  @override
  void didUpdateWidget(covariant WhalePetView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mood != widget.mood) {
      _applyMood();
    }
    if (oldWidget.line != widget.line) {
      _say(widget.line);
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
    final mood = switch (widget.mood) {
      WhalePetMood.thinking => 'thinking',
      WhalePetMood.happy => 'happy',
      WhalePetMood.sad => 'sad',
      WhalePetMood.idle => 'idle',
    };
    _call("window.petApi && window.petApi.setMood('$mood')");
  }

  void _say(String? text) {
    if (text == null) return;
    _call('window.petApi && window.petApi.say(${jsonEncode(text)})');
  }

  /// 触发一个动作词（如 'jump' / 'nod'）
  Future<void> doWord(String id) =>
      _call("window.petApi && window.petApi.doWord('$id')");

  @override
  Widget build(BuildContext context) {
    final web = WebViewWidget(controller: _controller);
    if (widget.fill) return web;
    return SizedBox(height: widget.height, width: double.infinity, child: web);
  }
}
