import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'premium_bottom_nav.dart';

const _deepPurple = Color(0xFF2E2540);
const _purple = Color(0xFF7A64A4);
const _mutedPurple = Color(0xFF6C648B);
const _lightPurple = Color(0xFFB0A8C8);
const _borderColor = Color(0xFFD4CDDF);
const _bg1 = Color(0xFF74659A);
const _bg2 = Color(0xFFDFDBE5);

// Audience options
enum MessageAudience { family, medical, everyone }

extension AudienceExt on MessageAudience {
  String get label {
    switch (this) {
      case MessageAudience.family:
        return 'Family only';
      case MessageAudience.medical:
        return 'Medical care team only';
      case MessageAudience.everyone:
        return 'Everyone';
    }
  }

  IconData get icon {
    switch (this) {
      case MessageAudience.family:
        return Icons.home_outlined;
      case MessageAudience.medical:
        return Icons.medical_services_outlined;
      case MessageAudience.everyone:
        return Icons.groups_outlined;
    }
  }

  Color get color {
    switch (this) {
      case MessageAudience.family:
        return const Color(0xFF7A64A4);
      case MessageAudience.medical:
        return const Color(0xFF4A8FD4);
      case MessageAudience.everyone:
        return const Color(0xFF5BAD8A);
    }
  }
}

// Demo message model (not yet in Supabase)
class _Message {
  final String id;
  final String senderName;
  final String content;
  final MessageAudience audience;
  final DateTime sentAt;
  final bool isMe;

