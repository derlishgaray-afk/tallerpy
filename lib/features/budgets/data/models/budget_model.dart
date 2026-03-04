import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/data/firestore_parsers.dart';

class BudgetPartItem {
  final String name;
  final num unitPrice;

  const BudgetPartItem({required this.name, required this.unitPrice});

  factory BudgetPartItem.fromMap(Map<String, dynamic> map) {
    return BudgetPartItem(
      name: readString(map, 'name'),
      unitPrice: readNum(map, 'unitPrice'),
    );
  }

  Map<String, dynamic> toMap() {
    return {'name': name, 'unitPrice': unitPrice};
  }
}

class BudgetModel {
  final String id;
  final String title;
  final String customerId;
  final String customerName;
  final String vehicleId;
  final String vehicleTitle;
  final DateTime? date;
  final String problemDescription;
  final int estimatedDays;
  final bool usePartsItems;
  final List<BudgetPartItem> partsItems;
  final num partsEstimated;
  final num laborEstimated;
  final num totalEstimated;
  final String observations;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const BudgetModel({
    required this.id,
    required this.title,
    required this.customerId,
    required this.customerName,
    required this.vehicleId,
    required this.vehicleTitle,
    required this.date,
    required this.problemDescription,
    required this.estimatedDays,
    required this.usePartsItems,
    required this.partsItems,
    required this.partsEstimated,
    required this.laborEstimated,
    required this.totalEstimated,
    required this.observations,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BudgetModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? _,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    final rawParts = (data['partsItems'] as List<dynamic>? ?? const []);
    return BudgetModel(
      id: snapshot.id,
      title: readString(data, 'title'),
      customerId: readString(data, 'customerId'),
      customerName: readString(data, 'customerName'),
      vehicleId: readString(data, 'vehicleId'),
      vehicleTitle: readString(data, 'vehicleTitle'),
      date: parseFirestoreDate(data['date']),
      problemDescription: readString(data, 'problemDescription'),
      estimatedDays: readInt(data, 'estimatedDays'),
      usePartsItems: readBool(data, 'usePartsItems'),
      partsItems: rawParts
          .whereType<Map>()
          .map(
            (item) => BudgetPartItem.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList(),
      partsEstimated: readNum(data, 'partsEstimated'),
      laborEstimated: readNum(data, 'laborEstimated'),
      totalEstimated: readNum(data, 'totalEstimated'),
      observations: readString(data, 'observations'),
      status: readString(data, 'status'),
      createdAt: parseFirestoreDate(data['createdAt']),
      updatedAt: parseFirestoreDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'customerId': customerId,
      'customerName': customerName,
      'vehicleId': vehicleId,
      'vehicleTitle': vehicleTitle,
      'date': date == null ? null : Timestamp.fromDate(date!),
      'problemDescription': problemDescription,
      'estimatedDays': estimatedDays,
      'usePartsItems': usePartsItems,
      'partsItems': partsItems.map((item) => item.toMap()).toList(),
      'partsEstimated': partsEstimated,
      'laborEstimated': laborEstimated,
      'totalEstimated': totalEstimated,
      'observations': observations,
      'status': status,
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
      'updatedAt': updatedAt == null ? null : Timestamp.fromDate(updatedAt!),
    };
  }

  static CollectionReference<BudgetModel> collectionForUser(
    FirebaseFirestore firestore,
    String uid,
  ) {
    return firestore
        .collection('users')
        .doc(uid)
        .collection('budgets')
        .withConverter<BudgetModel>(
          fromFirestore: BudgetModel.fromFirestore,
          toFirestore: (model, _) => model.toFirestore(),
        );
  }
}
