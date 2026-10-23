import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/ai_sessions.dart';
import '../../core/session.dart';
import 'ai_chat_page.dart';

/// Landing page after sign-in: the assistant opens directly with the most
/// recent conversation (or an empty one), like a chat app.
class AssistantRoot extends ConsumerStatefulWidget {
  const AssistantRoot({super.key});

  @override
  ConsumerState<AssistantRoot> createState() => _AssistantRootState();
}

class _AssistantRootState extends ConsumerState<AssistantRoot> {
  AiSession? _session;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = ref.read(sessionProvider).user?.id;
    List<AiSession> sessions = const [];
    if (userId != null) {
      sessions = await AiSessionStore.load(userId);
    }
    if (!mounted) return;
    setState(() {
      _session = sessions.isEmpty ? null : sessions.first;
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return AiChatPage(
      key: ValueKey(_session?.id ?? 'new'),
      global: true,
      session: _session,
    );
  }
}
