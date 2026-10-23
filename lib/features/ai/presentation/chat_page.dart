import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/morandi_theme.dart';
import '../../../core/ai/ai_client.dart';
import '../application/ai_service.dart';
import '../data/chat_state.dart';
import 'ai_draft_list.dart';

/// 问答页：与小屿聊天，回答可一键转为任务。
class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 160,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await ref.read(chatProvider.notifier).send(text);
    _scrollToBottom();
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// 把助手回答交给任务生成，弹出草案预览
  Future<void> _toTask(String reply) async {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final result = await ref.read(aiServiceProvider).generateTasks(reply);
      if (!mounted) return;
      Navigator.of(context).pop(); // 关闭 loading
      if (result.drafts.isEmpty) {
        _toast('没有从这段回答里识别到任务');
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: palette.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '从回答生成任务',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                AiDraftList(
                  drafts: result.drafts,
                  onAdded: () => Navigator.of(sheetContext).pop(),
                ),
              ],
            ),
          ),
        ),
      );
    } on AiException catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        _toast(e.message);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        _toast('出错了：$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<MorandiPalette>()!;
    final chat = ref.watch(chatProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('问答'),
        actions: [
          IconButton(
            onPressed: chat.turns.isEmpty
                ? null
                : () => ref.read(chatProvider.notifier).clear(),
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: '清空对话',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: chat.turns.isEmpty
                  ? _emptyState(palette)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      itemCount: chat.turns.length + (chat.loading ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i < chat.turns.length) {
                          final turn = chat.turns[i];
                          return _Bubble(
                            turn: turn,
                            palette: palette,
                            onToTask: turn.isUser
                                ? null
                                : () => _toTask(turn.text),
                          );
                        }
                        return _TypingBubble(palette: palette);
                      },
                    ),
            ),
            if (chat.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Text(
                  chat.error!,
                  style: TextStyle(fontSize: 12, color: palette.danger),
                ),
              ),
            _inputBar(palette, chat.loading),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(MorandiPalette palette) {
    final suggestions = ['今天有点累，陪我聊聊吧', '帮我分析一下怎么安排明天的学习', '有什么办法能坚持每天早起？'];
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      children: [
        Icon(Icons.chat_bubble_outline, size: 44, color: palette.primaryDark),
        const SizedBox(height: 12),
        Text(
          '和小屿聊聊天吧～',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '她可以陪你聊天、给建议；回答还能一键转成任务',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: palette.textSecondary),
        ),
        const SizedBox(height: 24),
        for (final s in suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OutlinedButton(
              onPressed: () {
                _controller.text = s;
                _controller.selection = TextSelection.collapsed(
                  offset: s.length,
                );
              },
              child: Text(s),
            ),
          ),
      ],
    );
  }

  Widget _inputBar(MorandiPalette palette, bool loading) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: palette.background,
        border: Border(top: BorderSide(color: palette.outline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(
                hintText: '说点什么…',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: loading ? null : _send,
            icon: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send, size: 20),
            style: IconButton.styleFrom(backgroundColor: palette.primary),
            tooltip: '发送',
          ),
        ],
      ),
    );
  }
}

/// 聊天气泡（用户右侧 / 小屿左侧）
class _Bubble extends StatelessWidget {
  const _Bubble({required this.turn, required this.palette, this.onToTask});

  final ChatTurn turn;
  final MorandiPalette palette;
  final VoidCallback? onToTask;

  @override
  Widget build(BuildContext context) {
    final isUser = turn.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 15,
              backgroundColor: palette.accent,
              child: Icon(
                Icons.auto_awesome,
                size: 16,
                color: palette.primaryDark,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isUser
                        ? palette.primary.withValues(alpha: 0.85)
                        : palette.card,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isUser ? 16 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 16),
                    ),
                    border: Border.all(color: palette.outline),
                  ),
                  child: Text(
                    turn.text,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: isUser ? Colors.white : palette.textPrimary,
                    ),
                  ),
                ),
                if (onToTask != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 2),
                    child: TextButton.icon(
                      onPressed: onToTask,
                      icon: const Icon(Icons.playlist_add, size: 16),
                      label: const Text('转为任务', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: palette.primaryDark,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 小屿正在输入
class _TypingBubble extends StatelessWidget {
  const _TypingBubble({required this.palette});

  final MorandiPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: palette.accent,
            child: Icon(
              Icons.auto_awesome,
              size: 16,
              color: palette.primaryDark,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.outline),
            ),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: palette.primaryDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
