import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:accident_app/shared/models/chat_message.dart';
import 'package:accident_app/shared/models/emergency_service.dart';
import 'package:accident_app/shared/services/gemini_service.dart';
import 'package:accident_app/shared/services/offline_qa_service.dart';
import 'package:accident_app/shared/providers/app_state.dart';

final chatProvider =
    NotifierProvider<ChatNotifier, List<ChatMessage>>(ChatNotifier.new);

final isAiOnlineProvider = FutureProvider<bool>((ref) async {
  final result = await Connectivity().checkConnectivity();
  return !result.contains(ConnectivityResult.none);
});

class ChatNotifier extends Notifier<List<ChatMessage>> {
  @override
  List<ChatMessage> build() {
    // Pre-load offline Q&A on startup
    Future.microtask(() async {
      await ref.read(offlineQaServiceProvider).load();
    });
    return [];
  }

  /// Send a user message and generate a response.
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    // Add user message
    final userMsg = ChatMessage(role: ChatRole.user, content: text.trim());
    state = [...state, userMsg];

    // Add typing indicator
    final typingMsg = ChatMessage(
      role: ChatRole.assistant,
      content: '...',
    );
    state = [...state, typingMsg];

    String response;
    bool offline = false;

    try {
      // Check connectivity
      final connectivity = await Connectivity().checkConnectivity();
      final isOnline = !connectivity.contains(ConnectivityResult.none);

      if (isOnline) {
        // Try Gemini
        final position = ref.read(lastPositionProvider);
        final pois = ref.read(sortedServicesProvider);

        final geminiResponse = await ref.read(geminiServiceProvider).generateResponse(
          userMessage: text.trim(),
          lat: position?.latitude,
          lng: position?.longitude,
          nearbyPois: pois.take(10).toList(),
        );

        if (geminiResponse != null) {
          response = geminiResponse;
        } else {
          // Gemini failed, fall back to offline
          offline = true;
          response = _offlineAnswer(text.trim(), pois);
        }
      } else {
        offline = true;
        final pois = ref.read(sortedServicesProvider);
        response = _offlineAnswer(text.trim(), pois);
      }
    } catch (e) {
      offline = true;
      response = 'Call 112 for immediate help.';
    }

    // Remove typing indicator, add real response
    final msgs = state.where((m) => m.id != typingMsg.id).toList();
    final assistantMsg = ChatMessage(
      role: ChatRole.assistant,
      content: response,
      isOffline: offline,
    );
    state = [...msgs, assistantMsg];
  }

  String _offlineAnswer(String query, List<EmergencyService> pois) {
    final nearest = pois.isNotEmpty ? pois.first : null;
    return ref.read(offlineQaServiceProvider).answer(query, nearestHospital: nearest);
  }

  void clear() {
    state = [];
  }
}
