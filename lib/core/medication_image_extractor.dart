import 'dart:convert';
import 'dart:typed_data';

import 'package:google_generative_ai/google_generative_ai.dart';

class MedicationImageExtraction {
  const MedicationImageExtraction({
    this.name,
    this.dosageAmount,
    this.dosageUnit,
    this.route,
    this.isPrn,
    this.frequency,
    this.instructions,
    this.prescribedDate,
  });

  final String? name;
  final String? dosageAmount;
  final String? dosageUnit;
  final String? route;
  final bool? isPrn;
  final String? frequency;
  final String? instructions;
  final DateTime? prescribedDate;

  static MedicationImageExtraction fromJson(Map<String, dynamic> json) {
    DateTime? parsedDate;
    final rawDate = json['prescribed_date'];
    if (rawDate is String && rawDate.trim().isNotEmpty) {
      parsedDate = DateTime.tryParse(rawDate);
    }

    bool? parsedPrn;
    final rawPrn = json['is_prn'];
    if (rawPrn is bool) parsedPrn = rawPrn;
    if (rawPrn is String) {
      final normalized = rawPrn.trim().toLowerCase();
      if (normalized == 'true') parsedPrn = true;
      if (normalized == 'false') parsedPrn = false;
    }

    String? str(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    return MedicationImageExtraction(
      name: str(json['name']),
      dosageAmount: str(json['dosage_amount']),
      dosageUnit: str(json['dosage_unit']),
      route: str(json['route']),
      isPrn: parsedPrn,
      frequency: str(json['frequency']),
      instructions: str(json['instructions']),
      prescribedDate: parsedDate,
    );
  }
}

class GeminiMedicationImageExtractor {
  GeminiMedicationImageExtractor({required this.apiKey});

  final String apiKey;

  static const List<String> _defaultModelCandidates = <String>[
    // Some keys/projects do not have access to older 1.5 model IDs.
    // Prefer Flash models for speed and cost.
    'gemini-flash-latest',
    'gemini-2.0-flash',
    'gemini-2.5-flash',
  ];

  Future<MedicationImageExtraction> extract({
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const _GeminiConfigException('Missing GEMINI_API_KEY');
    }

    const schemaHint =
        '{'
        '"name": string|null,'
        '"dosage_amount": string|null,'
        '"dosage_unit": "mg"|"mcg"|"mL"|"tabs"|"caps"|"drops"|null,'
        '"route": "By mouth"|"Sublingual"|"Topical"|"Injection"|"Suppository"|"Inhaled"|"Other"|null,'
        '"is_prn": boolean|null,'
        '"frequency": string|null,'
        '"prescribed_date": string|null,'
        '"instructions": string|null'
        '}';

    const prompt =
        'You are given a photo of a medication box/strip/bottle label or a prescription.\n'
        'Extract medication details and return ONLY a single JSON object (no markdown, no code fences).\n'
        'Use this exact schema and key names: '
        '$schemaHint\n'
        'Rules:\n'
        '- If a value is not present or you are unsure, set it to null.\n'
        '- Use dosage_unit from the allowed set in the schema.\n'
        '- Use route from the allowed set in the schema.\n'
        '- For prescribed_date: if you can identify a date, return ISO-8601 date-time string; otherwise null.\n'
        '- frequency can be plain text as seen (e.g., "Once daily", "Twice daily", "Every 6 hours", "As needed").\n'
        '- instructions: include directions like "take with food" if present.';

    final response = await _generateWithFallback(
      prompt: prompt,
      mimeType: mimeType,
      imageBytes: imageBytes,
    );

    final text = (response.text ?? '').trim();
    if (text.isEmpty) {
      throw const _GeminiParseException('Empty response from model');
    }

    final jsonText = _extractJsonObject(text);
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) {
      throw const _GeminiParseException('Expected a JSON object');
    }

    return MedicationImageExtraction.fromJson(decoded);
  }

  Future<GenerateContentResponse> _generateWithFallback({
    required String prompt,
    required String mimeType,
    required Uint8List imageBytes,
  }) async {
    Object? lastError;

    for (final modelName in _defaultModelCandidates) {
      try {
        final model = GenerativeModel(model: modelName, apiKey: apiKey);
        return await model.generateContent([
          Content.multi([TextPart(prompt), DataPart(mimeType, imageBytes)]),
        ]);
      } catch (e) {
        lastError = e;
      }
    }

    // Surface the last error for debugging.
    throw Exception(lastError?.toString() ?? 'Gemini request failed');
  }

  String _extractJsonObject(String raw) {
    final cleaned = raw.replaceAll('```json', '').replaceAll('```', '').trim();

    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) {
      throw const _GeminiParseException('Could not find JSON object');
    }
    return cleaned.substring(start, end + 1);
  }
}

class _GeminiConfigException implements Exception {
  const _GeminiConfigException(this.message);
  final String message;
  @override
  String toString() => message;
}

class _GeminiParseException implements Exception {
  const _GeminiParseException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Small helper so callers can safely show the error.
extension GeminiUserMessage on Object {
  String toUserMessage() {
    final v = this;
    if (v is _GeminiConfigException) {
      return 'Missing Gemini API key. Please set GEMINI_API_KEY.';
    }
    if (v is _GeminiParseException) {
      return 'Could not read medication details from this image.';
    }
    return 'Something went wrong while reading the image.';
  }
}
