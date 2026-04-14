import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/supabase_service.dart';
import '../domain/models.dart' as models;

class CalendarOperationException implements Exception {
  const CalendarOperationException(
    this.userMessage, {
    required this.operationType,
    this.retryable = false,
  });

  final String userMessage;
  final String operationType;
  final bool retryable;

  @override
  String toString() => userMessage;
}

class _PendingCalendarOperation {
  const _PendingCalendarOperation({
    required this.key,
    required this.timestamp,
    required this.run,
  });

  final String key;
  final DateTime timestamp;
  final Future<void> Function() run;
}

class CalendarService {
  CalendarService();

  final _client = Supabase.instance.client;

  static final List<_PendingCalendarOperation> _pendingOperations =
      <_PendingCalendarOperation>[];

  Future<bool> _useDocxCalendar() => SupabaseService().isDocxCalendarSchema();

  models.EventType _mapDocxEventType(String raw) {
    if (raw == 'medication') return models.EventType.medication;
    if (raw.endsWith('_visit')) return models.EventType.visit;
    if (raw == 'reminder') return models.EventType.care;
    return models.EventType.care;
  }

  String _docxEventTypeFor(models.EventType type) {
    if (type == models.EventType.medication) return 'medication';
    if (type == models.EventType.visit) return 'other_visit';
    return 'reminder';
  }

  String _docxCategoryFor(models.EventType type) {
    if (type == models.EventType.medication) return 'medications';
    if (type == models.EventType.visit) return 'visits';
    return 'other';
  }

  Map<String, dynamic> _docxNotesFromLegacy(Map<String, dynamic> legacy) {
    return <String, dynamic>{
      'notes': legacy['notes'],
      'severity': legacy['severity'],
      'is_overridden': legacy['is_overridden'],
      'is_auto': legacy['is_auto'],
    }..removeWhere((_, v) => v == null);
  }

  Map<String, dynamic> _legacyToDocxInsertPayload(Map<String, dynamic> legacy) {
    final rawType = (legacy['event_type'] ?? '').toString();
    final mapped = rawType == models.EventType.medication.name
        ? models.EventType.medication
        : rawType == models.EventType.visit.name
        ? models.EventType.visit
        : rawType == models.EventType.care.name
        ? models.EventType.care
        : models.EventType.care;

    return <String, dynamic>{
      'calendar_event_id': legacy['id'],
      'care_space_id': legacy['care_team_id'],
      'event_type': _docxEventTypeFor(mapped),
      'category': _docxCategoryFor(mapped),
      'scheduled_at': legacy['date'],
      'duration_minutes': legacy['duration'],
      'title': legacy['title'],
      'detail': null,
      'notes': jsonEncode(_docxNotesFromLegacy(legacy)),
      'source': legacy['source'] ?? 'manual',
      'source_medication_id': legacy['related_id'],
      'created_by': _client.auth.currentUser?.id,
    }..removeWhere((_, v) => v == null);
  }

