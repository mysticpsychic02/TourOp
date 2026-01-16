import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ShortCodeService {
  static const _alphabet = '2346789ABCDEFGHJKLMNPQRTUVWXYZ'; // no 0/1/I/O/S/B
  static const _length = 6;

  static String _randCode() {
    final r = Random.secure();
    return List.generate(_length, (_) => _alphabet[r.nextInt(_alphabet.length)]).join();
  }

  /// Ensures partners/{uid}.shortCode exists for the CURRENT user.
  /// This MUST be called only after sign-in.
  static Future<String> ensureForCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Not signed in');
    }
    final uid = user.uid;

    final db = FirebaseFirestore.instance;
    final partnerRef = db.collection('partners').doc(uid);

    // If already present, return it.
    final snap = await partnerRef.get();
    final existing = (snap.data()?['shortCode'] ?? '').toString();
    if (existing.isNotEmpty) return existing.toUpperCase();

    // Try multiple times to avoid rare collision races.
    for (int i = 0; i < 8; i++) {
      final code = _randCode();
      final codeDoc = db.collection('codes').doc(code);

      final codeExists = await codeDoc.get();
      if (codeExists.exists) continue; // collision, try again

      // Commit atomically
      await db.runTransaction((tx) async {
        final p = await tx.get(partnerRef);
        final current = (p.data()?['shortCode'] ?? '').toString();
        if (current.isNotEmpty) {
          // someone else set it meanwhile
          return;
        }

        // Update my own partners/{uid} (allowed by rules)
        tx.set(partnerRef, {
          'shortCode': code,
          'uid': uid, // harmless redundancy; useful for admin tooling
        }, SetOptions(merge: true));

        // Create codes/{code} with uid == owner (required by rules)
        tx.set(codeDoc, {
          'partnerDocId': uid, // partner doc id equals uid in your model
          'uid': uid,          // rules check this
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: false));
      });

      return code;
    }

    throw Exception('Failed to allocate short code after several attempts.');
  }
}
