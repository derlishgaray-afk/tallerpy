import 'package:cloud_firestore/cloud_firestore.dart';

class RepairHubItem {
  final String customerId;
  final String vehicleId;
  final String repairId;
  final Map<String, dynamic> data;

  const RepairHubItem({
    required this.customerId,
    required this.vehicleId,
    required this.repairId,
    required this.data,
  });
}

class RepairsHubRepository {
  final FirebaseFirestore _firestore;

  RepairsHubRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<List<RepairHubItem>> loadRepairsForUser(String uid) async {
    final snap = await _firestore.collectionGroup('repairs').get();
    final items = <RepairHubItem>[];

    for (final doc in snap.docs) {
      final ids = _idsFromRepairPath(doc.reference.path);
      if (ids == null) continue;
      if (ids.userId != uid) continue;

      final raw = doc.data();
      final data = Map<String, dynamic>.from(raw);

      final customerName = (data['customerName'] ?? '').toString().trim();
      if (customerName.isEmpty) {
        data['customerName'] = 'Cliente';
      }

      final vehicleTitle = (data['vehicleTitle'] ?? '').toString().trim();
      if (vehicleTitle.isEmpty) {
        data['vehicleTitle'] = 'Vehiculo';
      }

      items.add(
        RepairHubItem(
          customerId: ids.customerId,
          vehicleId: ids.vehicleId,
          repairId: doc.id,
          data: data,
        ),
      );
    }

    items.sort((a, b) => _sortKey(b.data).compareTo(_sortKey(a.data)));
    return items;
  }

  int _sortKey(Map<String, dynamic> data) {
    final ts = _readTs(data['updatedAt']) ?? _readTs(data['createdAt']);
    return ts?.millisecondsSinceEpoch ?? 0;
  }

  DateTime? _readTs(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  _RepairPathIds? _idsFromRepairPath(String path) {
    final segments = path.split('/');
    if (segments.length != 8) return null;
    if (segments[0] != 'users' ||
        segments[2] != 'customers' ||
        segments[4] != 'vehicles' ||
        segments[6] != 'repairs') {
      return null;
    }

    return _RepairPathIds(
      userId: segments[1],
      customerId: segments[3],
      vehicleId: segments[5],
    );
  }
}

class _RepairPathIds {
  final String userId;
  final String customerId;
  final String vehicleId;

  const _RepairPathIds({
    required this.userId,
    required this.customerId,
    required this.vehicleId,
  });
}
