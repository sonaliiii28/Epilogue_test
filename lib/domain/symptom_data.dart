/// Symptom definitions from the Hospice Symptom Tracking Guide.
///
/// Each symptom has an input type (dropdown or event-based) and, for dropdowns,
/// a set of preset options specific to that symptom.

enum SymptomInputType { dropdown, event }

enum DropdownType { severity, frequency, level, days, location, frequencyPerDay }

class SymptomDefinition {
  final String id;
  final String name;
  final SymptomInputType inputType;
  final DropdownType? dropdownType;
  final List<String> options;
  final String? description;

  /// If true, selecting this symptom always triggers a nurse-alert banner.
  final bool isAlertTrigger;

  const SymptomDefinition({
    required this.id,
    required this.name,
    required this.inputType,
    this.dropdownType,
    this.options = const [],
    this.description,
    this.isAlertTrigger = false,
  });
}

/// Complete list of 35 hospice symptoms defined in the tracking guide.
const kHospiceSymptoms = <SymptomDefinition>[
  // ── Dropdown: severity ─────────────────────────────────────────────
  SymptomDefinition(
    id: 'agitation',
    name: 'Agitation',
    inputType: SymptomInputType.dropdown,
    dropdownType: DropdownType.severity,
    options: ['Mild', 'Moderate', 'Severe'],
  ),
  SymptomDefinition(
    id: 'anxiety',
    name: 'Anxiety',
    inputType: SymptomInputType.dropdown,
    dropdownType: DropdownType.severity,
    options: ['Mild', 'Moderate', 'Severe'],
  ),
  SymptomDefinition(
    id: 'breathlessness',
    name: 'Breathlessness',
    inputType: SymptomInputType.dropdown,
    dropdownType: DropdownType.severity,
    options: ['Mild', 'Moderate', 'Severe'],
    isAlertTrigger: true,
  ),
  SymptomDefinition(
    id: 'congestion',
    name: 'Congestion',
    inputType: SymptomInputType.dropdown,
    dropdownType: DropdownType.severity,
    options: ['Mild', 'Moderate', 'Severe'],
  ),
  SymptomDefinition(
    id: 'edema',
    name: 'Edema',
    inputType: SymptomInputType.dropdown,
    dropdownType: DropdownType.severity,
    options: ['Mild', 'Moderate', 'Severe'],
  ),
  SymptomDefinition(
    id: 'extreme_fatigue',
    name: 'Extreme fatigue',
    inputType: SymptomInputType.dropdown,
    dropdownType: DropdownType.severity,
    options: ['Mild', 'Moderate', 'Severe'],
  ),
  SymptomDefinition(
    id: 'generalized_weakness',
    name: 'Generalized weakness',
    inputType: SymptomInputType.dropdown,
    dropdownType: DropdownType.severity,
    options: ['Mild', 'Moderate', 'Severe'],
  ),
  SymptomDefinition(
    id: 'nausea',
    name: 'Nausea',
    inputType: SymptomInputType.dropdown,
    dropdownType: DropdownType.severity,
    options: ['Mild', 'Moderate', 'Severe'],
  ),
  SymptomDefinition(
    id: 'pain',
    name: 'Pain',
    inputType: SymptomInputType.dropdown,
    dropdownType: DropdownType.severity,
    options: ['Mild', 'Moderate', 'Severe'],
  ),
  SymptomDefinition(
    id: 'restlessness',
    name: 'Restlessness',
    inputType: SymptomInputType.dropdown,
    dropdownType: DropdownType.severity,
    options: ['Mild', 'Moderate', 'Severe'],
  ),
  SymptomDefinition(
    id: 'respiratory_secretions',
    name: 'Respiratory secretions',
    inputType: SymptomInputType.dropdown,
    dropdownType: DropdownType.severity,
    options: ['Mild', 'Moderate', 'Severe'],
  ),
  SymptomDefinition(
    id: 'tremors',
    name: 'Tremors',
    inputType: SymptomInputType.dropdown,
    dropdownType: DropdownType.severity,
    options: ['Mild', 'Moderate', 'Severe'],
  ),

  // ── Dropdown: frequency ────────────────────────────────────────────
  SymptomDefinition(
    id: 'apnea',
    name: 'Apnea',
    inputType: SymptomInputType.dropdown,
    dropdownType: DropdownType.frequency,
    options: ['Occasional', 'Frequent'],
    isAlertTrigger: true,
  ),
  SymptomDefinition(
    id: 'delirium',
    name: 'Delirium',
    inputType: SymptomInputType.dropdown,
    dropdownType: DropdownType.frequency,
    options: ['Sometimes', 'Most of the time'],
    isAlertTrigger: true,
  ),
  SymptomDefinition(
    id: 'gasping_respirations',
    name: 'Gasping respirations',
    inputType: SymptomInputType.dropdown,
    dropdownType: DropdownType.frequency,
    options: ['Occasional', 'Frequent'],
    isAlertTrigger: true,
  ),
  SymptomDefinition(
    id: 'hallucinations',
    name: 'Hallucinations',
    inputType: SymptomInputType.dropdown,
    dropdownType: DropdownType.frequency,
    options: ['Occasionally', 'Daily', 'Most of the day'],
    isAlertTrigger: true,
  ),

  // ── Dropdown: level ────────────────────────────────────────────────
  SymptomDefinition(
    id: 'bedbound',
    name: 'Bedbound',
    inputType: SymptomInputType.dropdown,
    dropdownType: DropdownType.level,
    options: ['Mostly bed', 'Completely bedbound'],
  ),
  SymptomDefinition(
    id: 'bedsores',
    name: 'Bedsores',
    inputType: SymptomInputType.dropdown,
    dropdownType: DropdownType.level,
    options: ['Red area', 'Open sore'],
  ),
  SymptomDefinition(
    id: 'decreased_consciousness',
    name: 'Decreased level of consciousness',
    inputType: SymptomInputType.dropdown,
    dropdownType: DropdownType.level,
    options: ['Sleepy', 'Difficult to wake', 'Unresponsive'],
    isAlertTrigger: true,
  ),
  SymptomDefinition(
    id: 'decreased_urine_output',
    name: 'Decreased urine output',
    inputType: SymptomInputType.dropdown,
    dropdownType: DropdownType.level,
    options: ['Less than usual', 'Very little', 'Almost none'],
  ),
  SymptomDefinition(
    id: 'difficulty_swallowing',
    name: 'Difficulty swallowing',
    inputType: SymptomInputType.dropdown,
    dropdownType: DropdownType.level,
    options: ['Sometimes', 'Most foods', 'Even liquids'],
  ),
  SymptomDefinition(
    id: 'fever',
    name: 'Fever',
    inputType: SymptomInputType.dropdown,
    dropdownType: DropdownType.level,
    options: ['Low-grade', 'Moderate', 'High'],
    description: 'Highest in last 24 hours',
  ),
  SymptomDefinition(
    id: 'jaundice',
    name: 'Jaundice',
    inputType: SymptomInputType.dropdown,
    dropdownType: DropdownType.level,
    options: ['Slight', 'Obvious'],
  ),
  SymptomDefinition(
    id: 'low_blood_pressure',
    name: 'Low blood pressure',
    inputType: SymptomInputType.dropdown,
    dropdownType: DropdownType.level,
    options: ['Sometimes dizzy/woozy', 'Often dizzy/woozy', 'Fainted'],
  ),
  SymptomDefinition(
    id: 'transfers',
    name: 'Transfers',
    inputType: SymptomInputType.dropdown,
    dropdownType: DropdownType.level,
    options: ['Needs a little help', 'Needs a lot of help', 'Cannot transfer at all'],
    description: 'Moving from bed to chair/bathroom, etc.',
  ),

  // ── Dropdown: location ─────────────────────────────────────────────
  SymptomDefinition(
    id: 'mottled_skin',
    name: 'Mottled skin',
    inputType: SymptomInputType.dropdown,
    dropdownType: DropdownType.location,
    options: ['Hands/feet', 'Legs/arms', 'Most of body'],
  ),

  // ── Dropdown: days ─────────────────────────────────────────────────
  SymptomDefinition(
    id: 'constipation',
    name: 'Constipation',
    inputType: SymptomInputType.dropdown,
    dropdownType: DropdownType.days,
    options: ['2–3 days', '4–5 days', '6–7 days', '8–9 days', '10+ days'],
  ),

  // ── Dropdown: frequency per day ────────────────────────────────────
  SymptomDefinition(
    id: 'diarrhea',
    name: 'Diarrhea',
    inputType: SymptomInputType.dropdown,
    dropdownType: DropdownType.frequencyPerDay,
    options: ['1 time', '2–3 times', '4–5 times', '6+ times'],
    description: 'Times in last 24 hours',
  ),

  // ── Event-based ────────────────────────────────────────────────────
  SymptomDefinition(
    id: 'bladder_incontinence',
    name: 'Bladder incontinence',
    inputType: SymptomInputType.event,
  ),
  SymptomDefinition(
    id: 'bowel_incontinence',
    name: 'Bowel incontinence',
    inputType: SymptomInputType.event,
  ),
  SymptomDefinition(
    id: 'blood_in_urine_or_stool',
    name: 'Blood in urine or stool',
    inputType: SymptomInputType.event,
    options: ['Urine', 'Stool', 'Both'],
    description: 'Location',
    isAlertTrigger: true,
  ),
  SymptomDefinition(
    id: 'bowel_movement',
    name: 'Bowel movement',
    inputType: SymptomInputType.event,
    options: ['Normal', 'Hard/constipated', 'Loose/diarrhea'],
    description: 'Type',
  ),
  SymptomDefinition(
    id: 'cheyne_stokes',
    name: 'Cheyne-Stokes respirations',
    inputType: SymptomInputType.event,
    isAlertTrigger: true,
  ),
  SymptomDefinition(
    id: 'falls',
    name: 'Falls',
    inputType: SymptomInputType.event,
    isAlertTrigger: true,
  ),
  SymptomDefinition(
    id: 'seizures',
    name: 'Seizures',
    inputType: SymptomInputType.event,
    isAlertTrigger: true,
  ),
];

/// Quick look-up: symptom ID → definition.
final kSymptomById = {
  for (final s in kHospiceSymptoms) s.id: s,
};

/// Set of symptom names that automatically trigger a nurse-alert banner.
final kAlertSymptomNames = {
  for (final s in kHospiceSymptoms)
    if (s.isAlertTrigger) s.name,
};
