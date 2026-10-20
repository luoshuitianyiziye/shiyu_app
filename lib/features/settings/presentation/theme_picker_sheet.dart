import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/providers.dart';
import '../../../app/theme/morandi_theme.dart';
import '../../../core/db/db_providers.dart';

/// 主题选择弹层：6 套莫兰迪主题即选即生效
Future<void> showThemePicker(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Theme.of(context).extension<MorandiPalette>()!.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _ThemePickerSheet(),
  );
}

class _ThemePickerSheet extends ConsumerWidget {
  const _ThemePickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentId = ref.watch(themeIdNotifierProvider).value;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).extension<MorandiPalette>()!.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '选择主题',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context)
                    .extension<MorandiPalette>()!
                    .textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ...morandiThemes.map((theme) {
              final selected = theme.id == currentId;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: theme.palette.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.palette.textSecondary.withValues(alpha: 0.4),
                    ),
                  ),
                  child: selected
                      ? Icon(
                          Icons.check,
                          size: 20,
                          color: theme.palette.isDark
                              ? const Color(0xFF1F231E)
                              : Colors.white,
                        )
                      : null,
                ),
                title: Text(
                  theme.name,
                  style: TextStyle(color: theme.palette.textPrimary),
                ),
                subtitle: Text(
                  theme.id == 'mist_green'
                      ? '默认 · 清雅淡绿'
                      : '莫兰迪 · ${theme.name}色系',
                  style: TextStyle(
                    color: theme.palette.textSecondary,
                    fontSize: 12,
                  ),
                ),
                trailing: selected
                    ? Icon(Icons.check_circle, color: theme.palette.primaryDark)
                    : null,
                onTap: () => _select(context, ref, theme),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    MorandiTheme theme,
  ) async {
    ref.read(themeIdNotifierProvider).value = theme.id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_id', theme.id);
    // 同步进设置表（云同步后随账号保存）
    await ref.read(databaseProvider).updateSettings(themeId: theme.id);
    if (context.mounted) Navigator.of(context).pop();
  }
}
