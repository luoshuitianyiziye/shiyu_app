import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ignore_for_file: experimental_member_use

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/morandi_theme.dart';
import '../../../app/widgets/morandi_picker.dart';
import '../../../core/db/database.dart';
import '../../../core/db/db_providers.dart';
import '../../../core/utils/confirm_dialog.dart';
import '../../../core/utils/format.dart';
import '../data/note_image_store.dart';

/// 从 Delta JSON 中提取本地图片路径列表（缩略图 / 清理用）
List<String> extractImagePaths(String bodyJson) {
  if (bodyJson.isEmpty) return [];
  try {
    final delta = jsonDecode(bodyJson) as List;
    final paths = <String>[];
    for (final op in delta) {
      final data = (op as Map)['insert'];
      if (data is Map && data.containsKey('image')) {
        final url = data['image'] as String;
        if (url.startsWith('file://')) {
          paths.add(Uri.decodeComponent(url.substring('file://'.length)));
        }
      }
    }
    return paths;
  } catch (_) {
    return [];
  }
}

/// 本地文件 → quill 可存储的 URL
String localFileUrl(String path) => 'file://${path.replaceAll('\\', '/')}';

/// 笔记编辑器：富文本 + 图片嵌入正文 + 可展开工具栏（中文说明小字）+ 分类
class NoteEditorPage extends ConsumerStatefulWidget {
  const NoteEditorPage({super.key, this.existing});

  /// null = 新建
  final NoteRow? existing;

