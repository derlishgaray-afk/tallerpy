import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/data/firestore_parsers.dart';

class CustomerModel {
  final String id;
  final String name;
  final String phone;
  final String address;
  final String ruc;
  final String notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CustomerModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.address,
    required this.ruc,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CustomerModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? _,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    return CustomerModel(
      id: snapshot.id,
      name: readString(data, 'name'),
      phone: readString(data, 'phone'),
      address: readString(data, 'address'),
      ruc: readString(data, 'ruc'),
      notes: readString(data, 'notes'),
      createdAt: parseFirestoreDate(data['createdAt']),
      updatedAt: parseFirestoreDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'phone': phone,
      'address': address,
      'ruc': ruc,
      'notes': notes,
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
      'updatedAt': updatedAt == null ? null : Timestamp.fromDate(updatedAt!),
    };
  }

  static CollectionReference<CustomerModel> collectionForUser(
    FirebaseFirestore firestore,
    String uid,
  ) {
    return firestore
        .collection('users')
        .doc(uid)
        .collection('customers')
        .withConverter<CustomerModel>(
          fromFirestore: CustomerModel.fromFirestore,
          toFirestore: (model, _) => model.toFirestore(),
        );
  }
}
