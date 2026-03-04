import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? parseFirestoreDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

String readString(Map<String, dynamic> map, String key) {
  return (map[key] ?? '').toString().trim();
}

bool readBool(Map<String, dynamic> map, String key, {bool fallback = false}) {
  final value = map[key];
  if (value is bool) return value;
  return fallback;
}

int readInt(Map<String, dynamic> map, String key, {int fallback = 0}) {
  final value = map[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse((value ?? '').toString()) ?? fallback;
}

num readNum(Map<String, dynamic> map, String key, {num fallback = 0}) {
  final value = map[key];
  if (value is num) return value;
  return num.tryParse((value ?? '').toString()) ?? fallback;
}
