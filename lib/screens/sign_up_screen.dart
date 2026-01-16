import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dashboard_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

// Inline country code dropdown to sit inside the phone field (no phone icon)
class _CountryCodePrefix extends StatelessWidget {
  final String value;                   // '+1' or '+91'
  final ValueChanged<String> onChanged; // callback when changed

  const _CountryCodePrefix({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        items: const <DropdownMenuItem<String>>[
          DropdownMenuItem<String>(value: '+1', child: Text('🇨🇦 +1')),
          DropdownMenuItem<String>(value: '+91', child: Text('🇮🇳 +91')),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _partnerName = TextEditingController();
  final TextEditingController _firmName = TextEditingController();
  final TextEditingController _mobileNumber = TextEditingController();
  final TextEditingController _address = TextEditingController();
  final TextEditingController _referralCode = TextEditingController();

  String _selectedCountryCode = '+1'; // default Canada; user can switch to +91

  File? _aadharFile;
  File? _licenseFile;
  bool _isLoading = false;

  // ---- OTP State ----
  String? _verificationId;
  bool _isSendingCode = false;
  bool _isVerifyingCode = false;
  int _resendToken = 0;

  // ---- small helper to tag failing operations in logs ----
  Future<T> label<T>(String name, Future<T> op) async {
    try {
      return await op;
    } on FirebaseException catch (e, st) {
      debugPrint('FIREBASE FAIL @ $name -> ${e.plugin}/${e.code} ${e.message}');
      debugPrintStack(stackTrace: st);
      rethrow;
    } catch (e, st) {
      debugPrint('GENERIC FAIL @ $name -> $e');
      debugPrintStack(stackTrace: st);
      rethrow;
    }
  }

  @override
  void dispose() {
    _partnerName.dispose();
    _firmName.dispose();
    _mobileNumber.dispose();
    _address.dispose();
    _referralCode.dispose();
    super.dispose();
  }

  Future<void> _pickFile(bool isAadhar) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        if (isAadhar) {
          _aadharFile = File(picked.path);
        } else {
          _licenseFile = File(picked.path);
        }
      });
    }
  }

  Future<String?> _uploadFile(File file, String path) async {
    final ref = FirebaseStorage.instance.ref().child(path);
    await label('STORAGE_PUT $path', ref.putFile(file));
    return await label('STORAGE_URL $path', ref.getDownloadURL());
  }

  // ===== Referral code helpers =====
  String _makeRefCode() {
    // No ambiguous chars: I, O, 0, 1 removed
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    int seed = DateTime.now().microsecondsSinceEpoch;
    String out = '';
    for (int i = 0; i < 7; i++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      out += chars[seed % chars.length];
    }
    return out;
  }

  Future<String> _getUniqueRefCode() async {
    while (true) {
      final code = _makeRefCode();
      final snap = await label(
        'PARTNERS_CHECK_REF_CODE',
        FirebaseFirestore.instance
            .collection('partners')
            .where('referralCode', isEqualTo: code)
            .limit(1)
            .get(),
      );
      if (snap.docs.isEmpty) return code;
    }
  }

  // ---- Build E.164 from form (+1/+91 + 10 digits) ----
  String _buildE164() {
    final digits = _mobileNumber.text.trim().replaceAll(RegExp(r'\D'), '');
    return '$_selectedCountryCode$digits';
  }

  // =========================
  // OTP: Start verification
  // =========================
  Future<void> _startPhoneVerification() async {
    final e164 = _buildE164();

    setState(() {
      _isSendingCode = true;
    });

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: e164,
      forceResendingToken: _resendToken == 0 ? null : _resendToken,
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Auto-retrieval on some devices
        try {
          final cred = await FirebaseAuth.instance.signInWithCredential(credential);
          final user = cred.user;
          if (user != null) {
            if (!mounted) return;
            Navigator.of(context).pop(); // close sheet if open
            await _finalizeRegistration(user);
          }
        } catch (e) {
          // fall back to manual code entry
        }
      },
      verificationFailed: (FirebaseAuthException e) async {
        if (!mounted) return;
        setState(() => _isSendingCode = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send code: ${e.message ?? e.code}')),
        );
      },
      codeSent: (String verificationId, int? forceResendingToken) async {
        if (!mounted) return;
        setState(() {
          _isSendingCode = false;
          _verificationId = verificationId;
          _resendToken = forceResendingToken ?? 0;
        });
        _showOtpSheet();
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
      timeout: const Duration(seconds: 60),
    );
  }

  // =========================
  // OTP: Show sheet to enter 6-digit code
  // =========================
  void _showOtpSheet() {
    final otpCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter the 6-digit code', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                controller: otpCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '------',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isVerifyingCode
                          ? null
                          : () async {
                              if ((_verificationId ?? '').isEmpty) return;
                              final code = otpCtrl.text.trim();
                              if (code.length != 6) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Please enter the 6-digit code')),
                                );
                                return;
                              }
                              setState(() => _isVerifyingCode = true);
                              try {
                                final credential = PhoneAuthProvider.credential(
                                  verificationId: _verificationId!,
                                  smsCode: code,
                                );
                                final cred = await FirebaseAuth.instance.signInWithCredential(credential);
                                final user = cred.user;
                                if (user != null) {
                                  if (!mounted) return;
                                  Navigator.of(context).pop(); // close the sheet
                                  await _finalizeRegistration(user);
                                }
                              } on FirebaseAuthException catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Invalid code: ${e.message ?? e.code}')),
                                );
                              } finally {
                                if (mounted) setState(() => _isVerifyingCode = false);
                              }
                            },
                      child: _isVerifyingCode ? const CircularProgressIndicator() : const Text('Verify'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _isSendingCode
                        ? null
                        : () async {
                            // resend
                            await _startPhoneVerification();
                          },
                    child: _isSendingCode ? const Text('Resending...') : const Text('Resend Code'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // =========================
  // Finalize: uploads + Firestore writes (after OTP success)
  // =========================
  Future<void> _finalizeRegistration(User user) async {
    setState(() => _isLoading = true);
    try {
      final uid = user.uid;

      // --- NEW: If this phone already has a partner doc, block sign-up path ---
      final partners = FirebaseFirestore.instance.collection('partners');
      final partnerDoc = partners.doc(uid);
      final existing = await partnerDoc.get();
      if (existing.exists) {
        // Tell user and stop. Sign out so they're not left signed-in.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('An account with this phone number already exists. Please use Sign In.')),
          );
        }
        await FirebaseAuth.instance.signOut();
        return;
      }

      // upload optional files
      String? aadharUrl;
      String? licenseUrl;
      if (_aadharFile != null) {
        aadharUrl = await _uploadFile(
          _aadharFile!, 'documents/$uid/aadhar_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
      }
      if (_licenseFile != null) {
        licenseUrl = await _uploadFile(
          _licenseFile!, 'documents/$uid/license_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
      }

      // resolve typed referrer (optional) — validated AFTER user exists
      String? referrerId;
      final typed = _referralCode.text.trim().toUpperCase();
      if (typed.isNotEmpty) {
        final q = await FirebaseFirestore.instance
            .collection('partners')
            .where('referralCode', isEqualTo: typed)
            .limit(1)
            .get();

        if (q.docs.isEmpty) {
          throw Exception("Invalid referral code.");
        }
        referrerId = q.docs.first.id;
        if (referrerId == uid) {
          throw Exception("You cannot refer yourself.");
        }
      }

      // Prepare base profile payload
      final payload = <String, dynamic>{
        'uid': uid,
        'partnerName': _partnerName.text.trim(),
        'firmName': _firmName.text.trim(),
        'mobileNumber': _mobileNumber.text.trim(),
        'countryCode': _selectedCountryCode,
        'address': _address.text.trim(),
        'aadharFileUrl': aadharUrl,
        'licenseFileUrl': licenseUrl,
        'referrerId': referrerId,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // first-time creation → generate referralCode
      final myReferralCode = await _getUniqueRefCode();
      await partnerDoc.set({
        ...payload,
        'referralCode': myReferralCode,
        'referralsCount': 0,
        'isAdmin': false,
        'disabled': false,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // ensure rewards/{uid} exists (no-op increment)
      final rewardsRef = FirebaseFirestore.instance.collection('rewards').doc(uid);
      await rewardsRef.set({
        'points': FieldValue.increment(0),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // ---------- NEW: Atomic Sign-Up Bonus (+100) with ledger ----------
      // Only if not yet granted (guarded by partners/{uid}.signupBonusGranted)
      final rewardsLogs = FirebaseFirestore.instance.collection('rewards_logs');

      await FirebaseFirestore.instance.runTransaction((txn) async {
        final pSnap = await txn.get(partnerDoc);
        if (pSnap.exists && (pSnap.data()?['signupBonusGranted'] == true)) {
          return; // already granted, skip
        }

        final rSnap = await txn.get(rewardsRef);
        final currentPoints = (rSnap.exists && rSnap.data() != null && rSnap.data()!['points'] is num)
            ? (rSnap.data()!['points'] as num).toInt()
            : 0;
        final newPoints = currentPoints + 100;

        // Update total points
        txn.set(
          rewardsRef,
          {
            'points': newPoints,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        // Write history row
        final logRef = rewardsLogs.doc();
        txn.set(logRef, {
          'partnerId': uid,
          'delta': 100,
          'reason': 'Sign-Up Bonus',
          'by': 'system',
          'before': currentPoints,
          'after': newPoints,
          'at': FieldValue.serverTimestamp(),
        });

        // Mark idempotency on partner
        txn.set(
          partnerDoc,
          {
            'signupBonusGranted': true,
            'signupBonusGrantedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });
      // ---------- END NEW ----------

      // referral bonuses with 5-cap (only apply if referrer provided & under cap)
      if (referrerId != null) {
        await FirebaseFirestore.instance.runTransaction((txn) async {
          final referrerPartnerRef = partners.doc(referrerId!);
          final referrerSnap = await txn.get(referrerPartnerRef);
          int currentCount = 0;
          if (referrerSnap.exists) {
            final data = referrerSnap.data() as Map<String, dynamic>;
            currentCount = (data['referralsCount'] ?? 0) as int;
          }
          if (currentCount < 5) {
            final rewards = FirebaseFirestore.instance.collection('rewards');
            txn.set(
              rewards.doc(referrerId),
              {'points': FieldValue.increment(10), 'updatedAt': FieldValue.serverTimestamp()},
              SetOptions(merge: true),
            );
            txn.set(
              rewards.doc(uid),
              {'points': FieldValue.increment(10), 'updatedAt': FieldValue.serverTimestamp()},
              SetOptions(merge: true),
            );
            txn.set(
              referrerPartnerRef,
              {'referralsCount': FieldValue.increment(1)},
              SetOptions(merge: true),
            );

            // Optional: write logs for referral bonus (kept consistent with your schema)
            final logs = FirebaseFirestore.instance.collection('rewards_logs');
            final nowTs = FieldValue.serverTimestamp();
            txn.set(logs.doc(), {
              'partnerId': referrerId,
              'delta': 10,
              'reason': 'Referral Bonus',
              'by': 'system',
              'before': null,
              'after': null,
              'at': nowTs,
            });
            txn.set(logs.doc(), {
              'partnerId': uid,
              'delta': 10,
              'reason': 'Referral Bonus',
              'by': 'system',
              'before': null,
              'after': null,
              'at': nowTs,
            });
          }
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Welcome ${_partnerName.text.trim()}!')),
      );

      // go to Dashboard using the REAL uid
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => DashboardScreen(
            partnerName: _partnerName.text.trim(),
            partnerId: uid,
            mobileNumber: _mobileNumber.text.trim(),
            firmName: _firmName.text.trim(),
            address: _address.text.trim(),
          ),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // =========================
  // Original onPress entry point
  // =========================
  Future<void> _onRegisterPressed() async {
    if (!_formKey.currentState!.validate()) return;

    // light sanity for phone digits
    final digits = _mobileNumber.text.trim().replaceAll(RegExp(r'\D'), '');
    if (digits.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid 10-digit number')),
      );
      return;
    }

    // NOTE: We don't pre-check Firestore anymore (blocked by rules).
    // We verify phone first, then decide based on partners/{uid} existence.
    await _startPhoneVerification();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register with TourOp')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const Text(
                'Create Your Partner Account',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),

              _buildTextField(_partnerName, 'Name of Partner', Icons.person,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
              const SizedBox(height: 10),

              _buildTextField(_firmName, 'Name of Firm', Icons.business),
              const SizedBox(height: 10),

              // Phone with inline country-code dropdown INSIDE the field (no phone icon)
              TextFormField(
                controller: _mobileNumber,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Mobile Number',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: _CountryCodePrefix(
                      value: _selectedCountryCode,
                      onChanged: (v) => setState(() => _selectedCountryCode = v),
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Required';
                  final digits = value.replaceAll(RegExp(r'\D'), '');
                  if (digits.length != 10) return 'Enter valid 10-digit number';
                  return null;
                },
              ),

              const SizedBox(height: 10),

              _buildTextField(_address, 'Address', Icons.home),
              const SizedBox(height: 10),

              _buildTextField(_referralCode, 'Referral Code', Icons.card_giftcard),
              const SizedBox(height: 20),

              _buildUploadButton(isAadhar: true, file: _aadharFile, label: 'Upload Aadhar'),
              const SizedBox(height: 10),
              _buildUploadButton(isAadhar: false, file: _licenseFile, label: 'Upload License'),
              const SizedBox(height: 30),

              _isLoading || _isSendingCode
                  ? const CircularProgressIndicator()
                  : SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.check_circle),
                        label: const Text('Register'),
                        onPressed: _onRegisterPressed,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType? keyboardType,
    Widget? prefix,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType ?? TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        prefix: prefix, // not used for phone since we use the dropdown prefix above
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      validator: validator,
    );
  }

  Widget _buildUploadButton({
    required bool isAadhar,
    required File? file,
    required String label,
  }) {
    return ElevatedButton.icon(
      icon: Icon(file != null ? Icons.check : Icons.upload),
      label: Text(file != null ? 'Selected' : label),
      onPressed: () => _pickFile(isAadhar),
      style: ElevatedButton.styleFrom(
        backgroundColor: file != null ? Colors.green : Colors.indigo,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 48),
      ),
    );
  }
}
