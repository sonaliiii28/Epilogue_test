import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../core/notification_service.dart';

const _deepPurple = Color(0xFF2E2540);
const _purple = Color(0xFF7A64A4);
const _cardBg = Color(0xFFF0EDF6);
const _bg1 = Color(0xFF74659A);
const _bg2 = Color(0xFFDFDBE5);

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _service = NotificationService();
  bool _loading = true;
  List<AppNotification> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _service.getInbox(limit: 100);
      if (!mounted) return;
      setState(() => _items = rows);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatWhen(AppNotification n) {
    final dt = n.sentAt ?? n.createdAt;
    if (dt == null) return '';
    final local = dt.isUtc ? dt.toLocal() : dt;
    return DateFormat('MMM d • h:mm a').format(local);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
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
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).maybePop(),
                      child: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Notifications',
                      style: GoogleFonts.nunito(
                        fontSize: 22,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh, color: Colors.white),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: _cardBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(color: _purple),
                        )
                      : _items.isEmpty
                      ? Center(
                          child: Text(
                            'No notifications',
                            style: GoogleFonts.nunito(
                              color: _deepPurple,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: _items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final n = _items[index];
                              final when = _formatWhen(n);

                              return GestureDetector(
                                onTap: () async {
                                  if (!n.isRead) {
                                    await _service.markRead(n.id);
                                    await _load();
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: n.isRead
                                          ? Colors.transparent
                                          : _purple.withOpacity(0.35),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 34,
                                        height: 34,
                                        decoration: BoxDecoration(
                                          color: _purple.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Icon(
                                          n.isRead
                                              ? Icons.notifications_none
                                              : Icons.notifications,
                                          color: _purple,
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              (n.title ?? 'Notification')
                                                  .trim(),
                                              style: GoogleFonts.nunito(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                                color: _deepPurple,
                                              ),
                                            ),
                                            if ((n.body ?? '')
                                                .trim()
                                                .isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 4,
                                                ),
                                                child: Text(
                                                  n.body!.trim(),
                                                  style: GoogleFonts.nunito(
                                                    fontSize: 13,
                                                    color: Colors.black87,
                                                    height: 1.25,
                                                  ),
                                                ),
                                              ),
                                            if (when.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 8,
                                                ),
                                                child: Text(
                                                  when,
                                                  style: GoogleFonts.nunito(
                                                    fontSize: 12,
                                                    color: Colors.black54,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
