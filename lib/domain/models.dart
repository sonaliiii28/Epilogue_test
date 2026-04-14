import 'package:json_annotation/json_annotation.dart';

part 'models.g.dart';

enum EventType { medication, visit, care, symptom }

@JsonSerializable(fieldRename: FieldRename.snake)
class CareTeam {
  final String id;
  final String? patientFirstName;
  final String? primaryCaregiverName;
  final String? primaryCaregiverEmail;
  final String? hospiceOrgId;
  final String? hospiceName;
  final String? patientAddress;
  final String? nurseLineNumber;
  final String? joinCode;
  final DateTime? createdAt;

  CareTeam({
    required this.id,
    this.patientFirstName,
    this.primaryCaregiverName,
    this.primaryCaregiverEmail,
    this.hospiceOrgId,
    this.hospiceName,
    this.patientAddress,
    this.nurseLineNumber,
    this.joinCode,
    this.createdAt,
  });

  factory CareTeam.fromJson(Map<String, dynamic> json) =>
      _$CareTeamFromJson(json);
  Map<String, dynamic> toJson() => _$CareTeamToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class Member {
  final String id;
  final String? careTeamId;
  final String name;
  final String email;
  final String? role;
  final bool? isAdmin;
  final String? magicLinkToken;
  final String? accessPin;
  final DateTime? joinedAt;
  final DateTime? lastActive;

  Member({
    required this.id,
    this.careTeamId,
    required this.name,
    required this.email,
    this.role,
    this.isAdmin = false,
    this.magicLinkToken,
    this.accessPin,
    this.joinedAt,
    this.lastActive,
  });

  factory Member.fromJson(Map<String, dynamic> json) => _$MemberFromJson(json);
  Map<String, dynamic> toJson() => _$MemberToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class CarePlan {
  final String careTeamId;
  final String? medicationsSummary;
  final String? positioningTurning;
  final String? transfers;
  final String? mobility;
  final String? personalCare;
  final String? otherInstructions;
  final String? hospiceInstructions;
  final DateTime? updatedAt;
  final String? updatedByMemberId;

  CarePlan({
    required this.careTeamId,
    this.medicationsSummary,
    this.positioningTurning,
    this.transfers,
    this.mobility,
    this.personalCare,
    this.otherInstructions,
    this.hospiceInstructions,
    this.updatedAt,
    this.updatedByMemberId,
  });

  factory CarePlan.fromJson(Map<String, dynamic> json) =>
      _$CarePlanFromJson(json);
  Map<String, dynamic> toJson() => _$CarePlanToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class Medication {
  final String id;
  final String? careTeamId;
  final String? name;
  final String? strength;
  @JsonKey(name: 'typical_dose')
  final String? typicalDose;
  final String? route;
  final String? pattern;
  final String? scheduleDetails;
  final String? notes;
  final List<String>? prnReasonTags;
  final DateTime? createdAt;
  final String? createdByMemberId;
  final DateTime? deprescribedAt;

  Medication({
    required this.id,
    this.careTeamId,
    this.name,
    this.strength,
    this.typicalDose,
    this.route,
    this.pattern,
    this.scheduleDetails,
    this.notes,
    this.prnReasonTags,
    this.createdAt,
    this.createdByMemberId,
    this.deprescribedAt,
  });

  factory Medication.fromJson(Map<String, dynamic> json) =>
      _$MedicationFromJson(json);
  Map<String, dynamic> toJson() => _$MedicationToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class DoseLog {
  final String id;
  final String? careTeamId;
  final String? medicationId;
  final String? medicationName;
  final DateTime? doseTime;
  final String? amountGiven;
  final String? whoGave;
  final String? note;
  final String? loggedByMemberId;
  final String? loggedByMemberName;
  final DateTime? editableUntil;
  final String? eventId;

  DoseLog({
    required this.id,
    this.careTeamId,
    this.medicationId,
    this.medicationName,
    this.doseTime,
    this.amountGiven,
    this.whoGave,
    this.note,
    this.loggedByMemberId,
    this.loggedByMemberName,
    this.editableUntil,
    this.eventId,
  });

  factory DoseLog.fromJson(Map<String, dynamic> json) =>
      _$DoseLogFromJson(json);
  Map<String, dynamic> toJson() => _$DoseLogToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class SymptomEvent {
  final String id;
  final String? careTeamId;
  final List<String>? symptoms;
  final String? severity;
  final String? whatHappened;
  final DateTime? eventTime;
  final DateTime? deletedAt;
  final String? createdByMemberId;
  final String? createdByMemberName;
  final DateTime? editableUntil;

  SymptomEvent({
    required this.id,
    this.careTeamId,
    this.symptoms,
    this.severity,
    this.whatHappened,
    this.eventTime,
    this.deletedAt,
    this.createdByMemberId,
    this.createdByMemberName,
    this.editableUntil,
  });

  factory SymptomEvent.fromJson(Map<String, dynamic> json) =>
      _$SymptomEventFromJson(json);
  Map<String, dynamic> toJson() => _$SymptomEventToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class SkinWoundEvent {
  final String id;
  final String careTeamId;
  final bool hasSkinCondition;
  final String? skinCondition;
  final List<String> treatments;
  final List<String> imageUrls;
  final String? notes;
  final DateTime eventTime;
  final DateTime? deletedAt;
  final String? createdByMemberId;
  final String? createdByMemberName;
  final DateTime? editableUntil;

  SkinWoundEvent({
    required this.id,
    required this.careTeamId,
    required this.hasSkinCondition,
    this.skinCondition,
    required this.treatments,
    required this.imageUrls,
    this.notes,
    required this.eventTime,
    this.deletedAt,
    this.createdByMemberId,
    this.createdByMemberName,
    this.editableUntil,
  });

  factory SkinWoundEvent.fromJson(Map<String, dynamic> json) =>
      _$SkinWoundEventFromJson(json);
  Map<String, dynamic> toJson() => _$SkinWoundEventToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class NurseContact {
  final String id;
  final String? careTeamId;
  final String? symptomEventId;
  final String? contactMethod;
  final String? status;
  final String? messageBody;
  final DateTime? attemptedAt;
  final String? attemptedByMemberId;

  NurseContact({
    required this.id,
    this.careTeamId,
    this.symptomEventId,
    this.contactMethod,
    this.status,
    this.messageBody,
    this.attemptedAt,
    this.attemptedByMemberId,
  });

  factory NurseContact.fromJson(Map<String, dynamic> json) =>
      _$NurseContactFromJson(json);
  Map<String, dynamic> toJson() => _$NurseContactToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class Observation {
  final String id;
  final String? careTeamId;
  final String? content;
  final String? category;
  final DateTime? createdAt;
  final DateTime? deletedAt;
  final String? createdByMemberId;
  final String? createdByMemberName;

  Observation({
    required this.id,
    this.careTeamId,
    this.content,
    this.category,
    this.createdAt,
    this.deletedAt,
    this.createdByMemberId,
    this.createdByMemberName,
  });

  factory Observation.fromJson(Map<String, dynamic> json) =>
      _$ObservationFromJson(json);
  Map<String, dynamic> toJson() => _$ObservationToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class Moment {
  final String id;
  final String? careTeamId;
  final String? category;
  final String? content;
  final String? visibility;
  final String? photoUrl;
  final DateTime? createdAt;
  final String? createdByMemberId;
  final String? createdByMemberName;

  Moment({
    required this.id,
    this.careTeamId,
    this.category,
    this.content,
    this.visibility,
    this.photoUrl,
    this.createdAt,
    this.createdByMemberId,
    this.createdByMemberName,
  });

  factory Moment.fromJson(Map<String, dynamic> json) => _$MomentFromJson(json);
  Map<String, dynamic> toJson() => _$MomentToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class CalendarEvent {
  final String id;
  final String? careTeamId;
  final String title;
  @JsonKey(name: 'date')
  final DateTime dateTime;
  @JsonKey(
    name: 'event_type',
    fromJson: _eventTypeFromJson,
    toJson: _eventTypeToJson,
  )
  final EventType type;
  final String source;
  @JsonKey(name: 'created_by_member_id')
  final String? createdBy;
  final String? notes;
  final int? duration;
  final String? severity;
  final String? relatedId;
  final bool? isAuto;
  final bool? isOverridden;
  final DateTime? createdAt;

  CalendarEvent({
    required this.id,
    this.careTeamId,
    required this.title,
    required this.dateTime,
    required this.type,
    required this.source,
    this.createdBy,
    this.notes,
    this.duration,
    this.severity,
    this.relatedId,
    this.isAuto,
    this.isOverridden,
    this.createdAt,
  });

  factory CalendarEvent.fromJson(Map<String, dynamic> json) =>
      _$CalendarEventFromJson(json);
  Map<String, dynamic> toJson() => _$CalendarEventToJson(this);
}

EventType _eventTypeFromJson(String? rawType) {
  return EventType.values.firstWhere(
    (value) => value.name == rawType,
    orElse: () => EventType.symptom,
  );
}

String _eventTypeToJson(EventType type) => type.name;

@JsonSerializable(fieldRename: FieldRename.snake)
class CheckIn {
  final String id;
  final String? careTeamId;
  final String? memberId;
  final String? questionText;
  final String? response;
  final DateTime? createdAt;

  CheckIn({
    required this.id,
    this.careTeamId,
    this.memberId,
    this.questionText,
    this.response,
    this.createdAt,
  });

  factory CheckIn.fromJson(Map<String, dynamic> json) =>
      _$CheckInFromJson(json);
  Map<String, dynamic> toJson() => _$CheckInToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class ShiftNote {
  final String id;
  final String? careTeamId;
  final String? memberId;
  final String? memberName;
  final String? shiftDate;
  final DateTime? arrivedAt;
  final DateTime? leftAt;
  final List<String>? tasksCompleted;
  final String? whatINoticed;
  final bool? flagForPrimaryOnly;
  final DateTime? createdAt;

  ShiftNote({
    required this.id,
    this.careTeamId,
    this.memberId,
    this.memberName,
    this.shiftDate,
    this.arrivedAt,
    this.leftAt,
    this.tasksCompleted,
    this.whatINoticed,
    this.flagForPrimaryOnly,
    this.createdAt,
  });

  factory ShiftNote.fromJson(Map<String, dynamic> json) =>
      _$ShiftNoteFromJson(json);
  Map<String, dynamic> toJson() => _$ShiftNoteToJson(this);
}
