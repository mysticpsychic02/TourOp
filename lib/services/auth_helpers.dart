import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

Future<bool> isCurrentUserAdmin() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return false;
  final uid = user.uid;

  try {
    final doc = await FirebaseFirestore.instance
        .collection('admins')
        .doc(uid)
        .get();
    return doc.exists;
  } catch (_) {
    // Treat any permission-denied as "not admin"
    return false;
  }
}
