import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/widgets/app_feedback.dart';
import '../../auth/application/auth_session.dart';
import '../data/chatbot_repository.dart';
import '../domain/chatbot_models.dart';

final chatbotControllerProvider =
    ChangeNotifierProvider.autoDispose<ChatbotController>((ref) {
      return ChatbotController(ref.watch(chatbotRepositoryProvider));
    });

class ChatbotController extends ChangeNotifier {
  ChatbotController(this._repository);

  final ChatbotRepository _repository;

  bool loading = true;
  bool sending = false;
  String? error;
  ChatSessionSummary? session;
  ChatSessionState? sessionState;
  ChatbotActionSummary? pendingAction;
  final List<ChatBubble> bubbles = [];

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await _repository.loadMe();
      final sessions = await _repository.listSessions();
      sessions.sort((a, b) => b.lastActivityAt.compareTo(a.lastActivityAt));
      session = sessions.isEmpty
          ? await _repository.createSession()
          : sessions.first;
      final currentSession = session!;
      final messages = await _repository.loadMessages(currentSession.id);
      bubbles
        ..clear()
        ..addAll(messages.map(ChatBubble.fromRecord));
      if (bubbles.isEmpty) {
        bubbles.add(
          const ChatBubble.assistant(
            'Hi, I’m your Oslava admin assistant. Ask me about events, workers, staffing, or prepare an admin action for review.',
          ),
        );
      }
      pendingAction = (await _repository.loadPendingAction(currentSession.id))
          .pendingAction;
    } catch (e) {
      error = readableChatbotError(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> startNewChat() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      session = await _repository.createSession();
      sessionState = null;
      pendingAction = null;
      bubbles
        ..clear()
        ..add(
          const ChatBubble.assistant(
            'New chat started. What would you like to manage?',
          ),
        );
    } catch (e) {
      error = readableChatbotError(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> send(String message) async {
    final text = message.trim();
    final currentSession = session;
    if (text.isEmpty || currentSession == null || sending) return;
    sending = true;
    error = null;
    bubbles.add(ChatBubble.user(text));
    notifyListeners();
    try {
      final response = await _repository.sendMessage(
        sessionId: currentSession.id,
        message: text,
      );
      _appendTurn(response);
    } catch (e) {
      error = readableChatbotError(e);
      bubbles.add(ChatBubble.assistant(error!));
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  Future<void> choose(EntitySelection selection, EntitySelectionOption option) {
    return send(
      'Use ${selection.entityType} ${option.displayName} (${option.id}).',
    );
  }

  Future<void> confirm(ChatbotActionSummary action) async {
    if (sending) return;
    sending = true;
    error = null;
    notifyListeners();
    try {
      final response = await _repository.confirmAction(action.id);
      pendingAction = null;
      _appendTurn(response);
    } catch (e) {
      error = readableChatbotError(e);
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  Future<void> cancel(ChatbotActionSummary action) async {
    if (sending) return;
    sending = true;
    error = null;
    notifyListeners();
    try {
      final response = await _repository.cancelAction(action.id);
      pendingAction = null;
      _appendTurn(response);
    } catch (e) {
      error = readableChatbotError(e);
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  void _appendTurn(ChatTurnResponse response) {
    sessionState = response.sessionState ?? sessionState;
    final payload = response.response;
    bubbles.add(ChatBubble.assistant(payload.content, payload: payload));
    if (payload.type == ChatbotResponseType.confirmationRequired) {
      pendingAction = payload.action;
    }
  }
}

class AdminChatbotScreen extends ConsumerStatefulWidget {
  const AdminChatbotScreen({required this.role, super.key});

  final AppRole role;

  @override
  ConsumerState<AdminChatbotScreen> createState() => _AdminChatbotScreenState();
}

class _AdminChatbotScreenState extends ConsumerState<AdminChatbotScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatbotControllerProvider).load();
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(chatbotControllerProvider);
    ref.listen(chatbotControllerProvider, (_, _) => _scrollToBottomSoon());
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin AI'),
        actions: [
          IconButton(
            tooltip: 'New chat',
            onPressed: controller.loading || controller.sending
                ? null
                : () => ref.read(chatbotControllerProvider).startNewChat(),
            icon: const Icon(Icons.add_comment_outlined),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: controller.loading
                ? null
                : () => ref.read(chatbotControllerProvider).load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (controller.loading) const LinearProgressIndicator(),
            if (controller.error != null && !controller.loading)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: AppNotice(message: controller.error!, isError: true),
              ),
            if (controller.sessionState?.hasContext == true)
              _ContextStrip(state: controller.sessionState!),
            Expanded(child: _buildMessages(controller)),
            _Composer(
              controller: _messageController,
              enabled: !controller.loading && !controller.sending,
              sending: controller.sending,
              onSend: () {
                final text = _messageController.text;
                _messageController.clear();
                ref.read(chatbotControllerProvider).send(text);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages(ChatbotController controller) {
    if (controller.loading && controller.bubbles.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.error != null && controller.bubbles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: AppEmptyState(
            icon: Icons.smart_toy_outlined,
            title: 'AI assistant unavailable',
            message: controller.error!,
            action: FilledButton.icon(
              onPressed: () => ref.read(chatbotControllerProvider).load(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: controller.bubbles.length,
      itemBuilder: (context, index) => _BubbleCard(
        bubble: controller.bubbles[index],
        sending: controller.sending,
        onSelect: (selection, option) =>
            ref.read(chatbotControllerProvider).choose(selection, option),
        onConfirm: (action) =>
            ref.read(chatbotControllerProvider).confirm(action),
        onCancel: (action) =>
            ref.read(chatbotControllerProvider).cancel(action),
      ),
    );
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }
}

class ChatBubble {
  const ChatBubble({required this.content, required this.isUser, this.payload});

  const ChatBubble.user(String content) : this(content: content, isUser: true);

  const ChatBubble.assistant(String content, {ChatbotResponsePayload? payload})
    : this(content: content, isUser: false, payload: payload);

  final String content;
  final bool isUser;
  final ChatbotResponsePayload? payload;

  factory ChatBubble.fromRecord(ChatMessageRecord record) {
    return ChatBubble(content: record.content, isUser: record.role == 'USER');
  }
}

class _BubbleCard extends StatelessWidget {
  const _BubbleCard({
    required this.bubble,
    required this.sending,
    required this.onSelect,
    required this.onConfirm,
    required this.onCancel,
  });

  final ChatBubble bubble;
  final bool sending;
  final void Function(EntitySelection selection, EntitySelectionOption option)
  onSelect;
  final ValueChanged<ChatbotActionSummary> onConfirm;
  final ValueChanged<ChatbotActionSummary> onCancel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final align = bubble.isUser ? Alignment.centerRight : Alignment.centerLeft;
    final background = bubble.isUser
        ? colorScheme.primary
        : colorScheme.surfaceContainerHighest;
    final foreground = bubble.isUser
        ? colorScheme.onPrimary
        : colorScheme.onSurfaceVariant;
    final payload = bubble.payload;
    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          color: background,
          elevation: bubble.isUser ? 0 : 1,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  bubble.content,
                  style: TextStyle(color: foreground, height: 1.35),
                ),
                if (payload?.selection != null) ...[
                  const SizedBox(height: 12),
                  for (final option in payload!.selection!.options)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OutlinedButton.icon(
                        onPressed: sending
                            ? null
                            : () => onSelect(payload.selection!, option),
                        icon: const Icon(Icons.touch_app_outlined),
                        label: Align(
                          alignment: Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(option.displayName),
                              Text(
                                option.subtitle,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
                if (payload?.action != null &&
                    payload!.type == ChatbotResponseType.confirmationRequired)
                  _ActionConfirmationCard(
                    action: payload.action!,
                    sending: sending,
                    onConfirm: onConfirm,
                    onCancel: onCancel,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionConfirmationCard extends StatelessWidget {
  const _ActionConfirmationCard({
    required this.action,
    required this.sending,
    required this.onConfirm,
    required this.onCancel,
  });

  final ChatbotActionSummary action;
  final bool sending;
  final ValueChanged<ChatbotActionSummary> onConfirm;
  final ValueChanged<ChatbotActionSummary> onCancel;

  @override
  Widget build(BuildContext context) {
    final entries = action.summary.entries.toList();
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user_outlined),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Confirm ${action.type.replaceAll('_', ' ')}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          if (action.expiresAt != null) ...[
            const SizedBox(height: 6),
            Text('Expires: ${action.expiresAt!.toLocal()}'),
          ],
          const SizedBox(height: 12),
          for (final entry in entries.take(8))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('${_label(entry.key)}: ${entry.value}'),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: sending ? null : () => onCancel(action),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: sending ? null : () => onConfirm(action),
                  icon: const Icon(Icons.check),
                  label: const Text('Confirm'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _label(String key) {
    final words = key
        .replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ${match.group(1)}')
        .replaceAll('_', ' ')
        .trim()
        .split(RegExp(r'\s+'));
    return words
        .map(
          (word) => word.isEmpty
              ? word
              : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }
}

class _ContextStrip extends StatelessWidget {
  const _ContextStrip({required this.state});

  final ChatSessionState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (state.currentEventLabel != null)
            Chip(
              avatar: const Icon(Icons.event_outlined),
              label: Text(state.currentEventLabel!),
            ),
          if (state.currentWorkerLabel != null)
            Chip(
              avatar: const Icon(Icons.person_outline),
              label: Text(state.currentWorkerLabel!),
            ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: 'Ask about events, workers, or admin actions…',
                prefixIcon: Icon(Icons.smart_toy_outlined),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: enabled ? onSend : null,
            child: sending
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }
}
