// 生成「时屿 · 日程笔记」莫兰迪风格应用图标
//
// 设计：雾绿渐变圆角底 + 白色钟面（时间）+ 时针分针（莫兰迪深绿）
//       + 底部两道波浪（岛屿/水面）→ 呼应「时屿 = 时间 × 岛屿」
//
// 运行：flutter test tool/icon_generator_test.dart
// 输出：build/icon_out/ic_launcher_<size>.png（48/72/96/144/192）
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('生成各密度应用图标', () async {
    const sizes = [48, 72, 96, 144, 192];
    final outDir = Directory('build/icon_out');
    if (!outDir.existsSync()) outDir.createSync(recursive: true);

    for (final size in sizes) {
      final png = await _renderIcon(size);
      final f = File('${outDir.path}/ic_launcher_$size.png');
      f.writeAsBytesSync(png);
      // ignore: avoid_print
      print('wrote ${f.path} (${png.length} bytes)');
    }

    // 自适应图标前景：432×432 透明底，图形居中在安全区（中心 66%）
    final fg = await _renderForeground(432);
    final fgFile = File('${outDir.path}/ic_launcher_foreground.png');
    fgFile.writeAsBytesSync(fg);
    // ignore: avoid_print
    print('wrote ${fgFile.path} (${fg.length} bytes)');
  });
}

/// 自适应图标前景：透明背景，白色钟面 + 指针 + 波浪，图形位于中心安全区
Future<List<int>> _renderForeground(int size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final s = size.toDouble();

  // 图形整体置于中心 66% 安全区内
  final scale = s * 0.62 / s;
  canvas.scale(scale, scale);
  canvas.translate(s * (1 - scale) / 2 / scale, s * (1 - scale) / 2 / scale);

  // 1) 白色钟面（圆）
  final center = Offset(s * 0.5, s * 0.45);
  final radius = s * 0.235;
  canvas.drawCircle(center, radius, Paint()..color = Colors.white);

  // 2) 表盘刻度（4 个小点：3/6/9/12 位）
  final tickPaint = Paint()
    ..color = const Color(0xFF8FAC87).withValues(alpha: 0.6);
  for (var i = 0; i < 4; i++) {
    final angle = i * 1.5707963; // 90° 步进
    final tickCenter = center +
        Offset(
          (radius * 0.72) * _cos(angle),
          (radius * 0.72) * _sin(angle),
        );
    canvas.drawCircle(tickCenter, s * 0.018, tickPaint);
  }

  // 3) 时针（10 点方向）+ 分针（2 点方向），柔和深绿圆头
  final handPaint = Paint()
    ..color = const Color(0xFF6E8F6C)
    ..strokeWidth = s * 0.032
    ..strokeCap = StrokeCap.round;
  canvas.drawLine(
    center,
    center +
        Offset(
          radius * 0.42 * _cos(-1.0472),
          radius * 0.42 * _sin(-1.0472),
        ),
    handPaint,
  );
  canvas.drawLine(
    center,
    center +
        Offset(
          radius * 0.62 * _cos(1.0472),
          radius * 0.62 * _sin(1.0472),
        ),
    handPaint,
  );
  canvas.drawCircle(center, s * 0.028, Paint()..color = const Color(0xFF6E8F6C));

  // 4) 底部波浪（两道白色弧线）
  final wavePaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.9)
    ..style = PaintingStyle.stroke
    ..strokeWidth = s * 0.035
    ..strokeCap = StrokeCap.round;
  final waveTop = s * 0.80;
  for (var i = 0; i < 2; i++) {
    final y = waveTop + i * s * 0.085;
    final path = Path()
      ..moveTo(s * 0.26, y)
      ..quadraticBezierTo(s * 0.38, y - s * 0.05, s * 0.50, y)
      ..quadraticBezierTo(s * 0.62, y + s * 0.05, s * 0.74, y);
    canvas.drawPath(path, wavePaint);
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

Future<List<int>> _renderIcon(int size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final s = size.toDouble();

  // 1) 圆角渐变背景（清淡雾绿：更浅更亮）
  final rect = Rect.fromLTWH(0, 0, s, s);
  final rrect = RRect.fromRectAndRadius(rect, Radius.circular(s * 0.22));
  canvas.clipRRect(rrect);
  final bgPaint = Paint()
    ..shader = ui.Gradient.linear(
      Offset(0, 0),
      Offset(s, s),
      const [Color(0xFFCFE0C6), Color(0xFFAFC9A6)],
    );
  canvas.drawRect(rect, bgPaint);

  // 2) 底部波浪（两道白色弧线，象征水面/岛屿）
  final wavePaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.9)
    ..style = PaintingStyle.stroke
    ..strokeWidth = s * 0.035
    ..strokeCap = StrokeCap.round;
  final waveTop = s * 0.80;
  for (var i = 0; i < 2; i++) {
    final y = waveTop + i * s * 0.085;
    final path = Path()
      ..moveTo(s * 0.26, y)
      ..quadraticBezierTo(s * 0.38, y - s * 0.05, s * 0.50, y)
      ..quadraticBezierTo(s * 0.62, y + s * 0.05, s * 0.74, y);
    canvas.drawPath(path, wavePaint);
  }

  // 3) 白色钟面（圆）
  final center = Offset(s * 0.5, s * 0.45);
  final radius = s * 0.235;
  canvas.drawCircle(center, radius, Paint()..color = Colors.white);

  // 4) 表盘刻度（4 个小点：3/6/9/12 位）
  final tickPaint = Paint()
    ..color = const Color(0xFF8FAC87).withValues(alpha: 0.6);
  for (var i = 0; i < 4; i++) {
    final angle = i * 1.5707963; // 90° 步进
    final tickCenter = center +
        Offset(
          (radius * 0.72) * _cos(angle),
          (radius * 0.72) * _sin(angle),
        );
    canvas.drawCircle(tickCenter, s * 0.018, tickPaint);
  }

  // 5) 时针（指向 10 点方向）+ 分针（指向 2 点方向），柔和深绿圆头
  final handPaint = Paint()
    ..color = const Color(0xFF6E8F6C)
    ..strokeWidth = s * 0.032
    ..strokeCap = StrokeCap.round;
  // 时针（10 点 ≈ 300°，cos 正、sin 负）
  canvas.drawLine(
    center,
    center +
        Offset(
          radius * 0.42 * _cos(-1.0472),
          radius * 0.42 * _sin(-1.0472),
        ),
    handPaint,
  );
  // 分针（2 点 ≈ 60°）
  canvas.drawLine(
    center,
    center +
        Offset(
          radius * 0.62 * _cos(1.0472),
          radius * 0.62 * _sin(1.0472),
        ),
    handPaint,
  );
  // 中心轴
  canvas.drawCircle(center, s * 0.028, Paint()..color = const Color(0xFF6E8F6C));

  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

double _cos(double rad) => math.cos(rad);
double _sin(double rad) => math.sin(rad);
