import 'package:cloud_firestore/cloud_firestore.dart';

class RepairFormRepository {
  final FirebaseFirestore _firestore;

  RepairFormRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _repairsCol(
    String uid,
    String customerId,
    String vehicleId,
  ) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('customers')
        .doc(customerId)
        .collection('vehicles')
        .doc(vehicleId)
        .collection('repairs');
  }

  Future<void> saveRepair({
    required String uid,
    required String customerId,
    required String vehicleId,
    required Map<String, dynamic> data,
    String? repairId,
  }) async {
    final payload = Map<String, dynamic>.from(data);
    payload['updatedAt'] = FieldValue.serverTimestamp();

    if (repairId == null) {
      payload['createdAt'] = FieldValue.serverTimestamp();
      await _repairsCol(uid, customerId, vehicleId).add(payload);
      return;
    }

    await _repairsCol(
      uid,
      customerId,
      vehicleId,
    ).doc(repairId).set(payload, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>> loadWorkshopProfile(String uid) async {
    final snap = await _firestore.collection('users').doc(uid).get();
    final data = snap.data() ?? <String, dynamic>{};
    final profile = (data['profile'] as Map<String, dynamic>?) ?? {};
    return {
      'name': (profile['name'] ?? '').toString().trim(),
      'owner': (profile['owner'] ?? '').toString().trim(),
      'address': (profile['address'] ?? '').toString().trim(),
      'phone': (profile['phone'] ?? '').toString().trim(),
      'ruc': (profile['ruc'] ?? '').toString().trim(),
    };
  }

  Future<String> resolveCustomerName({
    required String uid,
    required String customerId,
    required String fallbackName,
  }) async {
    if (fallbackName.trim().isNotEmpty) return fallbackName.trim();

    final snap = await _firestore
        .collection('users')
        .doc(uid)
        .collection('customers')
        .doc(customerId)
        .get();
    final data = snap.data() ?? <String, dynamic>{};
    final fromDb = (data['name'] ?? '').toString().trim();
    return fromDb.isEmpty ? 'Cliente' : fromDb;
  }
}
