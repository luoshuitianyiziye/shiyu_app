import 'package:flutter/material.dart';

/// 白噪音轨道（素材已获授权；内置 4 首 + 用户自定义上传）
class WhiteNoiseTrack {
  const WhiteNoiseTrack({
    required this.id,
    required this.name,
    required this.asset,
    required this.icon,
    this.customPath,
  });

  final String id;
  final String name;
  final String asset;
  final IconData icon;

  /// 非空 = 用户上传的自定义音轨（本地文件路径）
  final String? customPath;

  bool get isCustom => customPath != null;
}

const List<WhiteNoiseTrack> kWhiteNoiseTracks = [
  WhiteNoiseTrack(
    id: 'rain',
    name: '雨声',
    asset: 'assets/audio/rain.mp3',
    icon: Icons.water_drop_outlined,
  ),
  WhiteNoiseTrack(
    id: 'ocean',
    name: '海浪',
    asset: 'assets/audio/ocean.mp3',
    icon: Icons.waves,
  ),
  WhiteNoiseTrack(
    id: 'fire',
    name: '篝火',
    asset: 'assets/audio/fire.mp3',
    icon: Icons.local_fire_department_outlined,
  ),
  WhiteNoiseTrack(
    id: 'wind',
    name: '风声',
    asset: 'assets/audio/wind.mp3',
    icon: Icons.air,
  ),
];

WhiteNoiseTrack whiteNoiseById(String id) => kWhiteNoiseTracks.firstWhere(
  (t) => t.id == id,
  orElse: () => kWhiteNoiseTracks.first,
);
