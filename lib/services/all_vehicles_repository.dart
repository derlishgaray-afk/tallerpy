import 'package:cloud_firestore/cloud_firestore.dart';

class VehicleSearchItem {
  final String customerId;
  final String vehicleId;
  final Map<String, dynamic> data;

  const VehicleSearchItem({
    required this.customerId,
    required this.vehicleId,
    required this.data,
  });
}

class AllVehiclesRepository {
  final FirebaseFirestore _firestore;

  AllVehiclesRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<List<VehicleSearchItem>> loadVehiclesForUser(String uid) async {
    try {
      final snap = await _firestore
          .collectionGroup('vehicles')
          .where('ownerUid', isEqualTo: uid)
          .get();
      final items = snap.docs
          .map((doc) => _fromDoc(doc, fallbackCustomerId: _pathCustomerId(doc)))
          .whereType<VehicleSearchItem>()
          .toList();
      items.sort((a, b) => _sortKey(b.data).compareTo(_sortKey(a.data)));
      return items;
    } on FirebaseException catch (e) {
      // Si rules no permiten collectionGroup, usamos fallback por cliente.
      if (e.code != 'permission-denied') rethrow;
      return _fallbackByCustomer(uid);
    }
  }

  Future<List<VehicleSearchItem>> _fallbackByCustomer(String uid) async {
    final customersSnap = await _firestore
        .collection('users')
        .doc(uid)
        .collection('customers')
        .get();

    final vehicleFutures = customersSnap.docs.map(
      (customerDoc) => customerDoc.reference
          .collection('vehicles')
          .orderBy('updatedAt', descending: true)
          .get(),
    );

    final vehicleSnaps = await Future.wait(vehicleFutures);
    final items = <VehicleSearchItem>[];

    for (final vehicleSnap in vehicleSnaps) {
      for (final doc in vehicleSnap.docs) {
        final item = _fromDoc(doc, fallbackCustomerId: _pathCustomerId(doc));
        if (item != null) items.add(item);
      }
    }

    items.sort((a, b) => _sortKey(b.data).compareTo(_sortKey(a.data)));
    return items;
  }

  VehicleSearchItem? _fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    required String fallbackCustomerId,
  }) {
    final data = Map<String, dynamic>.from(doc.data());
    final customerId = (data['customerId'] ?? fallbackCustomerId)
        .toString()
        .trim();
    if (customerId.isEmpty) return null;

    return VehicleSearchItem(
      customerId: customerId,
      vehicleId: doc.id,
      data: data,
    );
  }

  String _pathCustomerId(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final segments = doc.reference.path.split('/');
    if (segments.length >= 4 && segments[2] == 'customers') {
      return segments[3];
    }
    return '';
  }

  int _sortKey(Map<String, dynamic> data) {
    final date = _readDate(data['updatedAt']) ?? _readDate(data['createdAt']);
    return date?.millisecondsSinceEpoch ?? 0;
  }

  DateTime? _readDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
