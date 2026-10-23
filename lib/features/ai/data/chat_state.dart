import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/ai_client.dart';
import '../application/ai_service.dart';

/// 一条聊天消息（role: user / assistant）
class ChatTurn {
  const ChatTurn({required this.role, required this.text});

  final String role;
  final String text;

  bool get isUser => role == 'user';
}

class ChatState {
  const ChatState({this.turns = const [], this.loading = false, this.error});

  final List<ChatTurn> turns;
  final bool loading;
  final String? error;
}

class ChatNotifier extends Notifier<ChatState> {
  @override
  ChatState build() => const ChatState();

  Future<void> send(String text) async {
    final message = text.trim();
    if (message.isEmpty || state.loading) return;
    final turns = [...state.turns, ChatTurn(role: 'user', text: message)];
    state = ChatState(turns: turns, loading: true);
    try {
      final history = [
        for (final turn in turns.sublist(0, turns.length - 1))
          {'role': turn.role, 'content': turn.text},
      ];
      final reply = await ref
          .read(aiServiceProvider)
          .chat(message: message, history: history);
      state = ChatState(
        turns: [
          ...turns,
          ChatTurn(role: 'assistant', text: reply),
        ],
        loading: false,
      );
    } on AiException catch (e) {
      state = ChatState(turns: turns, loading: false, error: e.message);
    } catch (e) {
      state = ChatState(turns: turns, loading: false, error: '出错了：$e');
    }
  }

  void clear() => state = const ChatState();
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(
  ChatNotifier.new,
);