  Future<List<models.CalendarEvent>> getEvents(String careTeamId) async {
    await retryPendingOperations();

    try {
      final useDocx = await _useDocxCalendar();
      if (useDocx) {
        final res = await _client
            .from('calendar_events')
            .select(
              'calendar_event_id, care_space_id, title, scheduled_at, event_type, source, created_by, notes, duration_minutes, source_medication_id, created_at, deleted_at',
            )
            .eq('care_space_id', careTeamId)
            .isFilter('deleted_at', null)
            .order('scheduled_at');

        final rows = (res as List).cast<Map<String, dynamic>>();
        return rows
            .map((row) {
              final notesRaw = (row['notes'] ?? '').toString();
              Map<String, dynamic>? legacy;
              try {
                final decoded = jsonDecode(notesRaw);
                if (decoded is Map) {
                  legacy = decoded.cast<String, dynamic>();
                }
              } catch (_) {
                legacy = null;
              }

              final isOverridden = legacy?['is_overridden'] == true;
              final eventType = _mapDocxEventType(
                (row['event_type'] ?? '').toString(),
              );

              final scheduledAt = row['scheduled_at'];
              final dateTime = scheduledAt is String
                  ? DateTime.parse(scheduledAt)
                  : scheduledAt as DateTime;

              return models.CalendarEvent(
                id: (row['calendar_event_id'] ?? '').toString(),
                careTeamId: (row['care_space_id'] ?? '').toString(),
                title: (row['title'] ?? '').toString(),
                dateTime: dateTime,
                type: eventType,
                source: (row['source'] ?? 'manual').toString(),
                createdBy: (row['created_by'] ?? '').toString().trim().isEmpty
                    ? null
                    : (row['created_by'] ?? '').toString(),
                notes: legacy?['notes']?.toString(),
                duration: row['duration_minutes'] as int?,
                severity: legacy?['severity']?.toString(),
                relatedId:
                    (row['source_medication_id'] ?? '')
                        .toString()
                        .trim()
                        .isEmpty
                    ? null
                    : (row['source_medication_id'] ?? '').toString(),
                isAuto: (row['source'] ?? '').toString() != 'manual',
                isOverridden: isOverridden,
                createdAt: row['created_at'] is String
                    ? DateTime.tryParse(row['created_at'] as String)
                    : row['created_at'] as DateTime?,
              );
            })
            .where((event) => event.isOverridden != true)
            .toList();
      }

      final res = await _client
          .from('calendar_events')
          .select()
          .eq('care_team_id', careTeamId)
          .order('date');

      return (res as List)
          .map(
            (e) => models.CalendarEvent.fromJson(Map<String, dynamic>.from(e)),
          )
          .where((event) => event.isOverridden != true)
          .toList();
    } catch (error) {
      _logFailure('fetch_events', error);
      throw _mapError(error, operationType: 'fetch_events');
    }
  }

  Future<void> retryPendingOperations() async {
    if (_pendingOperations.isEmpty) return;

    final pending = List<_PendingCalendarOperation>.from(_pendingOperations)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    for (final operation in pending) {
      try {
        await operation.run();
        _pendingOperations.removeWhere((item) => item.key == operation.key);
      } catch (error) {
        _logFailure('retry_pending_operation', error);
        if (_isNetworkFailure(error)) {
          break;
        }
        _pendingOperations.removeWhere((item) => item.key == operation.key);
      }
    }
  }

  Future<void> safeInsertEvent(
    Map<String, dynamic> eventData, {
    String operationType = 'insert_event',
    String? queueKey,
  }) async {
    final normalizedData = _normalizeEventPayload(eventData);

    final useDocx = await _useDocxCalendar();
    final payload = useDocx
        ? _legacyToDocxInsertPayload(normalizedData)
        : normalizedData;

    Future<void> run() async {
      if (await _isMedicationDuplicate(normalizedData, useDocx: useDocx)) {
        debugPrint(
          '[Calendar][$operationType] Duplicate skipped for '
          'related_id=${normalizedData['related_id']} '
          'date=${normalizedData['date']}',
        );
        return;
      }
      await _client.from('calendar_events').insert(payload);
    }

    await _runWriteOperation(
      operationType: operationType,
      queueKey:
          queueKey ??
          _insertQueueKey(
            relatedId: normalizedData['related_id']?.toString(),
            source: normalizedData['source']?.toString(),
            date: normalizedData['date']?.toString(),
            fallbackId: normalizedData['id']?.toString(),
          ),
      run: run,
    );
  }

