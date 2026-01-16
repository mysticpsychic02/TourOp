import 'package:cloud_firestore/cloud_firestore.dart';

class RoutesRepository {
  final _routes = FirebaseFirestore.instance.collection('routes');

  // Use the same field you write: 'timestamp'
  Stream<QuerySnapshot<Map<String, dynamic>>> streamAllRoutes() {
    return _routes.orderBy('timestamp', descending: true).snapshots();
  }

  Future<void> deleteRoute(String routeId) async {
    await _routes.doc(routeId).delete();
  }

  // Optional helper to enforce partnerId and timestamp on create
  Future<String> createRoute({
    required String partnerId,
    required Map<String, dynamic> data,
  }) async {
    final doc = await _routes.add({
      ...data,
      'partnerId': partnerId,                         // REQUIRED by rules
      'timestamp': FieldValue.serverTimestamp(),      // for ordering
    });
    return doc.id;
  }
}
