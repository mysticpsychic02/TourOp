import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class ProfilePage extends StatelessWidget {
  final String partnerName;
  final String firmName;
  final String mobileNumber;
  final String address;
  final String partnerId; // Firestore doc id for partners/{partnerId}

  const ProfilePage({
    Key? key,
    required this.partnerName,
    required this.firmName,
    required this.mobileNumber,
    required this.address,
    required this.partnerId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final docRef =
        FirebaseFirestore.instance.collection('partners').doc(partnerId);

    return Scaffold(
      appBar: AppBar(title: const Text('Your Profile')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docRef.snapshots(),
        builder: (context, snap) {
          final data = snap.data?.data();

          // Fallbacks to the values passed in, overridden by Firestore if present
          final name = (data?['partnerName'] ?? partnerName).toString();
          final firm = (data?['firmName'] ?? firmName).toString();
          final addr = (data?['address'] ?? address).toString();
          final phone = (data?['mobileNumber'] ?? mobileNumber).toString();
          final ccode = (data?['countryCode'] ?? '+91')
              .toString(); // keep your original +91 display default

          // ✅ Document fields (expected in partners/{uid})
          final aadharUrl = (data?['aadharUrl'] ?? '').toString();
          final licenseUrl = (data?['licenseUrl'] ?? '').toString();

          // ✅ Verification flags (optional)
          final aadharVerified = data?['aadharVerified'] as bool?;
          final licenseVerified = data?['licenseVerified'] as bool?;

          // ✅ Completeness check
          final missing = <String>[];
          if (name.trim().isEmpty) missing.add('Name');
          if (firm.trim().isEmpty) missing.add('Firm');
          if (phone.trim().isEmpty) missing.add('Mobile');
          if (addr.trim().isEmpty) missing.add('Address');
          if (aadharUrl.trim().isEmpty) missing.add('Aadhar');
          if (licenseUrl.trim().isEmpty) missing.add('License');

          final isComplete = missing.isEmpty;

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: ListView(
              children: [
                profileItem('👤 Name', name),
                profileItem('🏢 Firm', firm),
                profileItem('📞 Mobile', '$ccode $phone'),
                profileItem('🏠 Address', addr),

                // ✅ NEW: Documents verification card (Aadhar + License)
                _documentsCard(
                  aadharUrl: aadharUrl,
                  licenseUrl: licenseUrl,
                  aadharVerified: aadharVerified,
                  licenseVerified: licenseVerified,
                ),

                // ✅ NEW: Complete profile CTA if missing anything
                if (!isComplete) ...[
                  const SizedBox(height: 8),
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '⚠️ Profile Incomplete',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Missing: ${missing.join(', ')}',
                            style: const TextStyle(fontSize: 13),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: ElevatedButton(
                              onPressed: () {
                                _openCompleteProfileSheet(
                                  context,
                                  docRef: docRef,
                                  currentName: name,
                                  currentFirm: firm,
                                  currentPhone: phone,
                                  currentAddress: addr,
                                  aadharUrl: aadharUrl,
                                  licenseUrl: licenseUrl,
                                );
                              },
                              child: const Text('Complete your profile'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // 🔹 Partner ID card now shows the SHORT code from Firestore (kept as-is)
                _partnerIdCard(),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Simple helper for static rows (kept as-is)
  Widget profileItem(String title, String value) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(value),
      ),
    );
  }

  /// ✅ NEW: Documents card (Aadhar + License)
  Widget _documentsCard({
    required String aadharUrl,
    required String licenseUrl,
    required bool? aadharVerified,
    required bool? licenseVerified,
  }) {
    String statusText(String url, bool? verified) {
      if (url.trim().isEmpty) return 'Not uploaded';
      if (verified == true) return 'Verified';
      return 'Not verified';
    }

    Color statusColor(String url, bool? verified) {
      if (url.trim().isEmpty) return Colors.red;
      if (verified == true) return Colors.green;
      return Colors.orange;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            const ListTile(
              title: Text(
                '📄 Documents',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text('Aadhar & Driving License status'),
            ),
            const Divider(height: 1),
            ListTile(
              title: const Text('Aadhar'),
              trailing: Text(
                statusText(aadharUrl, aadharVerified),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: statusColor(aadharUrl, aadharVerified),
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              title: const Text('Driving License'),
              trailing: Text(
                statusText(licenseUrl, licenseVerified),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: statusColor(licenseUrl, licenseVerified),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Partner ID card that fetches `shortCode` from partners/{partnerId} (kept as-is)
  Widget _partnerIdCard() {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('partners').doc(partnerId).get(),
      builder: (context, snap) {
        String displayCode = '—';

        if (snap.hasData && snap.data!.exists) {
          final data = snap.data!.data() as Map<String, dynamic>?;
          final shortCode = (data?['shortCode'] ?? '').toString();
          if (shortCode.isNotEmpty) {
            displayCode = shortCode.toUpperCase();
          } else {
            // Fallback: last 6 chars of the existing partnerId (doc id)
            displayCode = partnerId.length >= 6
                ? partnerId.substring(partnerId.length - 6).toUpperCase()
                : partnerId.toUpperCase();
          }
        } else {
          // If the doc isn't loaded yet, still show a friendly fallback
          displayCode = partnerId.length >= 6
              ? partnerId.substring(partnerId.length - 6).toUpperCase()
              : partnerId.toUpperCase();
        }

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ListTile(
            title: const Text(
              '🆔 Partner ID',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(displayCode),
          ),
        );
      },
    );
  }

  /// ✅ NEW: Bottom sheet to complete/edit missing parts
  static void _openCompleteProfileSheet(
    BuildContext context, {
    required DocumentReference<Map<String, dynamic>> docRef,
    required String currentName,
    required String currentFirm,
    required String currentPhone,
    required String currentAddress,
    required String aadharUrl,
    required String licenseUrl,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CompleteProfileSheet(
        docRef: docRef,
        currentName: currentName,
        currentFirm: currentFirm,
        currentPhone: currentPhone,
        currentAddress: currentAddress,
        aadharUrl: aadharUrl,
        licenseUrl: licenseUrl,
      ),
    );
  }
}

class _CompleteProfileSheet extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> docRef;
  final String currentName;
  final String currentFirm;
  final String currentPhone;
  final String currentAddress;
  final String aadharUrl;
  final String licenseUrl;

  const _CompleteProfileSheet({
    required this.docRef,
    required this.currentName,
    required this.currentFirm,
    required this.currentPhone,
    required this.currentAddress,
    required this.aadharUrl,
    required this.licenseUrl,
  });

  @override
  State<_CompleteProfileSheet> createState() => _CompleteProfileSheetState();
}

class _CompleteProfileSheetState extends State<_CompleteProfileSheet> {
  late final TextEditingController _nameC;
  late final TextEditingController _firmC;
  late final TextEditingController _phoneC;
  late final TextEditingController _addrC;

  bool _saving = false;

  String? _aadharUrl;
  String? _licenseUrl;

  @override
  void initState() {
    super.initState();
    _nameC = TextEditingController(text: widget.currentName);
    _firmC = TextEditingController(text: widget.currentFirm);
    _phoneC = TextEditingController(text: widget.currentPhone);
    _addrC = TextEditingController(text: widget.currentAddress);

    _aadharUrl = widget.aadharUrl;
    _licenseUrl = widget.licenseUrl;
  }

  @override
  void dispose() {
    _nameC.dispose();
    _firmC.dispose();
    _phoneC.dispose();
    _addrC.dispose();
    super.dispose();
  }

  bool _isEmpty(String? s) => (s ?? '').trim().isEmpty;

  Future<void> _pickAndUpload(String field) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (picked == null) return;

    setState(() => _saving = true);

    try {
      final file = File(picked.path);

      final storagePath =
          'partners/${widget.docRef.id}/documents/${field}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final ref = FirebaseStorage.instance.ref().child(storagePath);
      final task = await ref.putFile(file);
      final url = await task.ref.getDownloadURL();

      await widget.docRef.set({
        if (field == 'aadhar') 'aadharUrl': url,
        if (field == 'license') 'licenseUrl': url,

        // Optional: on re-upload mark as not verified
        if (field == 'aadhar') 'aadharVerified': false,
        if (field == 'license') 'licenseVerified': false,

        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      setState(() {
        if (field == 'aadhar') _aadharUrl = url;
        if (field == 'license') _licenseUrl = url;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${field == 'aadhar' ? 'Aadhar' : 'License'} uploaded')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveTextFields() async {
    setState(() => _saving = true);
    try {
      await widget.docRef.set({
        'partnerName': _nameC.text.trim(),
        'firmName': _firmC.text.trim(),
        'mobileNumber': _phoneC.text.trim(),
        'address': _addrC.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final missingName = _isEmpty(_nameC.text);
    final missingFirm = _isEmpty(_firmC.text);
    final missingPhone = _isEmpty(_phoneC.text);
    final missingAddr = _isEmpty(_addrC.text);
    final missingAadhar = _isEmpty(_aadharUrl);
    final missingLicense = _isEmpty(_licenseUrl);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 10,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Complete your profile',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'Fill only what is missing. You can also edit existing fields.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 14),

              if (missingName)
                _field(
                  controller: _nameC,
                  label: 'Name',
                  icon: Icons.person,
                )
              else
                _field(
                  controller: _nameC,
                  label: 'Name',
                  icon: Icons.person,
                ),

              const SizedBox(height: 12),

              _field(
                controller: _firmC,
                label: 'Firm Name',
                icon: Icons.business,
              ),

              const SizedBox(height: 12),

              _field(
                controller: _phoneC,
                label: 'Mobile Number',
                icon: Icons.phone,
                keyboardType: TextInputType.phone,
              ),

              const SizedBox(height: 12),

              _field(
                controller: _addrC,
                label: 'Address',
                icon: Icons.home,
                maxLines: 2,
              ),

              const SizedBox(height: 16),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Documents',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),

                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _saving ? null : () => _pickAndUpload('aadhar'),
                              icon: const Icon(Icons.badge),
                              label: Text(missingAadhar ? 'Upload Aadhar' : 'Replace Aadhar'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _saving ? null : () => _pickAndUpload('license'),
                              icon: const Icon(Icons.credit_card),
                              label: Text(missingLicense ? 'Upload License' : 'Replace License'),
                            ),
                          ),
                        ],
                      ),

                      if (missingAadhar || missingLicense) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Missing: ${[
                            if (missingAadhar) 'Aadhar',
                            if (missingLicense) 'License',
                          ].join(', ')}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _saving ? null : _saveTextFields,
                  child: _saving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Save'),
                ),
              ),

              const SizedBox(height: 10),

              // tiny hint (doesn't change your UI logic, just helpful)
              if (missingName || missingFirm || missingPhone || missingAddr || missingAadhar || missingLicense)
                const Text(
                  'Tip: Complete all fields + upload both documents to remove the “Complete your profile” button.',
                  style: TextStyle(fontSize: 11),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => setState(() {}),
    );
  }
}
