import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/morandi_theme.dart';
import '../../../core/db/database.dart';
import '../../../core/db/db_providers.dart';
import '../data/text_import.dart';

/// 打开「导入文本」弹层：粘贴多行文本 → 自动切分为条目 → 生成一篇笔记。
Future<void> showImportTextSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).extension<MorandiPalette>()!.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _ImportTextSheet(),
  );
}

class _ImportTextSheet extends ConsumerStatefulWidget {
  const _ImportTextSheet();

  @override
  ConsumerState<_ImportTextSheet> createState() => _ImportTextSheetState();
}

class _ImportTextSheetState extends ConsumerState<_ImportTextSheet> {
  final _titleController = TextEditingController();
  final _textController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _textController.dispose();
    super.dispose();
  }

  List<String> get _entries => splitImportText(_textController.text);

  Future<void> _save() async {
    if (_saving) return;
    final entries = _entries;
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可导入的文本')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final defaultTitle =
          '导入文本 · ${DateFormat('M月d日 HH:mm', 'zh_CN').format(DateTime.now())}';
      final title = _titleController.text.trim().isEmpty
          ? defaultTitle
          : _titleController.text.trim();
      await ref.read(databaseProvider).addNote(
            NotesCompanion.insert(
              title: title,
              body: Value(buildEntriesBody(entries)),
            ),
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入 ${entries.length} 条内容到笔记「$title」')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final entries = _entries;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '导入文本',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '粘贴多行文本：空行/分隔线分段，否则每行一条，自动识别条目',
              style: TextStyle(fontSize: 12, color: palette.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                hintText: '笔记标题（可选，留空自动生成）',
                prefixIcon: Icon(Icons.title),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _textController,
              maxLines: 8,
              minLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: '在这里粘贴文本…\n例如：\n账号：xxx\n密码：yyy\n\n或每行一条清单',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.auto_awesome_outlined, size: 16, color: palette.primaryDark),
                const SizedBox(width: 6),
                Text(
                  '识别到 ${entries.length} 条',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: palette.primaryDark,
                  ),
                ),
                const Spacer(),
                if (entries.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(_textController.clear),
                    child: const Text('清空'),
                  ),
              ],
            ),
            if (entries.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in entries.take(3))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          e.length > 40 ? '${e.substring(0, 40)}…' : e,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                    if (entries.length > 3)
                      Text(
                        '… 还有 ${entries.length - 3} 条',
                        style: TextStyle(fontSize: 11, color: palette.textSecondary),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: Text(
                _saving ? '导入中…' : '导入为笔记',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
