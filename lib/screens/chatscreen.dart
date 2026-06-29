import 'package:flutter/material.dart';
import 'emergency_chat_widget.dart';

class ChatScreen extends StatelessWidget {
  final String requestId;
  final String senderRole;
  final String chatTitle;

  const ChatScreen({
    super.key,
    required this.requestId,
    required this.senderRole,
    required this.chatTitle,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C1E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              chatTitle,
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            const Text(
              "Emergency Chat",
              style: TextStyle(color: Colors.green, fontSize: 12),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: EmergencyChatWidget(
          requestId: requestId,
          senderRole: senderRole,
        ),
      ),
    );
  }
}