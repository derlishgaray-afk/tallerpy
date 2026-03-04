import 'package:cloud_firestore/cloud_firestore.dart';

class CustomerLookup {
  final String id;
  final String name;
  final String phone;
  final String ruc;

  const CustomerLookup({
    required this.id,
    required this.name,
    required this.phone,
    required this.ruc,
  });

  factory CustomerLookup.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return CustomerLookup(
      id: doc.id,
      name: (data['name'] ?? '').toString().trim(),
      phone: (data['phone'] ?? '').toString().trim(),
      ruc: (data['ruc'] ?? '').toString().trim(),
    );
  }
}

class VehicleLookup {
  final String id;
  final String brand;
  final String model;
  final String plate;
  final String year;

  const VehicleLookup({
    required this.id,
    required this.brand,
    required this.model,
    required this.plate,
    required this.year,
  });

  factory VehicleLookup.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return VehicleLookup(
      id: doc.id,
      brand: (data['brand'] ?? '').toString().trim(),
      model: (data['model'] ?? '').toString().trim(),
      plate: (data['plate'] ?? '').toString().trim(),
      year: (data['year'] ?? '').toString().trim(),
    );
  }

  factory VehicleLookup.fromMap(String id, Map<String, dynamic> data) {
    return VehicleLookup(
      id: id,
      brand: (data['brand'] ?? '').toString().trim(),
      model: (data['model'] ?? '').toString().trim(),
      plate: (data['plate'] ?? '').toString().trim(),
      year: (data['year'] ?? '').toString().trim(),
    );
  }

  String get title {
    final base = [brand, model].where((e) => e.isNotEmpty).join(' ').trim();
    if (plate.isEmpty) return base.isEmpty ? 'Vehiculo' : base;
    return base.isEmpty ? plate : '$base - $plate';
  }
}

class BudgetFormRepository {
  final FirebaseFirestore _firestore;

  BudgetFormRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _budgetsCol(String uid) {
    return _firestore.collection('users').doc(uid).collection('budgets');
  }

  CollectionReference<Map<String, dynamic>> _customersCol(String uid) {
    return _firestore.collection('users').doc(uid).collection('customers');
  }

  CollectionReference<Map<String, dynamic>> _vehiclesCol(
    String uid,
    String customerId,
  ) {
    return _customersCol(uid).doc(customerId).collection('vehicles');
  }

  Future<List<CustomerLookup>> listCustomers(String uid) async {
    final snap = await _customersCol(uid).orderBy('name').get();
    return snap.docs.map(CustomerLookup.fromDoc).toList();
  }

  Future<CustomerLookup?> getCustomerById(String uid, String customerId) async {
    final snap = await _customersCol(uid).doc(customerId).get();
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return CustomerLookup(
      id: snap.id,
      name: (data['name'] ?? '').toString().trim(),
      phone: (data['phone'] ?? '').toString().trim(),
      ruc: (data['ruc'] ?? '').toString().trim(),
    );
  }

  Future<List<VehicleLookup>> listVehiclesForCustomer(
    String uid,
    String customerId,
  ) async {
    final snap = await _vehiclesCol(
      uid,
      customerId,
    ).orderBy('updatedAt', descending: true).get();
    return snap.docs.map(VehicleLookup.fromDoc).toList();
  }

  Future<VehicleLookup?> getVehicleById(
    String uid,
    String customerId,
    String vehicleId,
  ) async {
    final snap = await _vehiclesCol(uid, customerId).doc(vehicleId).get();
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return VehicleLookup.fromMap(snap.id, data);
  }

  Future<String> saveBudget({
    required String uid,
    required Map<String, dynamic> data,
    String? budgetId,
  }) async {
    final payload = Map<String, dynamic>.from(data);
    payload['updatedAt'] = FieldValue.serverTimestamp();

    if (budgetId == null) {
      payload['createdAt'] = FieldValue.serverTimestamp();
      final ref = await _budgetsCol(uid).add(payload);
      return ref.id;
    }

    await _budgetsCol(uid).doc(budgetId).set(payload, SetOptions(merge: true));
    return budgetId;
  }

  Future<String> approveAndConvert({
    required String uid,
    required String budgetId,
    required String customerId,
    required String vehicleId,
    required String customerName,
    required String vehicleTitle,
    required String repairTitle,
    required String repairDescription,
    required bool usePartsItems,
    required List<Map<String, dynamic>> partsItems,
    required num labor,
    required num parts,
  }) async {
    final repairsCol = _firestore
        .collection('users')
        .doc(uid)
        .collection('customers')
        .doc(customerId)
        .collection('vehicles')
        .doc(vehicleId)
        .collection('repairs');

    final repairRef = repairsCol.doc();
    final total = labor + parts;

    final repairData = <String, dynamic>{
      'title': repairTitle,
      'km': '',
      'description': repairDescription,
      'status': 'Abierta',
      'labor': labor,
      'parts': parts,
      'total': total,
      'usePartsItems': usePartsItems,
      'partsItems': partsItems,
      'customerId': customerId,
      'customerName': customerName,
      'vehicleId': vehicleId,
      'vehicleTitle': vehicleTitle,
      'sourceBudgetId': budgetId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final batch = _firestore.batch();
    batch.set(repairRef, repairData);
    batch.set(_budgetsCol(uid).doc(budgetId), {
      'status': 'Aprobado',
      'approvedAt': FieldValue.serverTimestamp(),
      'repairId': repairRef.id,
      'repairPath': repairRef.path,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
    return repairRef.id;
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
}
