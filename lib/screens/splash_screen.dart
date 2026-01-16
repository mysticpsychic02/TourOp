import 'package:flutter/material.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'welcome_screen.dart';
import 'dashboard_screen.dart';
import 'package:driver_connect/services/shortcode_service.dart';

class SplashScreen extends StatefulWidget {
  final bool shouldStayLoggedIn;

  const SplashScreen({super.key, required this.shouldStayLoggedIn});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _navigated = false; // prevent double-push
  Timer? _safetyTimer;

  @override
  void initState() {
    super.initState();

    // Absolute safety net: never allow indefinite splash
    _safetyTimer = Timer(const Duration(seconds: 6), () {
      _navigateSafe(const WelcomeScreen());
    });

    // Keep your 2s delay, then run checks with timeout protection
    Future.delayed(const Duration(seconds: 2), _checkLoginAndNavigate);
  }

  @override
  void dispose() {
    _safetyTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkLoginAndNavigate() async {
    try {
      // 1) Read prefs quickly (local, should not hang)
      final prefs = await SharedPreferences.getInstance();
      final lastLogin = prefs.getInt('lastLogin');
      final now = DateTime.now().millisecondsSinceEpoch;
      final oneWeekMillis = 7 * 24 * 60 * 60 * 1000;

      final isLoggedIn = lastLogin != null && (now - lastLogin) < oneWeekMillis;
      if (!isLoggedIn) {
        _navigateSafe(const WelcomeScreen());
        return;
      }

      // 2) Check current user (fast)
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _navigateSafe(const WelcomeScreen());
        return;
      }

      // 3) Firestore fetch with a timeout to avoid splash hang on bad network
      final phone = (user.phoneNumber ?? '').replaceFirst('+91', '').replaceFirst('+1', '');
      final query = await FirebaseFirestore.instance
          .collection('partners')
          .where('mobileNumber', isEqualTo: phone)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 5)); // <- timeout added

      if (query.docs.isNotEmpty) {
        final data = query.docs.first.data();
        final partnerName = data['partnerName'] ?? 'Driver';
        final partnerId = query.docs.first.id;
        final mobileNumber = data['mobileNumber'] ?? '';
        final firmName = data['firmName'] ?? '';
        final address = data['address'] ?? '';

        await ShortCodeService.ensureForCurrentUser();

        
        _navigateSafe(DashboardScreen(
          partnerName: partnerName,
          partnerId: partnerId,
          mobileNumber: mobileNumber,
          firmName: firmName,
          address: address,
        ));
      } else {
        _navigateSafe(const WelcomeScreen());
      }
    } on TimeoutException {
      // Network / Firestore slow — don’t hang splash
      _navigateSafe(const WelcomeScreen());
    } catch (_) {
      // Any unexpected error: fail safe to Welcome
      _navigateSafe(const WelcomeScreen());
    }
  }

  void _navigateSafe(Widget screen) {
    if (_navigated || !mounted) return;
    _navigated = true;
    _safetyTimer?.cancel();
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.indigo.shade50,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/logo.png', height: 120),
            const SizedBox(height: 20),
            const Text(
              'TourOp',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Helping Drivers Connect Better',
              style: TextStyle(
                fontSize: 16,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(color: Colors.indigo),
          ],
        ),
      ),
    );
  }
}
