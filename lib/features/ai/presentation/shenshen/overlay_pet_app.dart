import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/mascot_sounds.dart';
import 'shenshen_pet_view.dart';

/// 桌面悬浮窗里的桌宠 App（由 `overlayMain()` 启动）。
///
/// - 形象：ShenshenPetView（拖拽拎起/落地物理、漫步、点击互动）
/// - 长按形象：呼出菜单（隐藏桌宠 / 关闭桌宠）
/// - 窗口大小约 380x460 dp，默认右下角
class OverlayPetApp extends StatelessWidget {
  const OverlayPetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const _OverlayPetHome(),
    );
  }
}

class _OverlayPetHome extends StatefulWidget {
  const _OverlayPetHome();

  @override
  State<_OverlayPetHome> createState() => _OverlayPetHomeState();
}

class _OverlayPetHomeState extends State<_OverlayPetHome> {
  double _scale = 0.7;
  bool _soundOn = true;
  bool _menu = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _scale = (prefs.getDouble('ai_mascot_scale_v2') ?? 0.7).clamp(0.4, 1.2);
        _soundOn = prefs.getBool('ai_mascot_sound') ?? true;
      });
    } catch (_) {
      // 读取失败用默认值
    }
  }

  void _onTap() {
    if (_soundOn) MascotSounds.duck();
  }

  Future<void> _hide() async {
    try {
      await FlutterOverlayWindow.setOverlayVisible(visible: false);
    } catch (_) {}
    if (mounted) setState(() => _menu = false);
  }

  Future<void> _close() async {
    try {
      await FlutterOverlayWindow.closeOverlay();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: ShenshenPetView(
              scale: _scale,
              autoAction: true,
              onTap: _onTap,
              onLongPress: () => setState(() => _menu = true),
            ),
          ),
          if (_menu) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _menu = false),
                child: Container(color: Colors.black.withValues(alpha: 0.22)),
              ),
            ),
            Center(child: _menuCard()),
          ],
        ],
      ),
    );
  }

  Widget _menuCard() {
    return Container(
      width: 264,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F0E8),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '森森',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            '长按呼出菜单 · 点按互动 · 按住拖动',
            style: TextStyle(fontSize: 11, color: Colors.black54),
          ),
          const SizedBox(height: 10),
          _menuButton(Icons.visibility_off_outlined, '隐藏桌宠', _hide),
          _menuButton(Icons.close, '关闭桌宠', _close, danger: true),
          const SizedBox(height: 2),
          const Text(
            '隐藏后可到「时屿 → 设置 → AI 助手」重新呼出',
            style: TextStyle(fontSize: 10, color: Colors.black38),
          ),
        ],
      ),
    );
  }

  Widget _menuButton(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool danger = false,
  }) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(label, style: const TextStyle(fontSize: 14)),
      style: TextButton.styleFrom(
        foregroundColor: danger
            ? const Color(0xFFB0534B)
            : const Color(0xFF4C6B56),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      ),
    );
  }
}
