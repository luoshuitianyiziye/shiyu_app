import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/ai/ai_client.dart';
import '../application/ai_service.dart';

/// 一条聊天消息（role: user / assistant）
class ChatTurn {
  const ChatTurn({required this.id, required this.role, required this.text});

  final String id;
  final String role;
  final String text;

  bool get isUser => role == 'user';

  Map<String, dynamic> toJson() => {'id': id, 'role': role, 'text': text};

  factory ChatTurn.fromJson(Map<String, dynamic> json) {
    return ChatTurn(
      id:
          (json['id'] as String?) ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      role: (json['role'] as String?) ?? 'assistant',
      text: (json['text'] as String?) ?? '',
    );
  }
}

class ChatState {
  const ChatState({
    this.turns = const [],
    this.loading = false,
    this.error,
    this.selected = const {},
  });

  final List<ChatTurn> turns;
  final bool loading;
  final String? error;

  /// 多选删除选中的消息 id
  final Set<String> selected;

  bool get selecting => selected.isNotEmpty;
}

class ChatNotifier extends Notifier<ChatState> {
  static const _kHistory = 'ai_chat_history';
  static const _maxTurns = 200;

  @override
  ChatState build() => const ChatState();

  /// 启动时加载历史记录
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kHistory);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw);
      if (list is! List) return;
      final turns = <ChatTurn>[];
      for (final item in list) {
        if (item is Map) {
          turns.add(ChatTurn.fromJson(item.map((k, v) => MapEntry('$k', v))));
        }
      }
      state = ChatState(turns: turns);
    } catch (_) {
      // 历史损坏：忽略
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = [for (final t in state.turns) t.toJson()];
      await prefs.setString(_kHistory, jsonEncode(data));
    } catch (_) {
      // 持久化失败不影响使用
    }
  }

  Future<void> send(String text) async {
    final message = text.trim();
    if (message.isEmpty || state.loading) return;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final turns = [
      ...state.turns,
      ChatTurn(id: id, role: 'user', text: message),
    ];
    state = ChatState(turns: turns, loading: true, selected: state.selected);
    try {
      final history = [
        for (final turn in turns.sublist(0, turns.length - 1))
          {'role': turn.role, 'content': turn.text},
      ];
      final reply = await ref
          .read(aiServiceProvider)
          .chat(message: message, history: history);
      final replyId = '${DateTime.now().microsecondsSinceEpoch}_a';
      final next = [
        ...turns,
        ChatTurn(id: replyId, role: 'assistant', text: reply),
      ];
      state = ChatState(
        turns: next.length > _maxTurns
            ? next.sublist(next.length - _maxTurns)
            : next,
        loading: false,
      );
      await _persist();
    } on AiException catch (e) {
      state = ChatState(turns: turns, loading: false, error: e.message);
    } catch (e) {
      state = ChatState(turns: turns, loading: false, error: '出错了：$e');
    }
  }

  /// 多选：切换某条消息的选中状态
  void toggleSelect(String id) {
    final selected = {...state.selected};
    if (!selected.remove(id)) selected.add(id);
    state = ChatState(
      turns: state.turns,
      loading: state.loading,
      error: state.error,
      selected: selected,
    );
  }

  /// 退出多选
  void clearSelection() {
    state = ChatState(
      turns: state.turns,
      loading: state.loading,
      error: state.error,
    );
  }

  /// 删除选中的消息
  Future<void> deleteSelected() async {
    if (state.selected.isEmpty) return;
    final turns = [
      for (final t in state.turns)
        if (!state.selected.contains(t.id)) t,
    ];
    state = ChatState(turns: turns, loading: state.loading, error: state.error);
    await _persist();
  }

  /// 清空全部对话
  Future<void> clear() async {
    state = const ChatState();
    await _persist();
  }
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(
  ChatNotifier.new,
);
