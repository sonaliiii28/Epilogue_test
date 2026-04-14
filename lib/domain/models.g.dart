// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CareTeam _$CareTeamFromJson(Map<String, dynamic> json) => CareTeam(
  id: json['id'] as String,
  patientFirstName: json['patient_first_name'] as String?,
  primaryCaregiverName: json['primary_caregiver_name'] as String?,
  primaryCaregiverEmail: json['primary_caregiver_email'] as String?,
  hospiceOrgId: json['hospice_org_id'] as String?,
  hospiceName: json['hospice_name'] as String?,
  patientAddress: json['patient_address'] as String?,
  nurseLineNumber: json['nurse_line_number'] as String?,
  joinCode: json['join_code'] as String?,
  createdAt: json['created_at'] == null
      ? null
      : DateTime.parse(json['created_at'] as String),
);

Map<String, dynamic> _$CareTeamToJson(CareTeam instance) => <String, dynamic>{
  'id': instance.id,
  'patient_first_name': instance.patientFirstName,
  'primary_caregiver_name': instance.primaryCaregiverName,
  'primary_caregiver_email': instance.primaryCaregiverEmail,
  'hospice_org_id': instance.hospiceOrgId,
  'hospice_name': instance.hospiceName,
  'patient_address': instance.patientAddress,
  'nurse_line_number': instance.nurseLineNumber,
  'join_code': instance.joinCode,
  'created_at': instance.createdAt?.toIso8601String(),
};

Member _$MemberFromJson(Map<String, dynamic> json) => Member(
  id: json['id'] as String,
  careTeamId: json['care_team_id'] as String?,
  name: json['name'] as String,
  email: json['email'] as String,
  role: json['role'] as String?,
  isAdmin: json['is_admin'] as bool? ?? false,
  magicLinkToken: json['magic_link_token'] as String?,
  accessPin: json['access_pin'] as String?,
  joinedAt: json['joined_at'] == null
      ? null
      : DateTime.parse(json['joined_at'] as String),
  lastActive: json['last_active'] == null
      ? null
      : DateTime.parse(json['last_active'] as String),
);

Map<String, dynamic> _$MemberToJson(Member instance) => <String, dynamic>{
  'id': instance.id,
  'care_team_id': instance.careTeamId,
  'name': instance.name,
  'email': instance.email,
  'role': instance.role,
  'is_admin': instance.isAdmin,
  'magic_link_token': instance.magicLinkToken,
  'access_pin': instance.accessPin,
  'joined_at': instance.joinedAt?.toIso8601String(),
  'last_active': instance.lastActive?.toIso8601String(),
};

CarePlan _$CarePlanFromJson(Map<String, dynamic> json) => CarePlan(
  careTeamId: json['care_team_id'] as String,
  medicationsSummary: json['medications_summary'] as String?,
  positioningTurning: json['positioning_turning'] as String?,
  transfers: json['transfers'] as String?,
  mobility: json['mobility'] as String?,
  personalCare: json['personal_care'] as String?,
  otherInstructions: json['other_instructions'] as String?,
  hospiceInstructions: json['hospice_instructions'] as String?,
  updatedAt: json['updated_at'] == null
      ? null
      : DateTime.parse(json['updated_at'] as String),
  updatedByMemberId: json['updated_by_member_id'] as String?,
);

Map<String, dynamic> _$CarePlanToJson(CarePlan instance) => <String, dynamic>{
  'care_team_id': instance.careTeamId,
  'medications_summary': instance.medicationsSummary,
  'positioning_turning': instance.positioningTurning,
  'transfers': instance.transfers,
  'mobility': instance.mobility,
  'personal_care': instance.personalCare,
  'other_instructions': instance.otherInstructions,
  'hospice_instructions': instance.hospiceInstructions,
  'updated_at': instance.updatedAt?.toIso8601String(),
  'updated_by_member_id': instance.updatedByMemberId,
};

