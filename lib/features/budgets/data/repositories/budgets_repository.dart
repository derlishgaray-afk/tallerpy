import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/budget_model.dart';

class BudgetsPage {
  final List<BudgetModel> items;
  final bool hasMore;

  const BudgetsPage({required this.items, required this.hasMore});
}

class BudgetsRepository {
  final FirebaseFirestore _firestore;

  QueryDocumentSnapshot<BudgetModel>? _lastDoc;
  bool _hasMore = true;
  String? _scopeKey;

  BudgetsRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<BudgetsPage> fetchFirstPage({
    required String uid,
    String? customerId,
    String? vehicleId,
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

  Future<BudgetsPage> fetchNextPage({
    required String uid,
    String? customerId,
    String? vehicleId,
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
      return const BudgetsPage(items: <BudgetModel>[], hasMore: false);
    }

    return _fetchPage(
      uid: uid,
      customerId: customerId,
      vehicleId: vehicleId,
      statusFilter: statusFilter,
      limit: limit,
    );
  }

  Future<BudgetsPage> _fetchPage({
    required String uid,
    String? customerId,
    String? vehicleId,
    required String statusFilter,
    required int limit,
  }) async {
    Query<BudgetModel> query = _baseQuery(
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
    return BudgetsPage(
      items: docs.map((doc) => doc.data()).toList(),
      hasMore: _hasMore,
    );
  }

  Query<BudgetModel> _baseQuery({
    required String uid,
    String? customerId,
    String? vehicleId,
    required String statusFilter,
  }) {
    Query<BudgetModel> query = BudgetModel.collectionForUser(
      _firestore,
      uid,
    ).orderBy('updatedAt', descending: true);

    if (customerId != null) {
      query = query.where('customerId', isEqualTo: customerId);
    }
    if (vehicleId != null) {
      query = query.where('vehicleId', isEqualTo: vehicleId);
    }
    if (statusFilter != 'Todas') {
      query = query.where('status', isEqualTo: statusFilter);
    }
    return query;
  }

  String _buildScopeKey(
    String uid,
    String? customerId,
    String? vehicleId,
    String statusFilter,
  ) {
    return '$uid|${customerId ?? ''}|${vehicleId ?? ''}|$statusFilter';
  }
}
