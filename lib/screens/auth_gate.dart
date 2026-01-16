import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


import 'dashboard_screen.dart';
import 'welcome_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        // 1) Still figuring out auth state
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        // 2) Not signed in -> Welcome / Login
        final user = snap.data;
        if (user == null) {
          return const WelcomeScreen();
        }

        // 3) Signed in -> ensure partners/{uid} exists and load it
        final uid = user.uid;
        final partnersRef =
            FirebaseFirestore.instance.collection('partners').doc(uid);

        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: _ensureAndLoadPartnerDoc(partnersRef, user),
          builder: (context, partnerSnap) {
            if (partnerSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            Map<String, dynamic> data = {};
            if (partnerSnap.hasData && partnerSnap.data!.data() != null) {
              data = partnerSnap.data!.data()!;
            }


            return DashboardScreen(
              partnerName:
                  (data['partnerName'] ?? user.displayName ?? '').toString(),
              partnerId: uid,
              mobileNumber: (data['mobileNumber'] ?? '').toString(),
              firmName: (data['firmName'] ?? '').toString(),
              address: (data['address'] ?? '').toString(),
            );
          },
        );
      },
    );
  }

  /// Ensure partners/{uid} exists (allowed by your rules), then return the doc.
  Future<DocumentSnapshot<Map<String, dynamic>>> _ensureAndLoadPartnerDoc(
    DocumentReference<Map<String, dynamic>> partnersRef,
    User user,
  ) async {
    try {
      final snap = await partnersRef.get();
      if (!snap.exists) {
        final e164 = user.phoneNumber ?? '';
        final last10 = e164.replaceAll(RegExp(r'[^0-9]'), '')
            .replaceFirst(RegExp(r'^.*(?=.{10}$)'), '');

        await partnersRef.set({
          'uid': user.uid,
          'phoneE164': e164,
          'mobileNumber': last10,
          'partnerName': user.displayName ?? '',
          'firmName': '',
          'address': '',
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      return await partnersRef.get();
    } catch (e) {
      try {
        return await partnersRef.get();
      } catch (_) {
        rethrow;
      }
    }
  }
}
