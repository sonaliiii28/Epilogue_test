/// Auto-generated from hospice_medications_with_brands_filled.xlsx
/// 84 medications commonly used in hospice care.
class MedicationInfo {
  final String name;
  final String brand;
  final String primaryUse;
  final String route;
  final String doseUnit;

  const MedicationInfo({
    required this.name,
    required this.brand,
    required this.primaryUse,
    required this.route,
    required this.doseUnit,
  });

  /// Display string: 'GenericName (BrandName)'
  String get displayName => brand.isNotEmpty ? '$name ($brand)' : name;

  /// All brand names split on commas / slashes for search matching.
  List<String> get brandNames => brand
      .split(RegExp(r'[,/]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  /// Parsed list of route-of-administration options taken **directly** from
  /// the spreadsheet's route/form column for this specific medication.
  /// Splits on commas and semicolons so each distinct form becomes its own
  /// dropdown item (e.g. "Oral tablet/capsule", "Oral liquid", "Rectal suppository").
  List<String> get routeOptions {
    if (route.trim().isEmpty) return ['Other'];
    final parts = route
        .split(RegExp(r'[;,]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map(
          (s) => s[0].toUpperCase() + s.substring(1),
        ) // capitalise first letter
        .toList();
    // De-duplicate while preserving order
    final seen = <String>{};
    final unique = <String>[];
    for (final p in parts) {
      if (seen.add(p)) unique.add(p);
    }
    if (unique.isEmpty) return ['Other'];
    unique.add('Other');
    return unique;
  }

  /// Parsed list of unit options derived from the spreadsheet's doseUnit field.
  /// Returns simplified, dropdown-friendly labels.
  List<String> get unitOptions {
    final lower = doseUnit.toLowerCase();
    final opts = <String>{};
    if (lower.contains('mg') && !lower.contains('mcg')) opts.add('mg');
    if (lower.contains('mcg')) opts.add('mcg');
    if (lower.contains('ml')) opts.add('mL');
    if (lower.contains('%')) opts.add('%');
    if (lower.contains('units') || lower.contains('iu')) opts.add('units');
    if (lower.contains('g ') ||
        lower.contains('g/') ||
        RegExp(r'\bg\b').hasMatch(lower))
      opts.add('g');
    if (lower.contains('tablet')) opts.add('tablet(s)');
    if (lower.contains('capsule')) opts.add('capsule(s)');
    if (lower.contains('patch')) opts.add('patch');
    if (lower.contains('actuation')) opts.add('actuation(s)');
    if (lower.contains('drop')) opts.add('drop(s)');
    if (lower.contains('suppository')) opts.add('suppository');
    if (lower.contains('lozenge')) opts.add('lozenge(s)');
    if (opts.isEmpty) opts.add('mg'); // sensible default
    opts.add('Other');
    return opts.toList();
  }
}

/// Search hospice medications by generic name OR brand name.
/// Both 'lorazepam' and 'ativan' will match Lorazepam (Ativan).
List<MedicationInfo> searchMedications(String query) {
  if (query.trim().isEmpty) return [];
  final q = query.trim().toLowerCase();
  return kHospiceMedications.where((m) {
    if (m.name.toLowerCase().contains(q)) return true;
    // Check each brand name token
    for (final b in m.brandNames) {
      // Strip parenthetical content for matching
      final clean = b.replaceAll(RegExp(r'\(.*?\)'), '').trim().toLowerCase();
      if (clean.contains(q)) return true;
    }
    // Also check raw brand string
    return m.brand.toLowerCase().contains(q);
  }).toList();
}

const List<MedicationInfo> kHospiceMedications = [
  MedicationInfo(
    name: 'Acetaminophen',
    brand: 'Tylenol',
    primaryUse: 'Pain, fever',
    route: 'Oral tablet/capsule, oral liquid, rectal suppository',
    doseUnit: 'mg (tablets), mg/mL (liquid), mg (suppository)',
  ),
  MedicationInfo(
    name: 'Albuterol',
    brand: 'Proventil, Ventolin',
    primaryUse: 'Bronchodilator for dyspnea/wheezing',
    route: 'Inhaler (MDI), nebulizer solution',
    doseUnit: 'mcg/actuation (MDI), mg/mL or % (neb solution)',
  ),
  MedicationInfo(
    name: 'Alfentanil',
    brand: 'Alfenta',
    primaryUse: 'Severe pain/dyspnea (often via infusion)',
    route: 'IV/SC injection, continuous infusion',
    doseUnit: 'mcg, mcg/mL',
  ),
  MedicationInfo(
    name: 'Amitriptyline',
    brand: 'Elavil',
    primaryUse: 'Neuropathic pain, depression',
    route: 'Oral tablet',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Amlodipine',
    brand: 'Norvasc',
    primaryUse: 'Hypertension',
    route: 'Oral tablet',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Aspirin',
    brand: 'Bayer, Ecotrin, Bufferin',
    primaryUse: 'Antiplatelet, pain (sometimes continued)',
    route: 'Oral tablet',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Atropine',
    brand: '',
    primaryUse: 'Terminal secretions',
    route: 'Oral/SL drops',
    doseUnit: 'mg/mL or % (drops)',
  ),
  MedicationInfo(
    name: 'Baclofen',
    brand: 'Lioresal',
    primaryUse: 'Muscle spasm',
    route: 'Oral tablet',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Bethanechol',
    brand: 'Urecholine',
    primaryUse: 'Urinary retention',
    route: 'Oral tablet',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Bisacodyl',
    brand: 'Dulcolax',
    primaryUse: 'Stimulant laxative',
    route: 'Oral tablet, rectal suppository',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Carbidopa-levodopa / other Parkinson’s meds',
    brand: 'Sinemet (carbidopa-levodopa)',
    primaryUse: 'Parkinson’s symptoms',
    route: 'Oral tablet/capsule',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Carbamazepine',
    brand: 'Tegretol, Carbatrol',
    primaryUse: 'Neuropathic pain, seizures',
    route: 'Oral tablet/capsule',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Carvedilol',
    brand: 'Coreg',
    primaryUse: 'Heart failure, hypertension',
    route: 'Oral tablet',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Citalopram',
    brand: 'Celexa',
    primaryUse: 'Depression',
    route: 'Oral tablet',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Clonazepam',
    brand: 'Klonopin',
    primaryUse: 'Anxiety, seizures',
    route: 'Oral tablet, ODT',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Clopidogrel',
    brand: 'Plavix',
    primaryUse: 'Antiplatelet',
    route: 'Oral tablet',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Codeine',
    brand: '(often as combination products, e.g., Tylenol with Codeine)',
    primaryUse: 'Mild–moderate pain, cough',
    route: 'Oral tablet, oral liquid',
    doseUnit: 'mg (tabs), mg/mL (liquid)',
  ),
  MedicationInfo(
    name: 'Cyclobenzaprine',
    brand: 'Flexeril',
    primaryUse: 'Muscle relaxant',
    route: 'Oral tablet',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Dexamethasone',
    brand: 'Decadron',
    primaryUse: 'Corticosteroid for pain, appetite, nausea, brain mets',
    route: 'Oral tablet, oral liquid, IV',
    doseUnit: 'mg (tabs, injection), mg/mL (liquid)',
  ),
  MedicationInfo(
    name: 'Diazepam',
    brand: 'Valium, Diastat',
    primaryUse: 'Anxiety, seizures, muscle spasm',
    route: 'Oral tablet, rectal gel, IV',
    doseUnit: 'mg (tabs, injection), mg/mL (gel)',
  ),
  MedicationInfo(
    name: 'Diclofenac',
    brand: 'Voltaren, Cataflam',
    primaryUse: 'NSAID for pain',
    route: 'Oral tablet, topical gel',
    doseUnit: 'mg (oral), % (topical)',
  ),
  MedicationInfo(
    name: 'Digoxin',
    brand: 'Lanoxin',
    primaryUse: 'Heart failure/AFib',
    route: 'Oral tablet, oral solution',
    doseUnit: 'mcg (tabs), mcg/mL (solution)',
  ),
  MedicationInfo(
    name: 'Diphenhydramine',
    brand: 'Benadryl',
    primaryUse: 'Allergy, nausea, insomnia',
    route: 'Oral tablet/capsule, oral liquid',
    doseUnit: 'mg (tabs), mg/mL (liquid)',
  ),
  MedicationInfo(
    name: 'Docusate',
    brand: 'Colace',
    primaryUse: 'Stool softener',
    route: 'Oral capsule, oral liquid',
    doseUnit: 'mg (capsule), mg/mL (liquid)',
  ),
  MedicationInfo(
    name: 'Duloxetine',
    brand: 'Cymbalta',
    primaryUse: 'Neuropathic pain, depression',
    route: 'Oral capsule',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Enoxaparin',
    brand: 'Lovenox',
    primaryUse: 'Anticoagulation',
    route: 'Subcutaneous injection',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Fentanyl',
    brand: 'Duragesic (patch), Sublimaze (inj), Actiq (lozenge)',
    primaryUse: 'Severe pain/dyspnea',
    route: 'Transdermal patch, IV/SC injection, buccal formulations',
    doseUnit: 'mcg/hr (patch), mcg, mcg/mL (inj)',
  ),
  MedicationInfo(
    name: 'Furosemide',
    brand: 'Lasix',
    primaryUse: 'Edema, dyspnea in CHF',
    route: 'Oral tablet, IV',
    doseUnit: 'mg, mg/mL (IV)',
  ),
  MedicationInfo(
    name: 'Gabapentin',
    brand: 'Neurontin, Gralise, Horizant',
    primaryUse: 'Neuropathic pain',
    route: 'Oral capsule/tablet',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Glycopyrrolate',
    brand: 'Robinul, Cuvposa',
    primaryUse: 'Secretions',
    route: 'Oral tablet, IV/SC injection',
    doseUnit: 'mg, mg/mL (inj)',
  ),
  MedicationInfo(
    name: 'Haloperidol',
    brand: 'Haldol',
    primaryUse: 'Agitation, delirium, nausea',
    route: 'Oral tablet, oral drops, IV/IM',
    doseUnit: 'mg (tabs, inj), mg/mL (drops)',
  ),
  MedicationInfo(
    name: 'Hydralazine',
    brand: 'Apresoline',
    primaryUse: 'Hypertension',
    route: 'Oral tablet',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Hydromorphone',
    brand: 'Dilaudid',
    primaryUse: 'Severe pain',
    route: 'Oral tablet/liquid, IV/SC injection',
    doseUnit: 'mg (tabs), mg/mL (inj, liquid)',
  ),
  MedicationInfo(
    name: 'Hyoscyamine / Hyoscine',
    brand: 'Levsin (hyoscyamine), Transderm Scop (scopolamine)',
    primaryUse: 'Secretions, cramping, nausea',
    route: 'Oral/SL tablet, patch, injection',
    doseUnit: 'mg (tabs, inj), mg/hr or mg/72hr (patch)',
  ),
  MedicationInfo(
    name: 'Ibuprofen',
    brand: 'Advil, Motrin',
    primaryUse: 'NSAID for pain',
    route: 'Oral tablet/capsule, oral liquid',
    doseUnit: 'mg (tabs), mg/mL (liquid)',
  ),
  MedicationInfo(
    name: 'Ipratropium',
    brand: 'Atrovent',
    primaryUse: 'Bronchodilator',
    route: 'Inhaler, nebulizer solution',
    doseUnit: 'mcg/actuation (MDI), mg/mL or % (neb)',
  ),
  MedicationInfo(
    name: 'Isosorbide mononitrate',
    brand: 'Imdur',
    primaryUse: 'Angina',
    route: 'Oral tablet (IR/ER)',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Lactulose',
    brand: 'Enulose, Chronulac, Cephulac',
    primaryUse: 'Osmotic laxative',
    route: 'Oral liquid',
    doseUnit: 'g (per 15 mL) or mL',
  ),
  MedicationInfo(
    name: 'Levetiracetam',
    brand: 'Keppra',
    primaryUse: 'Seizures',
    route: 'Oral tablet/solution, IV',
    doseUnit: 'mg (tabs), mg/mL (solution, IV)',
  ),
  MedicationInfo(
    name: 'Levothyroxine',
    brand: 'Synthroid, Levoxyl, Tirosint',
    primaryUse: 'Hypothyroidism',
    route: 'Oral tablet',
    doseUnit: 'mcg',
  ),
  MedicationInfo(
    name: 'Lidocaine topical',
    brand: 'Lidoderm, LMX',
    primaryUse: 'Localized pain',
    route: 'Topical patch, gel, cream',
    doseUnit: 'mg (patch strength), %',
  ),
  MedicationInfo(
    name: 'Loperamide',
    brand: 'Imodium',
    primaryUse: 'Diarrhea',
    route: 'Oral capsule/tablet, oral liquid',
    doseUnit: 'mg (solid), mg/mL (liquid)',
  ),
  MedicationInfo(
    name: 'Lorazepam',
    brand: 'Ativan',
    primaryUse: 'Anxiety, dyspnea, agitation',
    route: 'Oral tablet, SL tablet, IV',
    doseUnit: 'mg, mg/mL (IV)',
  ),
  MedicationInfo(
    name: 'Magnesium hydroxide',
    brand: 'Milk of Magnesia',
    primaryUse: 'Laxative',
    route: 'Oral liquid',
    doseUnit: 'mL (with mg/mL concentration)',
  ),
  MedicationInfo(
    name: 'Megestrol acetate',
    brand: 'Megace',
    primaryUse: 'Appetite stimulant',
    route: 'Oral suspension/tablet',
    doseUnit: 'mg, mg/mL (suspension)',
  ),
  MedicationInfo(
    name: 'Melatonin',
    brand: 'OTC various',
    primaryUse: 'Insomnia',
    route: 'Oral tablet/capsule',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Methadone',
    brand: 'Dolophine, Methadose',
    primaryUse: 'Complex or neuropathic pain',
    route: 'Oral tablet/solution, sometimes IV',
    doseUnit: 'mg, mg/mL (solution, IV)',
  ),
  MedicationInfo(
    name: 'Metoclopramide',
    brand: 'Reglan',
    primaryUse: 'Nausea, gastroparesis',
    route: 'Oral tablet/solution, IV',
    doseUnit: 'mg (tabs, inj), mg/mL (solution)',
  ),
  MedicationInfo(
    name: 'Metoprolol',
    brand: 'Lopressor (IR), Toprol-XL (ER)',
    primaryUse: 'Beta-blocker for heart disease',
    route: 'Oral tablet (IR/ER)',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Midazolam',
    brand: 'Versed',
    primaryUse: 'Anxiety, seizures, palliative sedation',
    route: 'IV/SC injection, intranasal, buccal',
    doseUnit: 'mg, mg/mL',
  ),
  MedicationInfo(
    name: 'Mirtazapine',
    brand: 'Remeron',
    primaryUse: 'Depression, appetite, sleep',
    route: 'Oral tablet, ODT',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Morphine',
    brand: 'MS Contin, Kadian, Roxanol',
    primaryUse: 'Severe pain, dyspnea',
    route: 'Oral solution/tablet, IV/SC injection',
    doseUnit: 'mg (tabs), mg/mL (solution, inj)',
  ),
  MedicationInfo(
    name: 'Naloxone',
    brand: 'Narcan, Kloxxado',
    primaryUse: 'Opioid reversal (safety)',
    route: 'Intranasal spray, IV/IM/SC injection',
    doseUnit: 'mg, mg/mL',
  ),
  MedicationInfo(
    name: 'Nitroglycerin',
    brand: 'Nitrostat, Nitro-Dur',
    primaryUse: 'Angina',
    route: 'SL tablet/spray, transdermal patch',
    doseUnit: 'mg (SL), mg/hr or mcg/hr (patch)',
  ),
  MedicationInfo(
    name: 'Nystatin',
    brand: 'Mycostatin',
    primaryUse: 'Fungal infections (oral or skin)',
    route: 'Oral suspension, topical cream/powder',
    doseUnit: 'units/mL (oral), %, units (topical)',
  ),
  MedicationInfo(
    name: 'Octreotide',
    brand: 'Sandostatin',
    primaryUse: 'Refractory vomiting, high-output fistula/diarrhea',
    route: 'SC/IV injection',
    doseUnit: 'mcg, mcg/mL',
  ),
  MedicationInfo(
    name: 'Omeprazole / Pantoprazole',
    brand: 'Prilosec (omeprazole), Protonix (pantoprazole)',
    primaryUse: 'GERD, GI protection',
    route: 'Oral capsule/tablet, IV (pantoprazole)',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Ondansetron',
    brand: 'Zofran',
    primaryUse: 'Nausea, vomiting',
    route: 'Oral tablet/ODT, oral solution, IV',
    doseUnit: 'mg (tabs, inj), mg/mL (solution)',
  ),
  MedicationInfo(
    name: 'Oxycodone',
    brand: 'OxyContin, Roxicodone',
    primaryUse: 'Moderate–severe pain',
    route: 'Oral tablet/capsule, oral liquid',
    doseUnit: 'mg, mg/mL (liquid)',
  ),
  MedicationInfo(
    name: 'Paroxetine / Sertraline / Fluoxetine',
    brand: 'Paxil (paroxetine), Zoloft (sertraline), Prozac (fluoxetine)',
    primaryUse: 'Depression, anxiety',
    route: 'Oral tablet/capsule',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Phenobarbital',
    brand: 'Luminal',
    primaryUse: 'Seizures, refractory agitation',
    route: 'Oral tablet, IV',
    doseUnit: 'mg, mg/mL (IV)',
  ),
  MedicationInfo(
    name: 'Phenazopyridine',
    brand: 'Pyridium',
    primaryUse: 'Urinary tract pain',
    route: 'Oral tablet',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Prednisone / Methylprednisolone',
    brand: 'Deltasone (prednisone), Medrol or Solu-Medrol (methylprednisolone)',
    primaryUse: 'Steroid for appetite, pain, inflammation',
    route: 'Oral tablet; methylprednisolone also IV',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Prochlorperazine',
    brand: 'Compazine',
    primaryUse: 'Nausea, agitation',
    route: 'Oral tablet, rectal suppository, IV/IM',
    doseUnit: 'mg, mg/mL (inj)',
  ),
  MedicationInfo(
    name: 'Promethazine',
    brand: 'Phenergan',
    primaryUse: 'Nausea, allergy, sedation',
    route: 'Oral tablet/syrup, rectal suppository, IM',
    doseUnit: 'mg, mg/mL (syrup, inj)',
  ),
  MedicationInfo(
    name: 'Propranolol / Atenolol',
    brand: 'Inderal (propranolol), Tenormin (atenolol)',
    primaryUse: 'Beta-blockers (tachycardia, tremor, anxiety)',
    route: 'Oral tablet',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Quetiapine',
    brand: 'Seroquel',
    primaryUse: 'Agitation, insomnia, mood symptoms',
    route: 'Oral tablet',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Famotidine',
    brand: 'Pepcid',
    primaryUse: 'Acid reduction',
    route: 'Oral tablet, IV',
    doseUnit: 'mg, mg/mL (IV)',
  ),
  MedicationInfo(
    name: 'Scopolamine patch',
    brand: 'Transderm Scop',
    primaryUse: 'Terminal secretions, nausea',
    route: 'Transdermal patch',
    doseUnit: 'mg/72hr (or mg/hr) patch strength',
  ),
  MedicationInfo(
    name: 'Senna / Sennosides',
    brand: 'Senokot, Ex-Lax',
    primaryUse: 'Stimulant laxative',
    route: 'Oral tablet/liquid',
    doseUnit: 'mg (tabs), mg/mL (liquid)',
  ),
  MedicationInfo(
    name: 'Simethicone',
    brand: 'Gas-X, Mylicon',
    primaryUse: 'Gas, bloating',
    route: 'Oral chewable tablet, oral drops',
    doseUnit: 'mg, mg/mL (drops)',
  ),
  MedicationInfo(
    name: 'Spironolactone',
    brand: 'Aldactone',
    primaryUse: 'CHF, ascites (diuretic)',
    route: 'Oral tablet',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Sucralfate',
    brand: 'Carafate',
    primaryUse: 'GI mucosal protection',
    route: 'Oral tablet/suspension',
    doseUnit: 'mg (tabs), g/10 mL (suspension)',
  ),
  MedicationInfo(
    name: 'Sulfonylureas (e.g., glipizide)',
    brand: 'Glucotrol (glipizide)',
    primaryUse: 'Diabetes',
    route: 'Oral tablet',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Tizanidine',
    brand: 'Zanaflex',
    primaryUse: 'Muscle spasm',
    route: 'Oral tablet/capsule',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Topiramate / other antiepileptics',
    brand: 'Topamax (topiramate)',
    primaryUse: 'Seizures, neuropathic pain',
    route: 'Oral tablet/capsule',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Tramadol',
    brand: 'Ultram',
    primaryUse: 'Mild–moderate pain',
    route: 'Oral tablet/capsule',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Trazodone',
    brand: 'Desyrel, Oleptro',
    primaryUse: 'Insomnia, depression',
    route: 'Oral tablet',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Valproic acid',
    brand: 'Depakene, Depakote (divalproex)',
    primaryUse: 'Seizures, mood stabilization',
    route: 'Oral capsule/solution, IV',
    doseUnit: 'mg, mg/mL',
  ),
  MedicationInfo(
    name: 'Venlafaxine',
    brand: 'Effexor',
    primaryUse: 'Depression, neuropathic pain',
    route: 'Oral tablet/capsule',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Verapamil / Diltiazem',
    brand: 'Calan or Verelan (verapamil), Cardizem (diltiazem)',
    primaryUse: 'Rate control, hypertension',
    route: 'Oral tablet/capsule (some IV forms)',
    doseUnit: 'mg, mg/mL (IV)',
  ),
  MedicationInfo(
    name: 'Vitamin D / multivitamins',
    brand: 'Drisdol (vitamin D2), Centrum (multivitamin)',
    primaryUse: 'General supplementation (often deprescribed)',
    route: 'Oral tablet/capsule',
    doseUnit: 'International Units (IU), mg',
  ),
  MedicationInfo(
    name: 'Warfarin',
    brand: 'Coumadin, Jantoven',
    primaryUse: 'Anticoagulation',
    route: 'Oral tablet',
    doseUnit: 'mg',
  ),
  MedicationInfo(
    name: 'Zolpidem',
    brand: 'Ambien',
    primaryUse: 'Insomnia',
    route: 'Oral tablet',
    doseUnit: 'mg',
  ),
];
