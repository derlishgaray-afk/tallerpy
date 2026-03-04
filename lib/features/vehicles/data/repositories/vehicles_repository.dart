import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/vehicle_model.dart';

class VehiclesRepository {
  final FirebaseFirestore _firestore;

  VehiclesRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<VehicleModel> _vehiclesCol(
    String uid,
    String customerId,
  ) {
    return VehicleModel.collectionForUserCustomer(_firestore, uid, customerId);
  }

  Stream<QuerySnapshot<VehicleModel>> watchVehiclesForCustomer(
    String uid,
    String customerId,
  ) {
    return _vehiclesCol(
      uid,
      customerId,
    ).orderBy('updatedAt', descending: true).snapshots();
  }

  Stream<DocumentSnapshot<VehicleModel>> watchVehicleById(
    String uid,
    String customerId,
    String vehicleId,
  ) {
    return _vehiclesCol(uid, customerId).doc(vehicleId).snapshots();
  }

  Future<void> deleteVehicle(String uid, String customerId, String vehicleId) {
    return _vehiclesCol(uid, customerId).doc(vehicleId).delete();
  }
}
