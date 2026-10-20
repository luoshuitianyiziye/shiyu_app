import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 莫兰迪语义色板 —— 所有主题同构一套 token，新增主题 = 加一份配置。
@immutable
class MorandiPalette extends ThemeExtension<MorandiPalette> {
  const MorandiPalette({
    required this.background,
    required this.card,
    required this.primary,
    required this.primaryDark,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.danger,
    required this.surfaceVariant,
    required this.outline,
    required this.success,
    required this.gold,
  });

  /// 页面底色
  final Color background;

  /// 卡片底色
  final Color card;

  /// 主色
  final Color primary;

  /// 深主色（按钮/强调文字）
  final Color primaryDark;

  /// 浅强调色（进度条底色、选中指示）
  final Color accent;

  /// 正文
  final Color textPrimary;

  /// 次要文字
  final Color textSecondary;

  /// 警示（未完成提醒、删除）
  final Color danger;

  /// 次级容器底（输入框、分组卡片底）
  final Color surfaceVariant;

  /// 卡片描边 / 分隔线
  final Color outline;

  /// 达成/成功（成就、完成率）
  final Color success;

  /// 经验/奖励点缀（XP、晋级、段位）
  final Color gold;

  /// 是否为深色主题：以背景亮度判断（墨夜背景深 → true，其余浅色背景 → false）
  bool get isDark => background.computeLuminance() < 0.3;