  const _Message({
    required this.id,
    required this.senderName,
    required this.content,
    required this.audience,
    required this.sentAt,
    required this.isMe,
  });
}

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  MessageAudience _selectedAudience = MessageAudience.everyone;
  final _messageCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  // Demo messages Ã¢â‚¬â€ replace with Supabase later
  final List<_Message> _messages = [
    _Message(
      id: '1',
      senderName: 'Sarah (Nurse)',
      content:
          'Good morning. I reviewed the medication log. Everything looks good. Let me know if pain increases.',
      audience: MessageAudience.everyone,
      sentAt: DateTime.now().subtract(const Duration(hours: 3)),
      isMe: false,
    ),
    _Message(
      id: '2',
      senderName: 'You',
      content:
          'Dad had a rough night. Pain around 2am, gave morphine as scheduled. He settled after about 30 min.',
      audience: MessageAudience.everyone,
      sentAt: DateTime.now().subtract(const Duration(hours: 2)),
      isMe: true,
    ),
    _Message(
      id: '3',
      senderName: 'Mom',
      content: 'I can come over this afternoon if you need a break.',
      audience: MessageAudience.family,
      sentAt: DateTime.now().subtract(const Duration(hours: 1)),
      isMe: false,
    ),
    _Message(
      id: '4',
      senderName: 'Dr. Patel',
      content:
          'Reviewed the symptom log. The restlessness may be terminal agitation. I will call this evening.',
      audience: MessageAudience.medical,
      sentAt: DateTime.now().subtract(const Duration(minutes: 30)),
      isMe: false,
    ),
  ];

  // Filter tab
  MessageAudience? _filterAudience;

  List<_Message> get _filtered {
    if (_filterAudience == null) return _messages;
    return _messages.where((m) => m.audience == _filterAudience).toList();
  }

  void _sendMessage() {
    final text = _messageCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(
        _Message(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          senderName: 'You',
          content: text,
          audience: _selectedAudience,
          sentAt: DateTime.now(),
          isMe: true,
        ),
      );
      _messageCtrl.clear();
    });

    // Scroll to bottom
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_bg1, _bg2],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Ã¢â€â‚¬Ã¢â€â‚¬ Header Ã¢â€â‚¬Ã¢â€â‚¬
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/dashboard');
                        }
                      },
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.4),
                          ),
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new,
                          size: 15,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Messages',
                            style: GoogleFonts.nunito(
                              fontSize: 26,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Care team communication',
                            style: GoogleFonts.nunito(
                              fontSize: 15,
                              color: Colors.white.withOpacity(0.75),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // Ã¢â€â‚¬Ã¢â€â‚¬ Filter tabs Ã¢â€â‚¬Ã¢â€â‚¬
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _filterChip(null, 'All'),
                    ...MessageAudience.values.map(
                      (a) => _filterChip(a, a.label),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Divider(color: _borderColor, thickness: 1),
              ),

              // Ã¢â€â‚¬Ã¢â€â‚¬ Messages list Ã¢â€â‚¬Ã¢â€â‚¬
              Expanded(
                child: filtered.isEmpty
                    ? _emptyState()
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final msg = filtered[i];
                          final showDate =
                              i == 0 ||
                              !_isSameDay(filtered[i - 1].sentAt, msg.sentAt);
                          return Column(
                            children: [
                              if (showDate) _dateDivider(msg.sentAt),
                              _messageBubble(msg),
                            ],
                          );
                        },
                      ),
              ),

              // Ã¢â€â‚¬Ã¢â€â‚¬ Compose area Ã¢â€â‚¬Ã¢â€â‚¬
              _composeArea(),

              const PremiumBottomNav(currentIndex: 0),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChip(MessageAudience? audience, String label) {
    final isSelected = _filterAudience == audience;
    final color = audience != null ? audience.color : _purple;

    return GestureDetector(
      onTap: () => setState(() => _filterAudience = audience),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withOpacity(0.15)
              : Colors.white.withOpacity(0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : _borderColor,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.nunito(
            fontSize: 16,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
            color: isSelected ? color : _mutedPurple,
          ),
        ),
      ),
    );
  }

  Widget _dateDivider(DateTime date) {
    final label = _isSameDay(date, DateTime.now())
        ? 'Today'
        : _isSameDay(date, DateTime.now().subtract(const Duration(days: 1)))
        ? 'Yesterday'
        : DateFormat('MMM d').format(date);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: _borderColor, thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: GoogleFonts.nunito(fontSize: 15, color: _lightPurple),
            ),
          ),
          Expanded(child: Divider(color: _borderColor, thickness: 1)),
        ],
      ),
    );
  }

  Widget _messageBubble(_Message msg) {
    final audienceColor = msg.audience.color;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: msg.isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!msg.isMe) ...[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: audienceColor.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  msg.senderName[0].toUpperCase(),
                  style: GoogleFonts.nunito(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: audienceColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: msg.isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!msg.isMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 3),
                    child: Text(
                      msg.senderName,
                      style: GoogleFonts.nunito(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _mutedPurple,
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: msg.isMe
                        ? const Color(0xFF6B5B8E)
                        : Colors.white.withOpacity(0.8),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(msg.isMe ? 16 : 4),
                      bottomRight: Radius.circular(msg.isMe ? 4 : 16),
                    ),
                    border: msg.isMe ? null : Border.all(color: _borderColor),
                  ),
                  child: Text(
                    msg.content,
                    style: GoogleFonts.nunito(
                      fontSize: 15,
                      color: msg.isMe ? Colors.white : _deepPurple,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: audienceColor.withOpacity(0.6),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      msg.audience.label,
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        color: _lightPurple,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      DateFormat('h:mm a').format(msg.sentAt),
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        color: _lightPurple,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (msg.isMe) const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _composeArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.6),
        border: Border(top: BorderSide(color: _borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Audience selector
          Row(
            children: [
              Text(
                'Send to:',
                style: GoogleFonts.nunito(
                  fontSize: 15,
                  color: _mutedPurple,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              ...MessageAudience.values.map((a) {
                final isSelected = _selectedAudience == a;
                return GestureDetector(
                  onTap: () => setState(() => _selectedAudience = a),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? a.color.withOpacity(0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? a.color : _borderColor,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          a.icon,
                          size: 11,
                          color: isSelected ? a.color : _lightPurple,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          a == MessageAudience.family
                              ? 'Family'
                              : a == MessageAudience.medical
                              ? 'Medical'
                              : 'Everyone',
                          style: GoogleFonts.nunito(
                            fontSize: 16,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: isSelected ? a.color : _lightPurple,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 8),

          // Text input + send
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: _borderColor),
                  ),
                  child: TextField(
                    controller: _messageCtrl,
                    maxLines: null,
                    style: GoogleFonts.nunito(fontSize: 15, color: _deepPurple),
                    decoration: InputDecoration(
                      hintText: 'Write a message...',
                      hintStyle: GoogleFonts.nunito(
                        fontSize: 15,
                        color: const Color(0xFFB8B0CC),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _sendMessage,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6B5B8E),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _purple.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.send_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFE1DCEA),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.chat_bubble_outline_rounded,
              size: 32,
              color: _lightPurple,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: GoogleFonts.nunito(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _deepPurple,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Send the first message below',
            style: GoogleFonts.nunito(fontSize: 15, color: _mutedPurple),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