Medication _$MedicationFromJson(Map<String, dynamic> json) => Medication(
  id: json['id'] as String,
  careTeamId: json['care_team_id'] as String?,
  name: json['name'] as String?,
  strength: json['strength'] as String?,
  typicalDose: json['typical_dose'] as String?,
  route: json['route'] as String?,
  pattern: json['pattern'] as String?,
  scheduleDetails: json['schedule_details'] as String?,
  notes: json['notes'] as String?,
  prnReasonTags: (json['prn_reason_tags'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  createdAt: json['created_at'] == null
      ? null
      : DateTime.parse(json['created_at'] as String),
  createdByMemberId: json['created_by_member_id'] as String?,
  deprescribedAt: json['deprescribed_at'] == null
      ? null
      : DateTime.parse(json['deprescribed_at'] as String),
);

Map<String, dynamic> _$MedicationToJson(Medication instance) =>
    <String, dynamic>{
      'id': instance.id,
      'care_team_id': instance.careTeamId,
      'name': instance.name,
      'strength': instance.strength,
      'typical_dose': instance.typicalDose,
      'route': instance.route,
      'pattern': instance.pattern,
      'schedule_details': instance.scheduleDetails,
      'notes': instance.notes,
      'prn_reason_tags': instance.prnReasonTags,
      'created_at': instance.createdAt?.toIso8601String(),
      'created_by_member_id': instance.createdByMemberId,
      'deprescribed_at': instance.deprescribedAt?.toIso8601String(),
    };

DoseLog _$DoseLogFromJson(Map<String, dynamic> json) => DoseLog(
  id: json['id'] as String,
  careTeamId: json['care_team_id'] as String?,
  medicationId: json['medication_id'] as String?,
  medicationName: json['medication_name'] as String?,
  doseTime: json['dose_time'] == null
      ? null
      : DateTime.parse(json['dose_time'] as String),
  amountGiven: json['amount_given'] as String?,
  whoGave: json['who_gave'] as String?,
  note: json['note'] as String?,
  loggedByMemberId: json['logged_by_member_id'] as String?,
  loggedByMemberName: json['logged_by_member_name'] as String?,
  editableUntil: json['editable_until'] == null
      ? null
      : DateTime.parse(json['editable_until'] as String),
  eventId: json['event_id'] as String?,
);

Map<String, dynamic> _$DoseLogToJson(DoseLog instance) => <String, dynamic>{
  'id': instance.id,
  'care_team_id': instance.careTeamId,
  'medication_id': instance.medicationId,
  'medication_name': instance.medicationName,
  'dose_time': instance.doseTime?.toIso8601String(),
  'amount_given': instance.amountGiven,
  'who_gave': instance.whoGave,
  'note': instance.note,
  'logged_by_member_id': instance.loggedByMemberId,
  'logged_by_member_name': instance.loggedByMemberName,
  'editable_until': instance.editableUntil?.toIso8601String(),
  'event_id': instance.eventId,
};

SymptomEvent _$SymptomEventFromJson(Map<String, dynamic> json) => SymptomEvent(
  id: json['id'] as String,
  careTeamId: json['care_team_id'] as String?,
  symptoms: (json['symptoms'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  severity: json['severity'] as String?,
  whatHappened: json['what_happened'] as String?,
  eventTime: json['event_time'] == null
      ? null
      : DateTime.parse(json['event_time'] as String),
  createdByMemberId: json['created_by_member_id'] as String?,
  createdByMemberName: json['created_by_member_name'] as String?,
  editableUntil: json['editable_until'] == null
      ? null
      : DateTime.parse(json['editable_until'] as String),
);

Map<String, dynamic> _$SymptomEventToJson(SymptomEvent instance) =>
    <String, dynamic>{
      'id': instance.id,
      'care_team_id': instance.careTeamId,
      'symptoms': instance.symptoms,
      'severity': instance.severity,
      'what_happened': instance.whatHappened,
      'event_time': instance.eventTime?.toIso8601String(),
      'created_by_member_id': instance.createdByMemberId,
      'created_by_member_name': instance.createdByMemberName,
      'editable_until': instance.editableUntil?.toIso8601String(),
    };

SkinWoundEvent _$SkinWoundEventFromJson(Map<String, dynamic> json) =>
    SkinWoundEvent(
      id: json['id'] as String,
      careTeamId: json['care_team_id'] as String,
      hasSkinCondition: json['has_skin_condition'] as bool? ?? false,
      skinCondition: json['skin_condition'] as String?,
      treatments:
          (json['treatments'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      imageUrls:
          (json['image_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      notes: json['notes'] as String?,
      eventTime: DateTime.parse(json['event_time'] as String),
      deletedAt: json['deleted_at'] == null
          ? null
          : DateTime.parse(json['deleted_at'] as String),
      createdByMemberId: json['created_by_member_id'] as String?,
      createdByMemberName: json['created_by_member_name'] as String?,
      editableUntil: json['editable_until'] == null
          ? null
          : DateTime.parse(json['editable_until'] as String),
    );

Map<String, dynamic> _$SkinWoundEventToJson(SkinWoundEvent instance) =>
    <String, dynamic>{
      'id': instance.id,
      'care_team_id': instance.careTeamId,
      'has_skin_condition': instance.hasSkinCondition,
      'skin_condition': instance.skinCondition,
      'treatments': instance.treatments,
      'image_urls': instance.imageUrls,
      'notes': instance.notes,
      'event_time': instance.eventTime.toIso8601String(),
      'deleted_at': instance.deletedAt?.toIso8601String(),
      'created_by_member_id': instance.createdByMemberId,
      'created_by_member_name': instance.createdByMemberName,
      'editable_until': instance.editableUntil?.toIso8601String(),
    };

NurseContact _$NurseContactFromJson(Map<String, dynamic> json) => NurseContact(
  id: json['id'] as String,
  careTeamId: json['care_team_id'] as String?,
  symptomEventId: json['symptom_event_id'] as String?,
  contactMethod: json['contact_method'] as String?,
  status: json['status'] as String?,
  messageBody: json['message_body'] as String?,
  attemptedAt: json['attempted_at'] == null
      ? null
      : DateTime.parse(json['attempted_at'] as String),
  attemptedByMemberId: json['attempted_by_member_id'] as String?,
);

Map<String, dynamic> _$NurseContactToJson(NurseContact instance) =>
    <String, dynamic>{
      'id': instance.id,
      'care_team_id': instance.careTeamId,
      'symptom_event_id': instance.symptomEventId,
      'contact_method': instance.contactMethod,
      'status': instance.status,
      'message_body': instance.messageBody,
      'attempted_at': instance.attemptedAt?.toIso8601String(),
      'attempted_by_member_id': instance.attemptedByMemberId,
    };

Observation _$ObservationFromJson(Map<String, dynamic> json) => Observation(
  id: json['id'] as String,
  careTeamId: json['care_team_id'] as String?,
  content: json['content'] as String?,
  category: json['category'] as String?,
  createdAt: json['created_at'] == null
      ? null
      : DateTime.parse(json['created_at'] as String),
  createdByMemberId: json['created_by_member_id'] as String?,
  createdByMemberName: json['created_by_member_name'] as String?,
);

Map<String, dynamic> _$ObservationToJson(Observation instance) =>
    <String, dynamic>{
      'id': instance.id,
      'care_team_id': instance.careTeamId,
      'content': instance.content,
      'category': instance.category,
      'created_at': instance.createdAt?.toIso8601String(),
      'created_by_member_id': instance.createdByMemberId,
      'created_by_member_name': instance.createdByMemberName,
    };

Moment _$MomentFromJson(Map<String, dynamic> json) => Moment(
  id: json['id'] as String,
  careTeamId: json['care_team_id'] as String?,
  category: json['category'] as String?,
  content: json['content'] as String?,
  visibility: json['visibility'] as String?,
  photoUrl: json['photo_url'] as String?,
  createdAt: json['created_at'] == null
      ? null
      : DateTime.parse(json['created_at'] as String),
  createdByMemberId: json['created_by_member_id'] as String?,
  createdByMemberName: json['created_by_member_name'] as String?,
);

Map<String, dynamic> _$MomentToJson(Moment instance) => <String, dynamic>{
  'id': instance.id,
  'care_team_id': instance.careTeamId,
  'category': instance.category,
  'content': instance.content,
  'visibility': instance.visibility,
  'photo_url': instance.photoUrl,
  'created_at': instance.createdAt?.toIso8601String(),
  'created_by_member_id': instance.createdByMemberId,
  'created_by_member_name': instance.createdByMemberName,
};

CalendarEvent _$CalendarEventFromJson(Map<String, dynamic> json) =>
    CalendarEvent(
      id: json['id'] as String,
      careTeamId: json['care_team_id'] as String?,
      title: json['title'] as String? ?? '',
      dateTime: DateTime.parse(json['date'] as String).toLocal(),
      type: _eventTypeFromJson(json['event_type'] as String?),
      source: json['source'] as String? ?? 'manual',
      createdBy: json['created_by_member_id'] as String?,
      notes: json['notes'] as String?,
      duration: (json['duration'] as num?)?.toInt(),
      severity: json['severity'] as String?,
      relatedId: json['related_id'] as String?,
      isAuto: json['is_auto'] as bool?,
      isOverridden: json['is_overridden'] as bool?,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
    );

Map<String, dynamic> _$CalendarEventToJson(CalendarEvent instance) =>
    <String, dynamic>{
      'id': instance.id,
      'care_team_id': instance.careTeamId,
      'title': instance.title,
      'date': instance.dateTime.toUtc().toIso8601String(),
      'event_type': _eventTypeToJson(instance.type),
      'source': instance.source,
      'created_by_member_id': instance.createdBy,
      'notes': instance.notes,
      'duration': instance.duration,
      'severity': instance.severity,
      'related_id': instance.relatedId,
      'is_auto': instance.isAuto,
      'is_overridden': instance.isOverridden,
      'created_at': instance.createdAt?.toIso8601String(),
    };

CheckIn _$CheckInFromJson(Map<String, dynamic> json) => CheckIn(
  id: json['id'] as String,
  careTeamId: json['care_team_id'] as String?,
  memberId: json['member_id'] as String?,
  questionText: json['question_text'] as String?,
  response: json['response'] as String?,
  createdAt: json['created_at'] == null
      ? null
      : DateTime.parse(json['created_at'] as String),
);

Map<String, dynamic> _$CheckInToJson(CheckIn instance) => <String, dynamic>{
  'id': instance.id,
  'care_team_id': instance.careTeamId,
  'member_id': instance.memberId,
  'question_text': instance.questionText,
  'response': instance.response,
  'created_at': instance.createdAt?.toIso8601String(),
};

ShiftNote _$ShiftNoteFromJson(Map<String, dynamic> json) => ShiftNote(
  id: json['id'] as String,
  careTeamId: json['care_team_id'] as String?,
  memberId: json['member_id'] as String?,
  memberName: json['member_name'] as String?,
  shiftDate: json['shift_date'] as String?,
  arrivedAt: json['arrived_at'] == null
      ? null
      : DateTime.parse(json['arrived_at'] as String),
  leftAt: json['left_at'] == null
      ? null
      : DateTime.parse(json['left_at'] as String),
  tasksCompleted: (json['tasks_completed'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  whatINoticed: json['what_i_noticed'] as String?,
  flagForPrimaryOnly: json['flag_for_primary_only'] as bool?,
  createdAt: json['created_at'] == null
      ? null
      : DateTime.parse(json['created_at'] as String),
);

Map<String, dynamic> _$ShiftNoteToJson(ShiftNote instance) => <String, dynamic>{
  'id': instance.id,
  'care_team_id': instance.careTeamId,
  'member_id': instance.memberId,
  'member_name': instance.memberName,
  'shift_date': instance.shiftDate,
  'arrived_at': instance.arrivedAt?.toIso8601String(),
  'left_at': instance.leftAt?.toIso8601String(),
  'tasks_completed': instance.tasksCompleted,
  'what_i_noticed': instance.whatINoticed,
  'flag_for_primary_only': instance.flagForPrimaryOnly,
  'created_at': instance.createdAt?.toIso8601String(),
};
