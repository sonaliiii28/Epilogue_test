import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../core/session_manager.dart';
import '../domain/models.dart' show CalendarEvent, EventType;
import 'calendar_service.dart';
import 'event_details_sheet.dart';
import 'premium_bottom_nav.dart';

const _deepPurple = Color(0xFF2E2540);
const _purple = Color(0xFF7A64A4);
const _cardBg = Color(0xFFF0EDF6);
const _bg1 = Color(0xFF74659A);
const _bg2 = Color(0xFFDFDBE5);

enum _CalendarCategory { medications, visits, other }

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  final _service = CalendarService();
  List<CalendarEvent> _events = [];

  bool _calendarExpanded = false;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  _CalendarCategory _category = _CalendarCategory.medications;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    final teamId = SessionManager().currentCareTeam?.id;
    if (teamId == null) return;

    final data = await _service.getEvents(teamId);
    if (!mounted) return;

    setState(() => _events = data);
  }

  bool _isOtherVisit(CalendarEvent e) {
    if (e.type != EventType.visit) return false;
    final normalized = e.title.trim().toLowerCase();
    return normalized == 'other visit' || normalized == 'other_visit';
  }

  String? _extractVisitorName(String? notes) {
    if (notes == null) return null;
    const prefix = '[[VISITOR]]:';
    if (!notes.startsWith(prefix)) return null;
    final v = notes.substring(prefix.length).trim();
    return v.isEmpty ? null : v;
  }

  List<CalendarEvent> get _selectedEvents {
    bool matchesCategory(CalendarEvent e) {
      switch (_category) {
        case _CalendarCategory.medications:
          return e.type == EventType.medication;
        case _CalendarCategory.visits:
          return e.type == EventType.visit && !_isOtherVisit(e);
        case _CalendarCategory.other:
          return (e.type == EventType.care || e.type == EventType.symptom) ||
              (e.type == EventType.visit && _isOtherVisit(e));
      }
    }

    return _events
        .where(
          (e) =>
              e.dateTime.year == _selectedDay.year &&
              e.dateTime.month == _selectedDay.month &&
              e.dateTime.day == _selectedDay.day &&
              matchesCategory(e),
        )
        .toList();
  }

  Color _getEventColor(EventType type) {
    switch (type) {
      case EventType.medication:
        return _purple;
      case EventType.visit:
        return Colors.red.shade400;
      case EventType.care:
        return Colors.blue.shade400;
      case EventType.symptom:
        return Colors.orange.shade400;
    }
  }

  IconData _getEventIcon(EventType type) {
    switch (type) {
      case EventType.medication:
        return Icons.medication;
      case EventType.visit:
        return Icons.local_hospital;
      case EventType.care:
        return Icons.health_and_safety;
      case EventType.symptom:
        return Icons.warning_amber_rounded;
    }
  }

  Widget _categoryPill({
    required _CalendarCategory value,
    required String label,
    required Color color,
  }) {
    final selected = _category == value;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => setState(() => _category = value),
      child: Container(
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color, width: 2),
        ),
        child: Text(
          label,
          style: GoogleFonts.nunito(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
            color: _deepPurple,
          ),
        ),
      ),
    );
  }

  void _openAddEventSheet() {
    final visitorNameCtrl = TextEditingController();
    final durationCtrl = TextEditingController();

    const eventTypeOptions = <String>[
      'Hospice visit',
      'Caregiver visit',
      'Family/Friend visit',
      'Other visit',
      'Reminder',
    ];

    String selectedEventType = eventTypeOptions.first;
    DateTime? selectedDate = _selectedDay;
    TimeOfDay selectedTime = TimeOfDay.now();
    int? duration;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          decoration: const BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text(
                    'Add Event',
                    style: GoogleFonts.nunito(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _deepPurple,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: eventTypeOptions.contains(selectedEventType)
                      ? selectedEventType
                      : eventTypeOptions.first,
                  decoration: _sheetInputDecoration(),
                  dropdownColor: Colors.white,
                  icon: const Icon(
                    Icons.keyboard_arrow_down,
                    color: _deepPurple,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w800,
                    color: _deepPurple,
                  ),
                  items: eventTypeOptions
                      .map(
                        (option) => DropdownMenuItem<String>(
                          value: option,
                          child: Text(
                            option,
                            style: GoogleFonts.nunito(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: _deepPurple,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setModal(() => selectedEventType = value);
                  },
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  tileColor: Colors.white,
                  title: Text(
                    'Date: ${DateFormat('yyyy-MM-dd').format(selectedDate!)}',
                    style: GoogleFonts.nunito(
                      fontWeight: FontWeight.w700,
                      color: _deepPurple,
                    ),
                  ),
                  trailing: const Icon(Icons.calendar_today, color: _purple),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      initialDate: selectedDate!,
                    );
                    if (picked != null) {
                      setModal(() => selectedDate = picked);
                    }
                  },
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  tileColor: Colors.white,
                  title: Text(
                    'Time: ${selectedTime.format(ctx)}',
                    style: GoogleFonts.nunito(
                      fontWeight: FontWeight.w700,
                      color: _deepPurple,
                    ),
                  ),
                  trailing: const Icon(Icons.access_time, color: _purple),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: ctx,
                      initialTime: selectedTime,
                    );
                    if (picked != null) {
                      setModal(() => selectedTime = picked);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: durationCtrl,
                  keyboardType: TextInputType.number,
                  decoration: _sheetInputDecoration(
                    hintText: 'Duration (minutes)',
                  ),
                  onChanged: (val) => duration = int.tryParse(val),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: visitorNameCtrl,
                  minLines: 1,
                  maxLines: 1,
                  keyboardType: TextInputType.name,
                  decoration: _sheetInputDecoration(hintText: "Visitor's name"),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _purple,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () async {
                      try {
                        final teamId = SessionManager().currentCareTeam?.id;
                        if (teamId == null) return;

                        final visitorName = visitorNameCtrl.text.trim();
                        if (visitorName.isEmpty) {
                          throw Exception('Visitor name is required');
                        }

                        final date = selectedDate;
                        if (date == null) {
                          throw Exception('Select date');
                        }

                        final dateTime = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          selectedTime.hour,
                          selectedTime.minute,
                        );

                        final now = DateTime.now();
                        if (dateTime.isBefore(now)) {
                          throw Exception(
                            'Cannot add past entries for this type',
                          );
                        }

                        final type = selectedEventType == 'Reminder'
                            ? EventType.care
                            : EventType.visit;
                        final title = selectedEventType;

                        await _service.addEvent(
                          careTeamId: teamId,
                          title: title,
                          dateTime: dateTime,
                          type: type,
                          notes: '[[VISITOR]]:$visitorName',
                          duration: duration,
                        );

                        await _loadEvents();
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                      } catch (e) {
                        if (!ctx.mounted) return;
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text(
                              e.toString().replaceFirst('Exception: ', ''),
                            ),
                          ),
                        );
                      }
                    },
                    child: Text(
                      'Save',
                      style: GoogleFonts.nunito(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _sheetInputDecoration({String? hintText}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: GoogleFonts.nunito(color: Colors.black45),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }

  void _openEventDetails(CalendarEvent event) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EventDetailsSheet(event: event),
    );
  }

  @override
  Widget build(BuildContext context) {
    final patientName =
        SessionManager().currentCareTeam?.patientFirstName ?? 'Patient';
    final now = DateTime.now();
    final todayLabel = DateFormat('MMMM d, yyyy').format(now);
    final timeLabel = DateFormat('h:mm a').format(now);

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
                      onTap: () => context.go('/dashboard'),
                      child: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Calendar',
                          style: GoogleFonts.nunito(
                            fontSize: 22,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          "$patientName's Schedule",
                          style: GoogleFonts.nunito(color: Colors.white70),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: _cardBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          setState(() {
                            _calendarExpanded = !_calendarExpanded;
                            if (!_calendarExpanded) {
                              _selectedDay = DateTime.now();
                              _focusedDay = _selectedDay;
                            }
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      todayLabel,
                                      style: GoogleFonts.nunito(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: _deepPurple,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      timeLabel,
                                      style: GoogleFonts.nunito(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                _calendarExpanded
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                color: _deepPurple,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_calendarExpanded) ...[
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
                                child: Row(
                                  children: [
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(
                                        Icons.chevron_left,
                                        color: _deepPurple,
                                      ),
                                      onPressed: () {
                                        final prev = DateTime(
                                          _focusedDay.year,
                                          _focusedDay.month - 1,
                                          1,
                                        );
                                        setState(() => _focusedDay = prev);
                                      },
                                    ),
                                    Expanded(
                                      child: Text(
                                        DateFormat(
                                          'MMMM yyyy',
                                        ).format(_focusedDay),
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.nunito(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: _deepPurple,
                                        ),
                                      ),
                                    ),
                                    InkWell(
                                      borderRadius: BorderRadius.circular(999),
                                      onTap: () {
                                        setState(() {
                                          _calendarFormat =
                                              _calendarFormat ==
                                                  CalendarFormat.month
                                              ? CalendarFormat.twoWeeks
                                              : CalendarFormat.month;
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                          border: Border.all(
                                            color: Colors.black12,
                                          ),
                                        ),
                                        child: Text(
                                          _calendarFormat ==
                                                  CalendarFormat.month
                                              ? '2 weeks'
                                              : 'Month',
                                          style: GoogleFonts.nunito(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            color: _deepPurple,
                                          ),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(
                                        Icons.chevron_right,
                                        color: _deepPurple,
                                      ),
                                      onPressed: () {
                                        final next = DateTime(
                                          _focusedDay.year,
                                          _focusedDay.month + 1,
                                          1,
                                        );
                                        setState(() => _focusedDay = next);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              TableCalendar(
                                firstDay: DateTime.utc(2020),
                                lastDay: DateTime.utc(2030),
                                focusedDay: _focusedDay,
                                calendarFormat: _calendarFormat,
                                headerVisible: false,
                                onPageChanged: (focusedDay) {
                                  setState(() => _focusedDay = focusedDay);
                                },
                                selectedDayPredicate: (day) =>
                                    isSameDay(_selectedDay, day),
                                onDaySelected: (selectedDay, focusedDay) {
                                  setState(() {
                                    _selectedDay = selectedDay;
                                    _focusedDay = focusedDay;
                                  });
                                },
                                daysOfWeekStyle: DaysOfWeekStyle(
                                  weekdayStyle: GoogleFonts.nunito(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black54,
                                  ),
                                  weekendStyle: GoogleFonts.nunito(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black54,
                                  ),
                                ),
                                calendarStyle: CalendarStyle(
                                  outsideDaysVisible: false,
                                  todayDecoration: BoxDecoration(
                                    color: Colors.blue.shade100,
                                    shape: BoxShape.circle,
                                  ),
                                  selectedDecoration: BoxDecoration(
                                    color: Colors.blue.shade400,
                                    shape: BoxShape.circle,
                                  ),
                                  selectedTextStyle: GoogleFonts.nunito(
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                  todayTextStyle: GoogleFonts.nunito(
                                    fontWeight: FontWeight.w800,
                                    color: _deepPurple,
                                  ),
                                  defaultTextStyle: GoogleFonts.nunito(
                                    fontWeight: FontWeight.w700,
                                    color: _deepPurple,
                                  ),
                                  weekendTextStyle: GoogleFonts.nunito(
                                    fontWeight: FontWeight.w700,
                                    color: _deepPurple,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _categoryPill(
                        value: _CalendarCategory.medications,
                        label: 'Medications',
                        color: Colors.blue.shade400,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _categoryPill(
                        value: _CalendarCategory.visits,
                        label: 'Visits',
                        color: Colors.red.shade400,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _categoryPill(
                        value: _CalendarCategory.other,
                        label: 'Other',
                        color: Colors.green.shade400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: _selectedEvents.isEmpty
                    ? Center(
                        child: Text(
                          'No events',
                          style: GoogleFonts.nunito(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.black45,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _selectedEvents.length,
                        itemBuilder: (_, i) {
                          final e = _selectedEvents[i];
                          final eventType = e.type;
                          final isAutoMedication =
                              eventType == EventType.medication &&
                              ((e.isAuto ?? false) ||
                                  e.source.toLowerCase() == 'medication');
                          final visitorName = _extractVisitorName(e.notes);

                          return GestureDetector(
                            onTap: () => _openEventDetails(e),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: _getEventColor(
                                        eventType,
                                      ).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      _getEventIcon(eventType),
                                      color: _getEventColor(eventType),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          e.title,
                                          style: GoogleFonts.nunito(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (isAutoMedication)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 6,
                                            ),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: _purple.withOpacity(
                                                  0.12,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                'Auto',
                                                style: GoogleFonts.nunito(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w800,
                                                  color: _purple,
                                                ),
                                              ),
                                            ),
                                          ),
                                        const SizedBox(height: 2),
                                        Text(
                                          DateFormat(
                                            'MMM d, yyyy • h:mm a',
                                          ).format(e.dateTime),
                                          style: GoogleFonts.nunito(
                                            fontSize: 13,
                                            color: Colors.black54,
                                          ),
                                        ),
                                        if (e.duration != null)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 6,
                                            ),
                                            child: Text(
                                              'Duration: ${e.duration} min',
                                              style: GoogleFonts.nunito(
                                                fontSize: 13,
                                                color: Colors.black87,
                                              ),
                                            ),
                                          ),
                                        if (e.severity != null)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 4,
                                            ),
                                            child: Text(
                                              'Severity: ${e.severity}',
                                              style: GoogleFonts.nunito(
                                                fontSize: 13,
                                                color: Colors.black87,
                                              ),
                                            ),
                                          ),
                                        if (visitorName != null)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 4,
                                            ),
                                            child: Text(
                                              'Visitor: $visitorName',
                                              style: GoogleFonts.nunito(
                                                fontSize: 13,
                                                color: Colors.black54,
                                              ),
                                            ),
                                          )
                                        else if (e.notes?.isNotEmpty ?? false)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 4,
                                            ),
                                            child: Text(
                                              e.notes!,
                                              style: GoogleFonts.nunito(
                                                fontSize: 13,
                                                color: Colors.black54,
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
              const PremiumBottomNav(currentIndex: 1),
            ],
          ),
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: FloatingActionButton(
          backgroundColor: _purple,
          onPressed: _openAddEventSheet,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
