import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/morandi_theme.dart';
import '../../../app/widgets/empty_state.dart';
import '../../../app/widgets/slidable_actions.dart';
import '../../../core/db/database.dart';
import '../../../core/db/db_providers.dart';
import '../../../core/utils/confirm_dialog.dart';
import '../../../core/utils/format.dart';
import '../data/note_image_store.dart';
import 'import_text_sheet.dart';
import 'note_editor_page.dart';

/// 笔记列表：搜索 / 分类筛选 / 置顶 / 图片缩略 / 左滑删除
class NotesPage extends ConsumerStatefulWidget {
  const NotesPage({super.key});

  @override
  ConsumerState<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends ConsumerState<NotesPage> {
  String _query = '';
  int? _filterCategoryId; // null = 全部

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final notesAsync = ref.watch(notesStreamProvider);
    final categoriesAsync = ref.watch(noteCategoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('笔记'),
        actions: [
          IconButton(
            onPressed: () => showImportTextSheet(context),
            icon: const Icon(Icons.file_download_outlined),
            tooltip: '导入文本',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null, // 多页 FAB 共存（indexedStack），禁用 hero 动画避免标签冲突
        onPressed: () => _openEditor(),
        backgroundColor: palette.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.edit),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              onChanged: (v) => setState(() => _query = v.trim()),
              decoration: InputDecoration(
                hintText: '搜索笔记',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                filled: true,
                fillColor: palette.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          // 分类筛选条
          categoriesAsync.when(
            loading: () => const SizedBox(height: 40),
            error: (_, _) => const SizedBox(height: 40),
            data: (categories) => _CategoryFilterBar(
              categories: categories,
              selectedId: _filterCategoryId,
              onSelect: (id) => setState(() => _filterCategoryId = id),
              onManage: _manageCategories,
            ),
          ),
          Expanded(
            child: notesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败：$e')),
              data: (notes) {
                final filtered = notes.where((n) {
                  final matchQuery =
                      _query.isEmpty ||
                      n.title.contains(_query) ||
                      _plainText(n).contains(_query);
                  final matchCategory =
                      _filterCategoryId == null ||
                      n.categoryId == _filterCategoryId;
                  return matchQuery && matchCategory;
                }).toList();
                if (filtered.isEmpty) {
                  final isFiltering =
                      _query.isNotEmpty || _filterCategoryId != null;
                  return isFiltering
                      ? const EmptyState(
                          icon: Icons.search_off_outlined,
                          title: '没有找到相关笔记',
                          subtitle: '换个关键词，或清除筛选再试试',
                          compact: true,
                        )
                      : EmptyState(
                          icon: Icons.edit_note_outlined,
                          title: '还没有笔记',
                          subtitle: '点右下角 + 写一篇，或从右上角导入文本',
                          actionLabel: '写第一篇笔记',
                          onAction: () => _openEditor(),
                        );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) => _NoteCard(
                    note: filtered[i],
                    category: _categoryName(
                      categoriesAsync.value ?? const [],
                      filtered[i].categoryId,
                    ),
                    highlightQuery: _query,
                    onTap: () => _openEditor(existing: filtered[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String? _categoryName(List<NoteCategoryRow> cats, int? id) {
    if (id == null) return null;
    for (final c in cats) {
      if (c.id == id) return c.name;
    }
    return null;
  }

  void _openEditor({NoteRow? existing}) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NoteEditorPage(existing: existing)),
    );
  }

  /// 分类管理：新增 / 重命名 / 删除
  Future<void> _manageCategories() async {
    if (!mounted) return;
    final palette = Theme.of(context).extension<MorandiPalette>()!;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _CategoryManagerSheet(),
    );
  }
}

/// 顶部横向分类筛选条
class _CategoryFilterBar extends StatelessWidget {
  const _CategoryFilterBar({
    required this.categories,
    required this.selectedId,
    required this.onSelect,
    required this.onManage,
  });

  final List<NoteCategoryRow> categories;
  final int? selectedId;
  final ValueChanged<int?> onSelect;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('全部'),
              selected: selectedId == null,
              onSelected: (_) => onSelect(null),
              selectedColor: palette.accent,
              labelStyle: TextStyle(
                color: selectedId == null
                    ? palette.primaryDark
                    : palette.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          ...categories.map((c) {
            final selected = selectedId == c.id;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(c.name),
                selected: selected,
                onSelected: (_) => onSelect(c.id),
                selectedColor: palette.accent,
                avatar: CircleAvatar(
                  backgroundColor: _parseColor(c.color),
                  radius: 5,
                ),
                labelStyle: TextStyle(
                  color: selected ? palette.primaryDark : palette.textSecondary,
                  fontSize: 12,
                ),
              ),
            );
          }),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: ActionChip(
              avatar: const Icon(Icons.create_new_folder_outlined, size: 16),
              label: const Text('管理'),
              onPressed: onManage,
              labelStyle: TextStyle(fontSize: 12, color: palette.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

Color _parseColor(String hex) => parseHexColor(hex);

/// 分类管理弹层：新增 / 重命名 / 删除（实时响应数据库变化）
class _CategoryManagerSheet extends ConsumerStatefulWidget {
  const _CategoryManagerSheet();

  @override
  ConsumerState<_CategoryManagerSheet> createState() =>
      _CategoryManagerSheetState();
}

class _CategoryManagerSheetState extends ConsumerState<_CategoryManagerSheet> {
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入分类名称')));
      return;
    }
    final db = ref.read(databaseProvider);
    await db.addNoteCategory(name);
    // 弹层可能已被用户下滑关闭 → 避免操作已 dispose 的 controller
    if (!mounted) return;
    _nameController.clear();
    // 列表由 noteCategoriesProvider 流自动刷新
  }

  Future<void> _rename(NoteCategoryRow c) async {
    final newName = await showInputDialog(
      context,
      title: '重命名分类',
      initialValue: c.name,
      hintText: '新名称',
    );
    if (newName != null && newName.isNotEmpty && mounted) {
      await ref.read(databaseProvider).updateNoteCategory(c.id, name: newName);
    }
  }

  Future<void> _delete(NoteCategoryRow c) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除分类',
      content: '删除「${c.name}」后，该分类下的笔记将变为未分类',
      confirmText: '删除',
      danger: true,
    );
    if (ok == true) {
      await ref.read(databaseProvider).deleteNoteCategory(c.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final categoriesAsync = ref.watch(noteCategoriesProvider);
    final categories = categoriesAsync.value ?? const <NoteCategoryRow>[];

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
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
              '分类管理',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            // 新增
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      hintText: '新分类名称',
                      isDense: true,
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _add,
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.primary,
                    minimumSize: const Size(0, 40),
                  ),
                  child: const Text('新增'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 分类列表（实时刷新）
            if (categories.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    '还没有分类，先添加一个吧',
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              )
            else
              ...categories.map((c) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: _parseColor(c.color),
                    radius: 10,
                  ),
                  title: Text(
                    c.name,
                    style: TextStyle(color: palette.textPrimary, fontSize: 15),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        tooltip: '重命名',
                        onPressed: () => _rename(c),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: palette.danger,
                        ),
                        tooltip: '删除',
                        onPressed: () => _delete(c),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

/// Delta JSON → 纯文本（搜索/摘要用）
///
/// 带缓存：按 note.id + updatedAt 缓存解析结果，避免搜索每次按键、
/// 列表每次重建时对每篇笔记重复 jsonDecode + Document.fromJson 全量解析。
String _plainText(NoteRow note) {
  final key = '${note.id}:${note.updatedAt.millisecondsSinceEpoch}';
  final cached = _plainTextCache[key];
  if (cached != null) return cached;
  String text = '';
  if (note.body.isNotEmpty) {
    try {
      text = Document.fromJson(jsonDecode(note.body) as List).toPlainText();
    } catch (_) {
      text = '';
    }
  }
  if (_plainTextCache.length > 200) _plainTextCache.clear(); // 防无限增长
  _plainTextCache[key] = text;
  return text;
}

/// 纯文本解析缓存（轻量 LRU：超过 200 条清空重建）
final Map<String, String> _plainTextCache = {};

/// 截取命中关键词前后的上下文片段（搜索定位到具体条目用）
String _matchSnippet(String text, String query) {
  final idx = text.toLowerCase().indexOf(query.toLowerCase());
  if (idx < 0) return text;
  final start = (idx - 24).clamp(0, text.length);
  final end = (idx + query.length + 48).clamp(0, text.length);
  final prefix = start > 0 ? '…' : '';
  final suffix = end < text.length ? '…' : '';
  return '$prefix${text.substring(start, end)}$suffix';
}

/// 摘要文本：搜索时高亮命中的关键词
class _SnippetText extends StatelessWidget {
  const _SnippetText({
    required this.text,
    required this.query,
    required this.style,
    required this.highlightColor,
  });

  final String text;
  final String query;
  final TextStyle style;
  final Color highlightColor;

  @override
  Widget build(BuildContext context) {
    final idx = query.isEmpty
        ? -1
        : text.toLowerCase().indexOf(query.toLowerCase());
    if (idx < 0) {
      return Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text.substring(0, idx)),
          TextSpan(
            text: text.substring(idx, idx + query.length),
            style: style.copyWith(
              color: highlightColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(text: text.substring(idx + query.length)),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

class _NoteCard extends ConsumerWidget {
  const _NoteCard({
    required this.note,
    required this.category,
    required this.onTap,
    this.highlightQuery = '',
  });

  final NoteRow note;
  final String? category;
  final VoidCallback onTap;

  /// 搜索关键词：正文命中时显示命中片段并高亮（定位到具体条目）
  final String highlightQuery;

  List<String> _images() {
    // 优先从正文 Delta 提取（图片嵌入正文）；兼容旧版 images 字段
    final fromBody = extractImagePaths(note.body);
    if (fromBody.isNotEmpty) return fromBody;
    try {
      return (jsonDecode(note.images) as List).cast<String>();
    } catch (_) {
      return [];
    }
  }

  /// 左滑「删除」：确认后删除并清理图片文件
  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除笔记',
      content: '「${note.title}」将被删除',
      confirmText: '删除',
      danger: true,
    );
    if (ok != true) return;
    await ref.read(databaseProvider).softDeleteNote(note.id);
    // 清理正文内嵌图片的本地文件
    for (final path in extractImagePaths(note.body)) {
      await NoteImageStore.deleteFile(path);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final images = _images();
    final plain = _plainText(note).trim();
    final query = highlightQuery.trim();
    final matched =
        query.isNotEmpty && plain.toLowerCase().contains(query.toLowerCase());
    final snippet = matched ? _matchSnippet(plain, query) : plain;
    final dateStr = DateFormat('M月d日', 'zh_CN').format(note.updatedAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Slidable(
        key: ValueKey('note-${note.id}'),
        endActionPane: buildEditDeletePane(
          context,
          onEdit: onTap,
          onDelete: () => _delete(context, ref),
        ),
        child: Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (images.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(
                        File(images.first),
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 64,
                          height: 64,
                          color: palette.accent,
                          child: Icon(
                            Icons.image_outlined,
                            color: palette.primaryDark,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (note.pinned) ...[
                              Icon(
                                Icons.push_pin,
                                size: 14,
                                color: palette.primaryDark,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                note.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: palette.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (snippet.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          _SnippetText(
                            text: snippet,
                            query: matched ? query : '',
                            style: TextStyle(
                              fontSize: 13,
                              color: palette.textSecondary,
                            ),
                            highlightColor: palette.primaryDark,
                          ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              dateStr,
                              style: TextStyle(
                                fontSize: 11,
                                color: palette.textSecondary,
                              ),
                            ),
                            if (category != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: palette.accent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  category!,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: palette.primaryDark,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