  /// 系统状态栏/导航栏样式（透明状态栏 + 图标颜色随主题）
  SystemUiOverlayStyle get overlayStyle => SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: background,
    systemNavigationBarIconBrightness: isDark
        ? Brightness.light
        : Brightness.dark,
  );

  @override
  MorandiPalette copyWith({
    Color? background,
    Color? card,
    Color? primary,
    Color? primaryDark,
    Color? accent,
    Color? textPrimary,
    Color? textSecondary,
    Color? danger,
    Color? surfaceVariant,
    Color? outline,
    Color? success,
    Color? gold,
  }) {
    return MorandiPalette(
      background: background ?? this.background,
      card: card ?? this.card,
      primary: primary ?? this.primary,
      primaryDark: primaryDark ?? this.primaryDark,
      accent: accent ?? this.accent,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      danger: danger ?? this.danger,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      outline: outline ?? this.outline,
      success: success ?? this.success,
      gold: gold ?? this.gold,
    );
  }

  @override
  MorandiPalette lerp(MorandiPalette? other, double t) {
    if (other == null) return this;
    return MorandiPalette(
      background: Color.lerp(background, other.background, t)!,
      card: Color.lerp(card, other.card, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryDark: Color.lerp(primaryDark, other.primaryDark, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      success: Color.lerp(success, other.success, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
    );
  }
}

/// 一套主题 = id + 名称 + 色板
class MorandiTheme {
  const MorandiTheme({
    required this.id,
    required this.name,
    required this.palette,
  });

  final String id;
  final String name;
  final MorandiPalette palette;
}

/// 主题清单（雾绿为默认，用户偏爱清雅淡绿系）
const morandiThemes = <MorandiTheme>[
  MorandiTheme(
    id: 'mist_green',
    name: '雾绿',
    palette: MorandiPalette(
      background: Color(0xFFF6F4EF),
      card: Color(0xFFFFFFFF),
      primary: Color(0xFF9DBB9B),
      primaryDark: Color(0xFF7A9B78),
      accent: Color(0xFFC4D6B0),
      textPrimary: Color(0xFF3E3F3A),
      textSecondary: Color(0xFF8A8B83),
      danger: Color(0xFFC98A7D),
      surfaceVariant: Color(0xFFF0EDE5),
      outline: Color(0xFFE6E1D8),
      success: Color(0xFF8FAE8B),
      gold: Color(0xFFE5C99B),
    ),
  ),
  MorandiTheme(
    id: 'blush',
    name: '藕粉',
    palette: MorandiPalette(
      background: Color(0xFFF7F1EF),
      card: Color(0xFFFFFFFF),
      primary: Color(0xFFD9B8B8),
      primaryDark: Color(0xFFB89292),
      accent: Color(0xFFEAD4D4),
      textPrimary: Color(0xFF4A3E3E),
      textSecondary: Color(0xFF9A8A8A),
      danger: Color(0xFFC07E74),
      surfaceVariant: Color(0xFFF5EEEC),
      outline: Color(0xFFEADCD8),
      success: Color(0xFF9BAE8F),
      gold: Color(0xFFE0B98A),
    ),
  ),
  MorandiTheme(
    id: 'mist_blue',
    name: '雾蓝',
    palette: MorandiPalette(
      background: Color(0xFFF0F3F6),
      card: Color(0xFFFFFFFF),
      primary: Color(0xFFA9BCCF),
      primaryDark: Color(0xFF86A0B8),
      accent: Color(0xFFCDDCE8),
      textPrimary: Color(0xFF3A4148),
      textSecondary: Color(0xFF838E98),
      danger: Color(0xFFC08A7A),
      surfaceVariant: Color(0xFFECF0F4),
      outline: Color(0xFFDCE4EB),
      success: Color(0xFF8FAE8B),
      gold: Color(0xFFDDBF92),
    ),
  ),
  MorandiTheme(
    id: 'oat',
    name: '燕麦',
    palette: MorandiPalette(
      background: Color(0xFFF7F3EA),
      card: Color(0xFFFFFDF7),
      primary: Color(0xFFD8CBAF),
      primaryDark: Color(0xFFB5A684),
      accent: Color(0xFFE8DFC9),
      textPrimary: Color(0xFF4A453A),
      textSecondary: Color(0xFF988F7E),
      danger: Color(0xFFC0936F),
      surfaceVariant: Color(0xFFF2EDE2),
      outline: Color(0xFFE6DECE),
      success: Color(0xFF93A883),
      gold: Color(0xFFD9BE93),
    ),
  ),
  MorandiTheme(
    id: 'lilac',
    name: '香芋',
    palette: MorandiPalette(
      background: Color(0xFFF4F1F7),
      card: Color(0xFFFFFFFF),
      primary: Color(0xFFB8A8C8),
      primaryDark: Color(0xFF9683AB),
      accent: Color(0xFFD8CDE4),
      textPrimary: Color(0xFF423C4A),
      textSecondary: Color(0xFF8E8598),
      danger: Color(0xFFB9858A),
      surfaceVariant: Color(0xFFF1EDF5),
      outline: Color(0xFFE4DCEC),
      success: Color(0xFF9AAE93),
      gold: Color(0xFFD9B9A0),
    ),
  ),
  MorandiTheme(
    id: 'midnight',
    name: '墨夜',
    palette: MorandiPalette(
      background: Color(0xFF2B2E29),
      card: Color(0xFF343830),
      primary: Color(0xFF9DBB9B),
      primaryDark: Color(0xFFB5CDB3),
      accent: Color(0xFF55684F),
      textPrimary: Color(0xFFE6E4DA),
      textSecondary: Color(0xFF9A9C8F),
      danger: Color(0xFFD39A8B),
      surfaceVariant: Color(0xFF3C4137),
      outline: Color(0xFF4A5044),
      success: Color(0xFF8FB08C),
      gold: Color(0xFFE2C28E),
    ),
  ),
];

/// 莫兰迪页面转场：300ms 淡入 + 轻微水平滑入（替代默认平台转场）
class MorandiPageTransitionsBuilder extends PageTransitionsBuilder {
  const MorandiPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.03, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

/// 由 MorandiTheme 构建完整 ThemeData（Material 3）
ThemeData buildTheme(MorandiTheme theme) {
  final p = theme.palette;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: p.primary,
        brightness: p.isDark ? Brightness.dark : Brightness.light,
      ).copyWith(
        primary: p.primary,
        onPrimary: p.isDark ? const Color(0xFF1F231E) : Colors.white,
        secondary: p.accent,
        surface: p.card,
        onSurface: p.textPrimary,
        error: p.danger,
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.background,
    extensions: [p],
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final platform in TargetPlatform.values)
          platform: const MorandiPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.textPrimary,
      elevation: 0,
      centerTitle: false,
      systemOverlayStyle: p.overlayStyle,
      titleTextStyle: TextStyle(
        color: p.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      color: p.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: p.outline, width: 1),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.primary,
      foregroundColor: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.card,
      indicatorColor: p.accent,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(
          color: p.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? p.primaryDark
              : p.textSecondary,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surfaceVariant,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: p.primary, width: 1.5),
      ),
      hintStyle: TextStyle(color: p.textSecondary),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.primaryDark,
    ),
    dividerColor: p.outline,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.primary,
        foregroundColor: p.isDark ? const Color(0xFF1F231E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
  );
}
