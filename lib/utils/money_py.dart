import 'package:intl/intl.dart';

final NumberFormat gs = NumberFormat.decimalPattern('es_PY');

/// "1500000" -> "1.500.000"
String formatGsText(String raw) {
  final cleaned = raw.replaceAll('.', '').replaceAll(',', '').trim();
  final n = int.tryParse(cleaned);
  if (n == null) return raw;
  return gs.format(n);
}

/// "1.500.000" -> 1500000
int parseGsText(String formatted) {
  final cleaned = formatted.replaceAll('.', '').replaceAll(',', '').trim();
  return int.tryParse(cleaned) ?? 0;
}
