import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/data/firestore_parsers.dart';

class VehicleModel {
  final String id;
  final String customerId;
  final String ownerUid;
  final String brand;
  final String model;
  final String plate;
  final String plateNorm;
  final String year;
  final String chassis;
  final String notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const VehicleModel({
    required this.id,
    required this.customerId,
    required this.ownerUid,
    required this.brand,
    required this.model,
    required this.plate,
    required this.plateNorm,
    required this.year,
    required this.chassis,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory VehicleModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? _,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    return VehicleModel(
      id: snapshot.id,
      customerId: readString(data, 'customerId'),
      ownerUid: readString(data, 'ownerUid'),
      brand: readString(data, 'brand'),
      model: readString(data, 'model'),
      plate: readString(data, 'plate'),
      plateNorm: readString(data, 'plateNorm'),
      year: readString(data, 'year'),
      chassis: readString(data, 'chassis'),
      notes: readString(data, 'notes'),
      createdAt: parseFirestoreDate(data['createdAt']),
      updatedAt: parseFirestoreDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'customerId': customerId,
      'ownerUid': ownerUid,
      'brand': brand,
      'model': model,
      'plate': plate,
      'plateNorm': plateNorm,
      'year': year,
      'chassis': chassis,
      'notes': notes,
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
      'updatedAt': updatedAt == null ? null : Timestamp.fromDate(updatedAt!),
    };
  }

  static CollectionReference<VehicleModel> collectionForUserCustomer(
    FirebaseFirestore firestore,
    String uid,
    String customerId,
  ) {
    return firestore
        .collection('users')
        .doc(uid)
        .collection('customers')
        .doc(customerId)
        .collection('vehicles')
        .withConverter<VehicleModel>(
          fromFirestore: VehicleModel.fromFirestore,
          toFirestore: (model, _) => model.toFirestore(),
        );
  }
}