  Future<void> safeUpdateEvent({
    required String eventId,
    required Map<String, dynamic> updates,
    String operationType = 'update_event',
  }) async {
    final normalizedUpdates = _normalizeEventPayload(updates);
    final useDocx = await _useDocxCalendar();

    Future<void> run() async {
      if (!useDocx) {
        await _client
            .from('calendar_events')
            .update(normalizedUpdates)
            .eq('id', eventId);
        return;
      }

      Map<String, dynamic> existing = <String, dynamic>{};
      try {
        final row = await _client
            .from('calendar_events')
            .select('notes')
            .eq('calendar_event_id', eventId)
            .maybeSingle();
        if (row != null) {
          final rowMap = Map<String, dynamic>.from(row as Map);
          final raw = (rowMap['notes'] ?? '').toString();
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            existing = decoded.cast<String, dynamic>();
          }
        }
      } catch (_) {
        existing = <String, dynamic>{};
      }

      final merged = <String, dynamic>{...existing};
      if (normalizedUpdates.containsKey('notes')) {
        merged['notes'] = normalizedUpdates['notes'];
      }
      if (normalizedUpdates.containsKey('severity')) {
        merged['severity'] = normalizedUpdates['severity'];
      }
      if (normalizedUpdates.containsKey('is_overridden')) {
        merged['is_overridden'] = normalizedUpdates['is_overridden'];
      }

      final payload = <String, dynamic>{
        if (normalizedUpdates.containsKey('date'))
          'scheduled_at': normalizedUpdates['date'],
        'notes': jsonEncode(merged),
      }..removeWhere((_, v) => v == null);

      await _client
          .from('calendar_events')
          .update(payload)
          .eq('calendar_event_id', eventId);
    }

