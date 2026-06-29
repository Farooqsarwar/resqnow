import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EmergencyChatService {
  final SupabaseClient _supabase = Supabase.instance.client;

  String? get currentUserId => _supabase.auth.currentUser?.id;

  Future<void> sendMessage({
    required String requestId,
    required String senderRole,
    required String text,
  }) async {
    if (text.trim().isEmpty || currentUserId == null) return;

    try {
      await _supabase.from('emergency_chat_messages').insert({
        'request_id': requestId,
        'sender_id': currentUserId,
        'sender_role': senderRole,
        'message': text.trim(),
      });
    } catch (e) {
      debugPrint('Error sending message: $e');
    }
  }
  Future<List<Map<String, dynamic>>> loadMessages(String requestId) async {
    final data = await _supabase
        .from('emergency_chat_messages')
        .select()
        .eq('request_id', requestId)
        .order('created_at', ascending: true);

    return List<Map<String, dynamic>>.from(data);
  }

  RealtimeChannel subscribe(
      String requestId, void Function(Map<String, dynamic>) onNewMessage) {
    return _supabase
        .channel('emergency_chat_$requestId')
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'emergency_chat_messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'request_id',
        value: requestId,
      ),
      callback: (payload) {
        onNewMessage(payload.newRecord);
      },
    )
        .subscribe();
  }
}