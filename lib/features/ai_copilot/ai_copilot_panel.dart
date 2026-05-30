import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:accident_app/shared/models/chat_message.dart';
import 'package:accident_app/shared/providers/chat_provider.dart';

class AiCopilotPanel extends ConsumerStatefulWidget {
  const AiCopilotPanel({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AiCopilotPanel(),
    );
  }

  @override
  ConsumerState<AiCopilotPanel> createState() => _AiCopilotPanelState();
}

class _AiCopilotPanelState extends ConsumerState<AiCopilotPanel> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  static const _quickChips = [
    'Stop the bleeding',
    'Victim unconscious',
    'What to do while waiting',
    'Nearest hospital?',
    'Describe my location',
    'My legal rights as helper',
  ];

  void _sendMessage(String text) {
    if (text.trim().isEmpty) return;
    _controller.clear();
    ref.read(chatProvider.notifier).sendMessage(text);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatProvider);
    final isAiOnline = ref.watch(isAiOnlineProvider).valueOrNull ?? false;
    final screenH = MediaQuery.of(context).size.height;

    return Container(
      height: screenH * 0.85,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.smart_toy_outlined, size: 20),
                const SizedBox(width: 10),
                const Text(
                  'Emergency Assistant',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const Spacer(),
                // Connectivity badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isAiOnline
                        ? Colors.green.withValues(alpha: 0.15)
                        : Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isAiOnline ? Colors.green : Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isAiOnline ? 'AI Active' : 'Offline — Quick Answers',
                        style: TextStyle(
                          fontSize: 11,
                          color: isAiOnline ? Colors.green : Colors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Quick chips
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _quickChips.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ActionChip(
                label: Text(
                  _quickChips[i],
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                backgroundColor:
                    Theme.of(context).colorScheme.primaryContainer,
                onPressed: () => _sendMessage(_quickChips[i]),
              ),
            ),
          ),
          const Divider(height: 12),
          // Chat scroll
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.chat_bubble_outline,
                          size: 48,
                          color: Colors.white24,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Tap a chip or type a question.\nI can help with first aid, hospitals, and legal rights.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white38, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: messages.length,
                    itemBuilder: (_, i) =>
                        _ChatBubble(message: messages[i]),
                  ),
          ),
          // Disclaimer
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Bystander guidance only — not a substitute for professional medical care.',
              style: TextStyle(
                fontSize: 10.5,
                color: Colors.white.withValues(alpha: 0.35),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // Input
          Container(
            padding: EdgeInsets.fromLTRB(
                16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onSubmitted: _sendMessage,
                    textInputAction: TextInputAction.send,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Ask about first aid, hospitals, legal rights…',
                      hintStyle: const TextStyle(fontSize: 13, color: Colors.white38),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24)),
                      filled: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton.small(
                  heroTag: 'chat_send',
                  onPressed: () => _sendMessage(_controller.text),
                  child: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final isTyping = message.content == '...';
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: colorScheme.primaryContainer,
              child: Icon(Icons.smart_toy_outlined,
                  size: 16, color: colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
              ),
              child: isTyping
                  ? const _TypingIndicator()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message.content,
                          style: TextStyle(
                            color: isUser
                                ? colorScheme.onPrimary
                                : colorScheme.onSurface,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        if (!isUser && message.isOffline)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Offline answer',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.orange.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) {
            final offset = (((_ctrl.value * 3) - i) % 1).clamp(0.0, 1.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 6,
              height: 6 + (offset * 4),
              decoration: BoxDecoration(
                color: Colors.white54,
                borderRadius: BorderRadius.circular(3),
              ),
            );
          },
        );
      }),
    );
  }
}
