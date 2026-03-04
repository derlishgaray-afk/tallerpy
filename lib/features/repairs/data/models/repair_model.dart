import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/data/firestore_parsers.dart';

class RepairModel {
  final String id;
  final String title;
  final String km;
  final String description;
  final String status;
  final num labor;
  final num parts;
  final num total;
  final String customerId;
  final String customerName;
  final String vehicleId;
  final String vehicleTitle;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const RepairModel({
    required this.id,
    required this.title,
    required this.km,
    required this.description,
    required this.status,
    required this.labor,
    required this.parts,
    required this.total,
    required this.customerId,
    required this.customerName,
    required this.vehicleId,
    required this.vehicleTitle,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RepairModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? _,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    return RepairModel(
      id: snapshot.id,
      title: readString(data, 'title'),
      km: readString(data, 'km'),
      description: readString(data, 'description'),
      status: readString(data, 'status'),
      labor: readNum(data, 'labor'),
      parts: readNum(data, 'parts'),
      total: readNum(data, 'total'),
      customerId: readString(data, 'customerId'),
      customerName: readString(data, 'customerName'),
      vehicleId: readString(data, 'vehicleId'),
      vehicleTitle: readString(data, 'vehicleTitle'),
      createdAt: parseFirestoreDate(data['createdAt']),
      updatedAt: parseFirestoreDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'km': km,
      'description': description,
      'status': status,
      'labor': labor,
      'parts': parts,
      'total': total,
      'customerId': customerId,
      'customerName': customerName,
      'vehicleId': vehicleId,
      'vehicleTitle': vehicleTitle,
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
      'updatedAt': updatedAt == null ? null : Timestamp.fromDate(updatedAt!),
    };
  }

  static CollectionReference<RepairModel> collectionForUserVehicle(
    FirebaseFirestore firestore,
    String uid,
    String customerId,
    String vehicleId,
  ) {
    return firestore
        .collection('users')
        .doc(uid)
        .collection('customers')
        .doc(customerId)
        .collection('vehicles')
        .doc(vehicleId)
        .collection('repairs')
        .withConverter<RepairModel>(
          fromFirestore: RepairModel.fromFirestore,
          toFirestore: (model, _) => model.toFirestore(),
        );
  }
}
