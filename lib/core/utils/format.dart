import 'package:flutter/material.dart';

/// 星期短名（周一为 1，index = weekday - 1）—— 今日页/日历页共用
const List<String> kWeekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

/// 时:分 两位补零格式化（如 9:5 → "09:05"）
String formatHm(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

/// 十六进制颜色字符串 → [Color]（支持 #RGB / #RRGGBB / #AARRGGBB；解析失败用 fallback）
Color parseHexColor(String hex, {Color fallback = const Color(0xFF9DBB9B)}) {
  var h = hex.replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(v);
}
