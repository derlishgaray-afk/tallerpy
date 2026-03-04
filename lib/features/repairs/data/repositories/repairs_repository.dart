import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/repair_model.dart';

class RepairsPage {
  final List<RepairModel> items;
  final bool hasMore;

  const RepairsPage({required this.items, required this.hasMore});
}

class RepairsRepository {
  final FirebaseFirestore _firestore;

  QueryDocumentSnapshot<RepairModel>? _lastDoc;
  bool _hasMore = true;
  String? _scopeKey;

  RepairsRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<RepairsPage> fetchFirstPage({
    required String uid,
    required String customerId,
    required String vehicleId,
    required String statusFilter,
    int limit = 25,
  }) async {
    _scopeKey = _buildScopeKey(uid, customerId, vehicleId, statusFilter);
    _lastDoc = null;
    _hasMore = true;
    return _fetchPage(
      uid: uid,
      customerId: customerId,
      vehicleId: vehicleId,
      statusFilter: statusFilter,
      limit: limit,
    );
  }

  Future<RepairsPage> fetchNextPage({
    required String uid,
    required String customerId,
    required String vehicleId,
    required String statusFilter,
    int limit = 25,
  }) async {
    final nextKey = _buildScopeKey(uid, customerId, vehicleId, statusFilter);
    if (_scopeKey != nextKey) {
      return fetchFirstPage(
        uid: uid,
        customerId: customerId,
        vehicleId: vehicleId,
        statusFilter: statusFilter,
        limit: limit,
      );
    }

    if (!_hasMore) {
      return const RepairsPage(items: <RepairModel>[], hasMore: false);
    }

    return _fetchPage(
      uid: uid,
      customerId: customerId,
      vehicleId: vehicleId,
      statusFilter: statusFilter,
      limit: limit,
    );
  }

  Future<RepairsPage> _fetchPage({
    required String uid,
    required String customerId,
    required String vehicleId,
    required String statusFilter,
    required int limit,
  }) async {
    Query<RepairModel> query = _baseQuery(
      uid: uid,
      customerId: customerId,
      vehicleId: vehicleId,
      statusFilter: statusFilter,
    ).limit(limit);

    if (_lastDoc != null) {
      query = query.startAfterDocument(_lastDoc!);
    }

    final snap = await query.get();
    final docs = snap.docs;
    if (docs.isNotEmpty) {
      _lastDoc = docs.last;
    }

    _hasMore = docs.length == limit;
    return RepairsPage(
      items: docs.map((doc) => doc.data()).toList(),
      hasMore: _hasMore,
    );
  }

  Query<RepairModel> _baseQuery({
    required String uid,
    required String customerId,
    required String vehicleId,
    required String statusFilter,
  }) {
    Query<RepairModel> query = RepairModel.collectionForUserVehicle(
      _firestore,
      uid,
      customerId,
      vehicleId,
    ).orderBy('updatedAt', descending: true);

    if (statusFilter != 'Todas') {
      query = query.where('status', isEqualTo: statusFilter);
    }
    return query;
  }

  String _buildScopeKey(
    String uid,
    String customerId,
    String vehicleId,
    String statusFilter,
  ) {
    return '$uid|$customerId|$vehicleId|$statusFilter';
  }
}
