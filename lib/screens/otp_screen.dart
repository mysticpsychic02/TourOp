import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'dashboard_screen.dart';

class OTPScreen extends StatefulWidget {
  final String phoneNumber;   // E.164: +1XXXXXXXXXX / +91XXXXXXXXXX
  final String verificationId;
  final int? resendToken;
  final String countryCode;   // '+1' or '+91'

  const OTPScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
    this.resendToken,
    required this.countryCode,
  });

  @override
  State<OTPScreen> createState() => _OTPScreenState();
}

class _OTPScreenState extends State<OTPScreen> {
  final TextEditingController _otpController = TextEditingController();
  bool _isLoading = false;
  late String _verificationId;
  int? _resendToken;

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
    _resendToken = widget.resendToken;
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  /// Save FCM token to partners/{uid}
  Future<void> _setupPushForPartnerDoc(String uid) async {
    try {
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();

      if (token != null) {
        await FirebaseFirestore.instance
            .collection('partners')
            .doc(uid)
            .set({
          'fcmTokens': FieldValue.arrayUnion([token]),
          'lastLoginAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
          try {
            await FirebaseFirestore.instance
                .collection('partners')
                .doc(uid)
                .set({
              'fcmTokens': FieldValue.arrayUnion([newToken]),
              'lastLoginAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          } catch (e) {
            debugPrint('[PUSH][onTokenRefresh] $e');
          }
        });
      }
    } catch (e) {
      // Non-blocking
      debugPrint('[PUSH][setup] $e');
    }
  }

Future<void> _verifyOTP() async {
  final code = _otpController.text.trim();
  if (code.length != 6) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the 6-digit OTP')),
      );
    }
    return;
  }

  setState(() => _isLoading = true);
  String step = 'AUTH_SIGNIN';

  try {
    // 1) Sign in with OTP
    final credential = PhoneAuthProvider.credential(
      verificationId: _verificationId,
      smsCode: code,
    );
    await FirebaseAuth.instance.signInWithCredential(credential);

    // 2) Get uid
    step = 'AUTH_UID';
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseAuthException(code: 'no-user', message: 'No user after sign-in');
    }
    final uid = user.uid;

    // 3) Non-blocking: try to upsert partners/{uid}
    step = 'PARTNER_UPSERT';
    try {
      final e164 = widget.phoneNumber.trim();
      final digits = _digitsOnly(e164);
      final last10 = digits.length >= 10 ? digits.substring(digits.length - 10) : digits;

      await FirebaseFirestore.instance.collection('partners').doc(uid).set({
        'uid': uid,
        'phoneE164': e164,
        'mobileNumber': last10,
        'partnerName': user.displayName ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      // Don’t block login
      debugPrint('[$step] $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('[$step] continuing…')),
        );
      }
    }

    // 4) Non-blocking: local prefs
    step = 'LOCAL_PREFS';
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('lastLogin', DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('[$step] $e');
    }

    // 5) Non-blocking: FCM token save to partners/{uid}
    step = 'PUSH_SAVE';
    try {
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await FirebaseFirestore.instance.collection('partners').doc(uid).set({
          'fcmTokens': FieldValue.arrayUnion([token]),
          'lastLoginAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('[$step] $e');
    }

    // 6) Navigate regardless of the above Firestore attempts
    if (!mounted) return;

    // We’ll pass placeholders; your Dashboard can re-read partners/{uid} later.
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => DashboardScreen(
          partnerName: FirebaseAuth.instance.currentUser?.displayName ?? '',
          partnerId: uid,
          mobileNumber: '',
          firmName: '',
          address: '',
        ),
      ),
      (route) => false,
    );
  } on FirebaseAuthException catch (e) {
    if (!mounted) return;
    if (e.code == 'session-expired') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OTP session expired. Resending a new code...')),
      );
      await _resendOTP(autoFromSessionExpired: true);
    } else if (e.code == 'invalid-verification-code') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid OTP. Please try again.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('[$step] ${e.message ?? e.code}')),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('[$step] ${e.toString()}')),
      );
    }
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}


  Future<void> _resendOTP({bool autoFromSessionExpired = false}) async {
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: widget.phoneNumber,
        timeout: const Duration(seconds: 60),
        forceResendingToken: _resendToken,
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Optional auto sign-in
        },
        verificationFailed: (FirebaseAuthException e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Resend failed: ${e.message}')),
            );
          }
        },
        codeSent: (String newVerificationId, int? newResendToken) {
          if (mounted) {
            if (!autoFromSessionExpired) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('OTP resent successfully')),
              );
            }
            setState(() {
              _verificationId = newVerificationId;
              _resendToken = newResendToken;
            });
          }
        },
        codeAutoRetrievalTimeout: (String newVerificationId) {
          setState(() {
            _verificationId = newVerificationId;
          });
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  String getMaskedPhone() {
    final digits = _digitsOnly(widget.phoneNumber);
    final last10 = digits.length >= 10 ? digits.substring(digits.length - 10) : digits;
    if (last10.length != 10) return widget.phoneNumber;
    return '${widget.countryCode} ${last10.substring(0, 3)} XXXXX${last10.substring(5)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.indigo.shade50,
      appBar: AppBar(title: const Text('OTP Verification')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/logo.png', height: 90),
              const SizedBox(height: 16),
              const Text(
                'Verify Your Phone',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.indigo),
              ),
              const SizedBox(height: 8),
              Text('OTP sent to ${getMaskedPhone()}', style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 32),
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: 'Enter OTP',
                  prefixIcon: const Icon(Icons.lock),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: _isLoading
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(_isLoading ? 'Verifying...' : 'Verify'),
                  onPressed: _isLoading ? null : _verifyOTP,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _isLoading ? null : () => _resendOTP(),
                child: const Text('Didn’t receive OTP? Resend'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
