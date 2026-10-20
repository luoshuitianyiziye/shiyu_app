import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/ai_client.dart';
import '../../../core/ai/ai_config.dart';

/// AI 配置（启动时加载；设置页保存后 invalidate 刷新）
final aiConfigProvider = FutureProvider<AiConfig>((ref) => AiConfig.load());

/// 聊天客户端（测试中可 override 为假实现）
final aiClientProvider = Provider<AiChat>((ref) => AiClient());
