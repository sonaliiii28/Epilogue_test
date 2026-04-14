String personDisplayName(String? raw, {String fallback = 'Caregiver'}) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return fallback;

  // Common pattern: "Name <email@domain.com>"
  final lt = value.indexOf('<');
  final gt = value.indexOf('>');
  if (lt != -1 && gt != -1 && gt > lt) {
    final before = value.substring(0, lt).trim();
    if (before.isNotEmpty && !before.contains('@')) return before;

    final inside = value.substring(lt + 1, gt).trim();
    if (inside.isNotEmpty) {
      return personDisplayName(inside, fallback: fallback);
    }
  }

  if (!value.contains('@')) return value;

  // Convert email address to a readable name.
  final localPart = value.split('@').first.trim();
  if (localPart.isEmpty) return fallback;

  final words = localPart
      .replaceAll(RegExp(r'[._\-]+'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.trim().isNotEmpty)
      .toList();
  if (words.isEmpty) return fallback;

  String titleCaseWord(String w) {
    if (w.isEmpty) return w;
    final lower = w.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }

  final pretty = words.map(titleCaseWord).join(' ').trim();
  return pretty.isEmpty ? fallback : pretty;
}