  @override
  ConsumerState<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends ConsumerState<NoteEditorPage> {
  late final TextEditingController _titleController;
  late final QuillController _quill;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool _saving = false;
  int? _categoryId; // 当前笔记分类
  Map<String, String> _captions = {}; // 图片路径 → 小字说明

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.existing?.title ?? '');
    _categoryId = widget.existing?.categoryId;
    _captions = _captionsFromJson(widget.existing?.imageCaptions ?? '');
    final body = widget.existing?.body ?? '';
    _quill = QuillController(
      document: body.isEmpty
          ? Document()
          : _documentFromJson(body),
      selection: const TextSelection.collapsed(offset: 0),
    );
    // 工具栏按钮状态随光标变化刷新（激活高亮）
    _quill.addListener(_onQuillChanged);
  }

  Map<String, String> _captionsFromJson(String s) {
    try {
      final map = jsonDecode(s);
      if (map is Map) {
        return map.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {
      // 非法 JSON 忽略
    }
    return {};
  }

  Document _documentFromJson(String body) {
    try {
      return Document.fromJson(jsonDecode(body) as List);
    } catch (_) {
      return Document();
    }
  }

  void _onQuillChanged() {
    if (!mounted) return;
    setState(() {});
    _scheduleChecklistSync();
  }

  /// checklist 删除线同步的防抖定时器：输入过程中高频触发，
  /// 合并为 150ms 一次，避免长笔记每个按键都全文档扫描。
  Timer? _checklistSyncTimer;

  void _scheduleChecklistSync() {
    _checklistSyncTimer?.cancel();
    _checklistSyncTimer = Timer(
      const Duration(milliseconds: 150),
      _syncChecklistStrike,
    );
  }

  /// 任务列表勾选 → 行文字加删除线；取消勾选 → 移除删除线。
  /// 只在「勾选状态与现有删除线不一致」时同步：勾选行已有删除线则不动，
  /// 未勾选行无删除线则不动 —— 用户手动加/删删除线不会被立即覆盖。
  /// 内部所有文档操作均有保护：结构异常时静默跳过，绝不影响编辑。
  bool _syncingChecklist = false;

  void _syncChecklistStrike() {
    if (_syncingChecklist) return;
    _syncingChecklist = true;
    try {
      final doc = _quill.document;
      for (final node in doc.root.children) {
        if (node is! Line || node.hasEmbed) continue; // 跳过图片行
        try {
          final listValue = node.style.attributes[Attribute.list.key]?.value;
          if (listValue == null) continue; // 非列表行
          final offset = node.documentOffset;
          final len = node.toPlainText().length; // 不含换行符
          if (len <= 0) continue;
          if (offset < 0 || offset + len > doc.length) continue;
          final hasStrike =
              node.style.attributes.containsKey(Attribute.strikeThrough.key);
          if (listValue == Attribute.checked.value && !hasStrike) {
            // 勾选但无删除线 → 补上
            _quill.formatText(
              offset,
              len,
              Attribute.strikeThrough,
              shouldNotifyListeners: false,
            );
          } else if (listValue == Attribute.unchecked.value && hasStrike) {
            // 未勾选但仍有删除线 → 移除
            _quill.formatText(
              offset,
              len,
              Attribute.clone(Attribute.strikeThrough, null),
              shouldNotifyListeners: false,
            );
          }
        } catch (_) {
          // 单行同步失败不影响其他行与编辑
        }
      }
    } catch (_) {
      // 文档结构异常时静默跳过本次同步
    } finally {
      _syncingChecklist = false;
    }
  }

  @override
  void dispose() {
    _checklistSyncTimer?.cancel();
    _quill.removeListener(_onQuillChanged);
    _titleController.dispose();
    _quill.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---------- 图片嵌入正文 ----------

  Future<void> _insertImage() async {
    final path = await NoteImageStore.pickAndSave();
    if (path == null || !mounted) return;

    final doc = _quill.document;
    // 选区可能失效（如刚删除过图片），回退到文档末尾
    final sel = _quill.selection;
    var index = (sel.isValid ? sel.baseOffset : doc.length).clamp(0, doc.length);
    // flutter_quill 只保证 video 类 embed 独占一行，图片不会自动补换行；
    // 若光标在段中/段尾，先把位置归一化到行首，保证图片独占一行，
    // 避免与文字同处一行导致行内溢出、以及按行删除时连带删除文字。
    final text = doc.toPlainText();
    while (index > 0 && index <= text.length && text[index - 1] != '\n') {
      index--;
    }
    _quill.document.insert(index, BlockEmbed.image(localFileUrl(path)));
    _quill.updateSelection(
      TextSelection.collapsed(
        offset: (index + 1).clamp(0, _quill.document.length),
      ),
      ChangeSource.local,
    );
    _focusNode.requestFocus();
  }

  Future<void> _onImageTap(String path) async {
    final hasCaption = (_captions[path] ?? '').isNotEmpty;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).extension<MorandiPalette>()!.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.zoom_in),
              title: const Text('查看大图'),
              onTap: () => Navigator.of(ctx).pop('view'),
            ),
            ListTile(
              leading: const Icon(Icons.title),
              title: Text(hasCaption ? '编辑说明' : '添加说明'),
              subtitle: const Text('在图片下方显示一行小字'),
              onTap: () => Navigator.of(ctx).pop('caption'),
            ),
            if (hasCaption)
              ListTile(
                leading: Icon(Icons.clear, color: Theme.of(ctx).colorScheme.error),
                title: const Text('移除说明'),
                onTap: () => Navigator.of(ctx).pop('removeCaption'),
              ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
              title: const Text('删除图片'),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;

    if (action == 'view') {
      await _showImagePreview(path);
    } else if (action == 'caption') {
      await _editCaption(path);
    } else if (action == 'removeCaption') {
      setState(() => _captions.remove(path));
    } else if (action == 'delete') {
      // 删除图片不可撤销（本地文件立即移除）：先确认，避免误触丢失内容
      final ok = await showConfirmDialog(
        context,
        title: '删除图片',
        content: '将从笔记中移除这张图片（本地文件一并删除，不可恢复）',
        confirmText: '删除',
        danger: true,
      );
      if (ok) _deleteImageByPath(path);
    }
  }

  /// 全屏查看图片（含说明文字）
  Future<void> _showImagePreview(String path) async {
    final caption = _captions[path];
    await showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(ctx).pop(),
                child: InteractiveViewer(
                  maxScale: 6,
                  minScale: 0.5,
                  // 双指自由缩放 / 拖动
                  child: Center(
                    child: Image.file(File(path), fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: IconButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  if (caption != null && caption.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        caption,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    '双指缩放 · 拖动查看 · 点击关闭',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 为图片添加/编辑一行小字说明
  Future<void> _editCaption(String path) async {
    final text = await showInputDialog(
      context,
      title: '图片说明',
      initialValue: _captions[path] ?? '',
      hintText: '给图片加一句小字说明…',
      maxLength: 60,
    );
    if (!mounted || text == null) return; // 取消 → 保持原说明不变
    if (text.isEmpty) {
      _captions.remove(path);
    } else {
      _captions[path] = text;
    }
    setState(() {});
  }

  /// 找到含指定图片 embed 的行（图片独占一行）
  Line? _findImageLine(String path) {
    final target = localFileUrl(path);
    for (final node in _quill.document.root.children) {
      if (node is! Line || !node.hasEmbed) continue;
      for (final leaf in node.children) {
        if (leaf is Embed &&
            leaf.value.type == BlockEmbed.imageType &&
            leaf.value.data == target) {
          return node;
        }
      }
    }
    return null;
  }

  /// 从文档中移除指定路径的图片 embed，并删除本地文件与说明。
  /// 删除后把光标移到安全位置，避免旧选区越界导致编辑器异常。
  void _deleteImageByPath(String path) {
    try {
      final line = _findImageLine(path);
      if (line != null) {
        final off = line.documentOffset;
        _quill.document.delete(off, line.length);
        final len = _quill.document.length;
        final pos = off.clamp(0, len > 0 ? len - 1 : 0);
        _quill.updateSelection(
          TextSelection.collapsed(offset: pos),
          ChangeSource.local,
        );
      }
    } catch (_) {
      // 文档结构异常时忽略（图片文件仍会清理）
    }
    _captions.remove(path);
    NoteImageStore.deleteFile(path);
    setState(() {});
  }

  // ---------- 保存 ----------

  /// 复制笔记全文纯文本到剪贴板（密码/清单类笔记快速取用）
  Future<void> _copyPlainText() async {
    final text = _quill.document.toPlainText();
    if (text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('笔记为空，没有可复制的内容')),
        );
      }
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制全文')),
      );
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('给笔记起个标题吧')),
      );
      return;
    }
    setState(() => _saving = true);

    try {
      final bodyJson = jsonEncode(_quill.document.toDelta().toJson());
      final imagesJson = jsonEncode(extractImagePaths(bodyJson));
      final captionsJson = jsonEncode(_captions);
      final db = ref.read(databaseProvider);

      if (_isNew) {
        await db.addNote(
          NotesCompanion.insert(
            title: title,
            body: Value(bodyJson),
            images: Value(imagesJson),
            imageCaptions: Value(captionsJson),
            categoryId: Value(_categoryId),
          ),
        );
      } else {
        await db.updateNote(
          widget.existing!.id,
          NotesCompanion(
            title: Value(title),
            body: Value(bodyJson),
            images: Value(imagesJson),
            imageCaptions: Value(captionsJson),
            categoryId: Value(_categoryId),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
      }
    } finally {
      // 无论成功失败都复位，避免保存按钮永久卡死
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------- 工具栏 ----------

  /// 当前光标处是否应用了某个 attribute（用于按钮高亮）。
  /// 颜色类 attribute 的值是动态的（hex 字符串），只判断 key 是否存在。
  bool _hasAttr(Attribute attr) {
    final attrs = _quill.getSelectionStyle().attributes;
    final v = attrs[attr.key];
    if (v == null) return false;
    if (attr.key == Attribute.color.key ||
        attr.key == Attribute.background.key) {
      return true;
    }
    return v.value == attr.value;
  }

  /// 应用/取消格式（显式开关）：
  /// 第一次点击 → 启用（并作为后续输入格式）；
  /// 第二次点击 → 取消（清除该 attribute，避免只改 toggledStyle 导致的"取消无效"）。
  void _toggleAttr(Attribute attr) {
    try {
      if (_hasAttr(attr)) {
        _quill.formatSelection(Attribute.clone(attr, null));
      } else {
        _quill.formatSelection(attr);
      }
    } catch (_) {
      // 文档结构异常时静默跳过，不影响编辑
    }
  }

  /// 工具栏按钮：图标 + 长按提示 + 激活高亮
  Widget _toolButton({
    required IconData icon,
    required String hint,
    required VoidCallback onTap,
    bool active = false,
  }) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;

    return Tooltip(
      message: hint,
      child: IconButton(
        icon: Icon(
          icon,
          size: 20,
          color: active ? palette.primaryDark : palette.textSecondary,
        ),
        visualDensity: VisualDensity.compact,
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: active ? palette.accent : null,
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    final palette = Theme.of(context).extension<MorandiPalette>()!;

    // 第一行：最常用格式
    final primary = <Widget>[
      _toolButton(
        icon: Icons.undo,
        hint: '撤销',
        onTap: () => _quill.undo(),
      ),
      _toolButton(
        icon: Icons.redo,
        hint: '重做',
        onTap: () => _quill.redo(),
      ),
      _toolButton(
        icon: Icons.title,
        hint: '标题（正文/标题1/标题2）',
        onTap: _cycleHeader,
        active: _hasAttr(Attribute.h1) || _hasAttr(Attribute.h2),
      ),
      _toolButton(
        icon: Icons.format_bold,
        hint: '加粗',
        onTap: () => _toggleAttr(Attribute.bold),
        active: _hasAttr(Attribute.bold),
      ),
      _toolButton(
        icon: Icons.format_italic,
        hint: '斜体',
        onTap: () => _toggleAttr(Attribute.italic),
        active: _hasAttr(Attribute.italic),
      ),
      _toolButton(
        icon: Icons.format_underline,
        hint: '下划线',
        onTap: () => _toggleAttr(Attribute.underline),
        active: _hasAttr(Attribute.underline),
      ),
      _toolButton(
        icon: Icons.format_strikethrough,
        hint: '删除线',
        onTap: () => _toggleAttr(Attribute.strikeThrough),
        active: _hasAttr(Attribute.strikeThrough),
      ),
      _toolButton(
        icon: Icons.checklist,
        hint: '待办清单',
        onTap: () => _toggleAttr(Attribute.unchecked),
        active: _hasAttr(Attribute.checked) || _hasAttr(Attribute.unchecked),
      ),
      _toolButton(
        icon: Icons.add_photo_alternate_outlined,
        hint: '插入图片',
        onTap: _insertImage,
      ),
    ];

    // 第二行：段落/样式/颜色/对齐
    final secondary = <Widget>[
      _toolButton(
        icon: Icons.format_list_bulleted,
        hint: '无序列表',
        onTap: () => _toggleAttr(Attribute.ul),
        active: _hasAttr(Attribute.ul),
      ),
      _toolButton(
        icon: Icons.format_list_numbered,
        hint: '有序列表',
        onTap: () => _toggleAttr(Attribute.ol),
        active: _hasAttr(Attribute.ol),
      ),
      _toolButton(
        icon: Icons.format_quote,
        hint: '引用',
        onTap: () => _toggleAttr(Attribute.blockQuote),
        active: _hasAttr(Attribute.blockQuote),
      ),
      _toolButton(
        icon: Icons.code,
        hint: '行内代码',
        onTap: () => _toggleAttr(Attribute.inlineCode),
        active: _hasAttr(Attribute.inlineCode),
      ),
      _toolButton(
        icon: Icons.terminal,
        hint: '代码块',
        onTap: () => _toggleAttr(Attribute.codeBlock),
        active: _hasAttr(Attribute.codeBlock),
      ),
      _toolButton(
        icon: Icons.format_color_text,
        hint: '文字颜色',
        onTap: _pickTextColor,
        active: _hasAttr(Attribute.color),
      ),
      _toolButton(
        icon: Icons.format_color_fill,
        hint: '背景色',
        onTap: _pickHighlightColor,
        active: _hasAttr(Attribute.background),
      ),
      _toolButton(
        icon: Icons.format_align_left,
        hint: '左对齐',
        onTap: () => _toggleAttr(Attribute.leftAlignment),
        active: _hasAttr(Attribute.leftAlignment),
      ),
      _toolButton(
        icon: Icons.format_align_center,
        hint: '居中',
        onTap: () => _toggleAttr(Attribute.centerAlignment),
        active: _hasAttr(Attribute.centerAlignment),
      ),
      _toolButton(
        icon: Icons.format_align_right,
        hint: '右对齐',
        onTap: () => _toggleAttr(Attribute.rightAlignment),
        active: _hasAttr(Attribute.rightAlignment),
      ),
      _toolButton(
        icon: Icons.format_align_justify,
        hint: '两端对齐',
        onTap: () => _toggleAttr(Attribute.justifyAlignment),
        active: _hasAttr(Attribute.justifyAlignment),
      ),
      _toolButton(
        icon: Icons.format_clear,
        hint: '清除格式',
        onTap: () => _quill.formatSelection(null),
      ),
    ];

    return Material(
      color: palette.card,
      elevation: 1,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                children: primary,
              ),
            ),
            Divider(height: 1, thickness: 0.5, color: palette.accent),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                children: secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 标题循环：正文 → 标题1 → 标题2 → 正文
  void _cycleHeader() {
    final attrs = _quill.getSelectionStyle().attributes;
    if (attrs[Attribute.h1.key]?.value == Attribute.h1.value) {
      _toggleAttr(Attribute.h2);
    } else if (attrs[Attribute.h2.key]?.value == Attribute.h2.value) {
      _toggleAttr(Attribute.clone(Attribute.h1, null)); // 清除标题
    } else {
      _toggleAttr(Attribute.h1);
    }
  }

  Future<void> _pickTextColor() async {
    final color = await showDialog<Color>(
      context: context,
      builder: (ctx) => _ColorPickerDialog(title: '文字颜色'),
    );
    if (color != null) {
      _quill.formatSelection(Attribute.clone(Attribute.color, _toHex(color)));
      setState(() {});
    }
  }

  Future<void> _pickHighlightColor() async {
    final color = await showDialog<Color>(
      context: context,
      builder: (ctx) => _ColorPickerDialog(title: '背景色'),
    );
    if (color != null) {
      _quill.formatSelection(
        Attribute.clone(Attribute.background, _toHex(color)),
      );
      setState(() {});
    }
  }

  String _toHex(Color c) {
    final v = c.toARGB32();
    return '#${(v & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  }

  // ---------- 分类选择 ----------

  String _categoryLabel(List<NoteCategoryRow> cats) {
    if (_categoryId == null) return '未分类';
    for (final c in cats) {
      if (c.id == _categoryId) return c.name;
    }
    return '未分类';
  }

  /// 分类：莫兰迪小窗选择（与任务重复规则一致）
  Future<void> _pickCategory(List<NoteCategoryRow> cats) async {
    final picked = await showMorandiPicker<int?>(
      context: context,
      title: '笔记分类',
      titleIcon: Icons.folder_outlined,
      selected: _categoryId,
      items: [
        const PickerItem<int?>(
          value: null,
          label: '未分类',
          icon: Icons.folder_off_outlined,
        ),
        for (final c in cats)
          PickerItem<int?>(
            value: c.id,
            label: c.name,
            icon: Icons.folder,
            color: parseHexColor(c.color),
          ),
      ],
    );
    if (picked != null && mounted) setState(() => _categoryId = picked);
  }

  Widget _buildCategoryBar() {
    final categoriesAsync = ref.watch(noteCategoriesProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: categoriesAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (_, _) => const SizedBox.shrink(),
        data: (cats) => MorandiOptionField(
          icon: Icons.folder_outlined,
          label: '分类',
          valueText: _categoryLabel(cats),
          onTap: () => _pickCategory(cats),
          dense: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? '新笔记' : '编辑笔记'),
        actions: [
          IconButton(
            onPressed: _copyPlainText,
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: '复制全文',
          ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _titleController,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
                decoration: const InputDecoration(
                  hintText: '标题',
                  filled: false,
                  border: InputBorder.none,
                ),
              ),
            ),
            _buildCategoryBar(),
            const Divider(height: 1),
            Expanded(
              child: QuillEditor(
                controller: _quill,
                focusNode: _focusNode,
                scrollController: _scrollController,
                config: QuillEditorConfig(
                  placeholder: '写点什么…',
                  autoFocus: true,
                  expands: true,
                  padding: const EdgeInsets.all(16),
                  // 本地图片渲染：点击可预览 / 删除
                  embedBuilders: [
                    LocalImageEmbedBuilder(
                      onTap: _onImageTap,
                      captionFor: (p) => _captions[p],
                    ),
                  ],
                ),
              ),
            ),
            _buildToolbar(),
          ],
        ),
      ),
    );
  }
}

/// 简易取色器（莫兰迪色板 + 常用色）
class _ColorPickerDialog extends StatelessWidget {
  const _ColorPickerDialog({required this.title});

  final String title;

  static const _palette = [
    Color(0xFF1F231E), // 墨黑
    Color(0xFF5C6B57), // 墨绿
    Color(0xFF9DBB9B), // 雾绿
    Color(0xFFB8C4B2), // 浅绿
    Color(0xFFA3B8C4), // 雾蓝
    Color(0xFF6E8BA0), // 灰蓝
    Color(0xFFC4A3A3), // 藕粉
    Color(0xFFB57281), // 豆沙
    Color(0xFFD9C4A3), // 燕麦
    Color(0xFF8A6F4D), // 卡其
    Color(0xFFB3A3C4), // 香芋
    Color(0xFF7E6E9E), // 灰紫
    Color(0xFFE0B080), // 暖橙
    Color(0xFFC46A6A), // 砖红
    Color(0xFF6AA0C4), // 天蓝
    Color(0xFF7FC4A3), // 青绿
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: _palette
            .map(
              (c) => InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => Navigator.of(context).pop(c),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black12),
                  ),
                ),
              ),
            )
            .toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

/// 本地文件图片的渲染器：file:// 路径 → Image.file；点击弹出操作菜单；
/// 支持在图片下方渲染一行小字说明。
class LocalImageEmbedBuilder extends EmbedBuilder {
  const LocalImageEmbedBuilder({required this.onTap, required this.captionFor});

  final void Function(String path) onTap;
  final String? Function(String path) captionFor;

  @override
  String get key => BlockEmbed.imageType;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final url = embedContext.node.value.data as String?;
    if (url == null || !url.startsWith('file://')) {
      // 非本地图（网络图）回退默认渲染
      return url == null ? const SizedBox.shrink() : Image.network(url);
    }
    final path = Uri.decodeComponent(url.substring('file://'.length));
    final caption = captionFor(path);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GestureDetector(
        onTap: () => onTap(path),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(path),
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (_, _, _) => Container(
                  height: 120,
                  color: Colors.grey.shade200,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
            if (caption != null && caption.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 5, left: 2, right: 2),
                child: Text(
                  caption,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
