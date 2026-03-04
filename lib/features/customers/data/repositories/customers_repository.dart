import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/customer_model.dart';

class CustomersRepository {
  final FirebaseFirestore _firestore;

  CustomersRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<CustomerModel> _customersCol(String uid) {
    return CustomerModel.collectionForUser(_firestore, uid);
  }

  Stream<QuerySnapshot<CustomerModel>> watchCustomersSnapshot(String uid) {
    return _customersCol(uid).orderBy('name').snapshots();
  }

  Stream<DocumentSnapshot<CustomerModel>> watchCustomerById(
    String uid,
    String customerId,
  ) {
    return _customersCol(uid).doc(customerId).snapshots();
  }

  Future<void> deleteCustomer(String uid, String customerId) {
    return _customersCol(uid).doc(customerId).delete();
  }
}