    await _runWriteOperation(
      operationType: operationType,
      queueKey: 'update:$eventId',
      run: run,
    );
  }

  Future<void> safeDeleteEvent({
    String? eventId,
    String? relatedId,
    String? source,
    DateTime? greaterThanDate,
    String operationType = 'delete_event',
  }) async {
    final queueKey = eventId != null
        ? 'delete:$eventId'
        : 'delete:$relatedId:${source ?? 'any'}:${greaterThanDate?.toUtc().toIso8601String() ?? 'all'}';

    await _runWriteOperation(
      operationType: operationType,
      queueKey: queueKey,
      run: () async {
        final useDocx = await _useDocxCalendar();
        PostgrestFilterBuilder builder = _client
            .from('calendar_events')
            .delete();
        if (eventId != null) {
          builder = builder.eq(useDocx ? 'calendar_event_id' : 'id', eventId);
        }
        if (relatedId != null) {
          builder = builder.eq(
            useDocx ? 'source_medication_id' : 'related_id',
            relatedId,
          );
        }
        if (source != null) {
          builder = builder.eq('source', source);
        }
        if (greaterThanDate != null) {
          builder = builder.gt(
            useDocx ? 'scheduled_at' : 'date',
            greaterThanDate.toUtc().toIso8601String(),
          );
        }
        await builder;
      },
    );
  }

  Future<void> addEvent({
    required String careTeamId,
    required String title,
    required DateTime dateTime,
    required models.EventType type,
    String? notes,
    int? duration,
    String? severity,
    String source = 'manual',
  }) async {
    if (careTeamId.trim().isEmpty) {
      throw const CalendarOperationException(
        'Missing care team',
        operationType: 'insert_event',
      );
    }
    if (title.trim().isEmpty) {
      throw const CalendarOperationException(
        'Title is required',
        operationType: 'insert_event',
      );
    }

    await safeInsertEvent({
      'id': const Uuid().v4(),
      'care_team_id': careTeamId,
      'title': title.trim(),
      'event_type': type.name,
      'date': dateTime,
      'notes': notes,
      'duration': duration,
      'severity': severity,
      'source': source,
      'is_auto': false,
      'is_overridden': false,
    });
  }

  Future<void> generateMedicationEvents({
    required String careTeamId,
    required String medicationId,
    required String name,
    required DateTime start,
    DateTime? end,
    required String frequency,
  }) async {
    if (careTeamId.trim().isEmpty ||
        medicationId.trim().isEmpty ||
        name.trim().isEmpty ||
        frequency.trim().isEmpty) {
      throw const CalendarOperationException(
        'Missing medication schedule details',
        operationType: 'generate_medication_events',
      );
    }

    final horizon = end ?? start.add(const Duration(days: 90));
    final schedule = _buildMedicationSchedule(
      start: start,
      end: horizon,
      frequency: frequency,
    );

    if (schedule.isEmpty) return;

    try {
      final rows = <Map<String, dynamic>>[];
      final useDocx = await _useDocxCalendar();
      for (final date in schedule) {
        final normalizedDate = date.toUtc().toIso8601String();
        final duplicateExists = await _isMedicationDuplicate({
          'related_id': medicationId,
          'date': normalizedDate,
          'source': 'medication',
        }, useDocx: useDocx);
        if (duplicateExists) continue;

        final legacy = {
          'id': const Uuid().v4(),
          'care_team_id': careTeamId,
          'title': 'Give $name',
          'event_type': models.EventType.medication.name,
          'date': normalizedDate,
          'source': 'medication',
          'related_id': medicationId,
          'is_auto': true,
          'is_overridden': false,
        };

        rows.add(useDocx ? _legacyToDocxInsertPayload(legacy) : legacy);
      }

      if (rows.isEmpty) return;

      await _runWriteOperation(
        operationType: 'generate_medication_events',
        queueKey: 'generate:$medicationId',
        run: () => _client.from('calendar_events').insert(rows),
      );
    } catch (error) {
      _logFailure('generate_medication_events', error);
      if (_isNetworkFailure(error)) {
        _enqueuePendingOperation(
          'generate:$medicationId',
          () => generateMedicationEvents(
            careTeamId: careTeamId,
            medicationId: medicationId,
            name: name,
            start: start,
            end: end,
            frequency: frequency,
          ),
        );
      }
      throw const CalendarOperationException(
        'Failed to generate schedule. Please retry.',
        operationType: 'generate_medication_events',
        retryable: true,
      );
    }
  }

  Future<void> deleteFutureMedicationEvents(String medicationId) async {
    final now = DateTime.now();
    await safeDeleteEvent(
      relatedId: medicationId,
      source: 'medication',
      greaterThanDate: now,
      operationType: 'delete_future_medication_events',
    );
  }

  Future<void> updateMedicationSchedule({
    required String medicationId,
    required String careTeamId,
    required String name,
    required DateTime start,
    DateTime? end,
    required String frequency,
  }) async {
    final now = DateTime.now();
    await safeDeleteEvent(
      relatedId: medicationId,
      source: 'medication',
      greaterThanDate: now,
      operationType: 'update_medication_schedule_delete_future',
    );

    await generateMedicationEvents(
      careTeamId: careTeamId,
      medicationId: medicationId,
      name: name,
      start: start.isBefore(now) ? now : start,
      end: end,
      frequency: frequency,
    );
  }

  Future<void> updateMedicationScheduleFromDate({
    required String medicationId,
    required String careTeamId,
    required DateTime effectiveFrom,
    required String name,
    required DateTime start,
    DateTime? end,
    required String frequency,
  }) async {
    await safeDeleteEvent(
      relatedId: medicationId,
      source: 'medication',
      greaterThanDate: effectiveFrom,
      operationType: 'update_medication_schedule_from_date_delete_future',
    );

    await generateMedicationEvents(
      careTeamId: careTeamId,
      medicationId: medicationId,
      name: name,
      start: effectiveFrom,
      end: end,
      frequency: frequency,
    );
  }

  Future<void> markEventOverridden(String eventId) async {
    await safeUpdateEvent(
      eventId: eventId,
      updates: {'is_overridden': true},
      operationType: 'mark_event_overridden',
    );
  }

  Future<void> deleteSingleOccurrence(String eventId) async {
    await markEventOverridden(eventId);
  }

  Future<void> overrideSingleEvent({
    required models.CalendarEvent event,
    required DateTime newDate,
    String? notes,
  }) async {
    if ((event.isAuto ?? false) && event.dateTime.isBefore(DateTime.now())) {
      throw const CalendarOperationException(
        'Cannot modify past auto events',
        operationType: 'override_single_event',
      );
    }

    await markEventOverridden(event.id);
    await safeInsertEvent({
      'id': const Uuid().v4(),
      'care_team_id': event.careTeamId,
      'title': event.title,
      'event_type': event.type.name,
      'date': newDate,
      'notes': notes,
      'duration': event.duration,
      'severity': event.severity,
      'source': 'manual',
      'related_id': event.relatedId,
      'is_auto': false,
      'is_overridden': false,
    }, operationType: 'override_single_event_insert');
  }

  Future<void> updateManualEvent({
    required String eventId,
    required DateTime newDate,
    String? notes,
  }) async {
    await safeUpdateEvent(
      eventId: eventId,
      updates: {'date': newDate, 'notes': notes},
      operationType: 'update_manual_event',
    );
  }

  Future<Map<String, dynamic>?> getMedicationScheduleDetails(
    String medicationId,
  ) async {
    try {
      return await SupabaseService().getMedicationScheduleDetails(medicationId);
    } catch (error) {
      _logFailure('get_medication_schedule_details', error);
      throw _mapError(error, operationType: 'get_medication_schedule_details');
    }
  }

  Future<void> _runWriteOperation({
    required String operationType,
    required String queueKey,
    required Future<void> Function() run,
  }) async {
    try {
      await retryPendingOperations();
      await run();
    } catch (error) {
      _logFailure(operationType, error);
      if (_isNetworkFailure(error)) {
        _enqueuePendingOperation(queueKey, run);
      }
      throw _mapError(error, operationType: operationType);
    }
  }

  Map<String, dynamic> _normalizeEventPayload(Map<String, dynamic> payload) {
    final normalized = Map<String, dynamic>.from(payload);
    final rawDate = normalized['date'];
    if (rawDate is DateTime) {
      normalized['date'] = rawDate.toUtc().toIso8601String();
    }
    if (rawDate is String && rawDate.trim().isNotEmpty) {
      normalized['date'] = DateTime.parse(rawDate).toUtc().toIso8601String();
    }
    return normalized;
  }

  List<DateTime> _buildMedicationSchedule({
    required DateTime start,
    required DateTime end,
    required String frequency,
  }) {
    final schedule = <DateTime>[];
    final normalized = frequency.trim().toLowerCase();

    // New formats used by the Add Medication modal.
    // - every_hours:N
    // - every_days:N
    // - daily_times:minutes,minutes,... (minutes from midnight)
    if (normalized.startsWith('every_hours:')) {
      final parts = normalized.split(':');
      final hours = parts.length == 2 ? int.tryParse(parts[1]) : null;
      final stepHours = (hours != null && hours > 0) ? hours : 4;
      DateTime current = start;
      while (current.isBefore(end) && schedule.length < 500) {
        schedule.add(current);
        current = current.add(Duration(hours: stepHours));
      }
      return schedule;
    }

    if (normalized.startsWith('every_days:')) {
      final parts = normalized.split(':');
      final days = parts.length == 2 ? int.tryParse(parts[1]) : null;
      final stepDays = (days != null && days > 0) ? days : 2;
      DateTime current = start;
      while (current.isBefore(end) && schedule.length < 500) {
        schedule.add(current);
        current = current.add(Duration(days: stepDays));
      }
      return schedule;
    }

    if (normalized.startsWith('daily_times:')) {
      final payload = normalized.substring('daily_times:'.length);
      final minutes =
          payload
              .split(',')
              .map((s) => int.tryParse(s.trim()))
              .whereType<int>()
              .where((m) => m >= 0 && m < 24 * 60)
              .toSet()
              .toList()
            ..sort();

      final baseDay = DateTime(start.year, start.month, start.day);
      for (
        int dayOffset = 0;
        !baseDay.add(Duration(days: dayOffset)).isAfter(end) &&
            schedule.length < 500;
        dayOffset++
      ) {
        final day = baseDay.add(Duration(days: dayOffset));
        for (final m in minutes) {
          final candidate = day.add(Duration(minutes: m));
          if (candidate.isBefore(start)) continue;
          if (!candidate.isBefore(end)) continue;
          schedule.add(candidate);
          if (schedule.length >= 500) break;
        }
      }
      return schedule;
    }

    if (normalized == 'daily') {
      DateTime current = start;
      while (current.isBefore(end) && schedule.length < 500) {
        schedule.add(current);
        current = current.add(const Duration(days: 1));
      }
      return schedule;
    }

    if (normalized == 'twice_daily') {
      DateTime current = start;
      while (current.isBefore(end) && schedule.length < 500) {
        schedule.add(current);
        final second = current.add(const Duration(hours: 12));
        if (second.isBefore(end)) schedule.add(second);
        current = current.add(const Duration(days: 1));
      }
      return schedule;
    }

    if (normalized == 'weekly') {
      DateTime current = start;
      while (current.isBefore(end) && schedule.length < 500) {
        schedule.add(current);
        current = current.add(const Duration(days: 7));
      }
      return schedule;
    }

    return schedule;
  }

  Future<bool> _isMedicationDuplicate(
    Map<String, dynamic> payload, {
    required bool useDocx,
  }) async {
    final relatedId = payload['related_id']?.toString();
    final date = payload['date']?.toString();
    final source = payload['source']?.toString();
    if (source != 'medication' || relatedId == null || date == null) {
      return false;
    }

    final existing = await _client
        .from('calendar_events')
        .select(useDocx ? 'calendar_event_id' : 'id')
        .eq(useDocx ? 'source_medication_id' : 'related_id', relatedId)
        .eq('source', 'medication')
        .eq(useDocx ? 'scheduled_at' : 'date', date)
        .limit(1);

    return (existing as List).isNotEmpty;
  }

  bool _isNetworkFailure(Object error) {
    if (error is SocketException) return true;
    final message = error.toString().toLowerCase();
    return message.contains('socketexception') ||
        message.contains('failed host lookup') ||
        message.contains('network') ||
        message.contains('connection') ||
        message.contains('timed out');
  }

  void _enqueuePendingOperation(String key, Future<void> Function() run) {
    _pendingOperations.removeWhere((item) => item.key == key);
    _pendingOperations.add(
      _PendingCalendarOperation(
        key: key,
        timestamp: DateTime.now().toUtc(),
        run: run,
      ),
    );
  }

  String _insertQueueKey({
    String? relatedId,
    String? source,
    String? date,
    String? fallbackId,
  }) {
    if (relatedId != null && source != null && date != null) {
      return 'insert:$source:$relatedId:$date';
    }
    return 'insert:${fallbackId ?? const Uuid().v4()}';
  }

  CalendarOperationException _mapError(
    Object error, {
    required String operationType,
  }) {
    if (error is CalendarOperationException) {
      return error;
    }

    if (_isNetworkFailure(error)) {
      return CalendarOperationException(
        'Check your internet connection',
        operationType: operationType,
        retryable: true,
      );
    }

    if (error is PostgrestException) {
      final code = (error.code ?? '').toUpperCase();
      final message = error.message.toLowerCase();
      if (code == '42501' || message.contains('row-level security')) {
        return CalendarOperationException(
          'Blocked by Supabase RLS for calendar_events. Apply backend/supabase_cloud_calendar_events_rls_fix.sql in Supabase SQL Editor.',
          operationType: operationType,
          retryable: false,
        );
      }
      return CalendarOperationException(
        'Something went wrong. Please try again later',
        operationType: operationType,
      );
    }

    return CalendarOperationException(
      'Something went wrong. Please try again later',
      operationType: operationType,
    );
  }

  void _logFailure(String operationType, Object error) {
    debugPrint('[Calendar][$operationType] $error');
  }
}
