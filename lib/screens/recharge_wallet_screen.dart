import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

class RechargeWalletScreen extends StatefulWidget {
  const RechargeWalletScreen({super.key});

  @override
  State<RechargeWalletScreen> createState() => _RechargeWalletScreenState();
}

class _RechargeWalletScreenState extends State<RechargeWalletScreen> {
  double? selectedAmount;
  bool _loading = false;

  final TextEditingController _utrController = TextEditingController();

  String? _status; // null | pending | approved | rejected

  final String upiId = '9815820541@ybl';
  final String payeeName = 'Pankaj Gulati';

  // 🔹 Validate 12-digit numeric UTR
  bool _isValidUTR(String value) {
    final regex = RegExp(r'^\d{12}$');
    return regex.hasMatch(value);
  }

  // 🔹 Get wallet balance
  Future<double> _getBalance() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc =
        await FirebaseFirestore.instance.collection('wallets').doc(uid).get();
    return (doc.data()?['balance'] ?? 0).toDouble();
  }

  // 🔹 Open UPI app
  Future<void> _payViaUPI() async {
    if (selectedAmount == null) return;

    final upiUrl =
        'upi://pay?pa=$upiId&pn=${Uri.encodeComponent(payeeName)}'
        '&am=${selectedAmount!.toInt()}&cu=INR&tn=Wallet Recharge';

    final uri = Uri.parse(upiUrl);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No UPI app found')),
      );
    }
  }

  // 🔹 Manual UPI fallback
  void _showManualUPIDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Manual UPI Payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('UPI ID'),
            SelectableText(
              upiId,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text('Name'),
            SelectableText(
              payeeName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Open your UPI app and send money using the above details.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // 🔹 Submit recharge request
  Future<void> _submitRechargeRequest() async {
    final utr = _utrController.text.trim();
    if (!_isValidUTR(utr)) return;
    if (selectedAmount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an amount')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      // ✅ IMPORTANT FIX:
      // Use doc().set() (explicit set) instead of add()
      // because serverTimestamp is guaranteed to be valid with set()/update().
      final docRef =
          FirebaseFirestore.instance.collection('wallet_requests').doc();

      await docRef.set({
        'uid': uid,
        'amount': selectedAmount!.toInt(), // store as int
        'utr': utr,
        'screenshotUrl': null,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        _status = 'pending';
        _utrController.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recharge request submitted')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: const Text('Recharge Wallet')),
      body: FutureBuilder<double>(
        future: _getBalance(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final balance = snapshot.data!;

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 🔹 Balance
                    Card(
                      child: ListTile(
                        leading:
                            const Icon(Icons.account_balance_wallet_outlined),
                        title: const Text('Current Balance'),
                        subtitle: Text('₹${balance.toStringAsFixed(2)}'),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // 🔹 Amount selection
                    const Text(
                      'Select amount',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),

                    Wrap(
                      spacing: 12,
                      children: [100, 200, 500, 1000].map((amt) {
                        return ChoiceChip(
                          label: Text('₹$amt'),
                          selected: selectedAmount == amt.toDouble(),
                          onSelected: (_) {
                            setState(() => selectedAmount = amt.toDouble());
                          },
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 24),

                    // 🔹 Pay via UPI
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: selectedAmount == null ? null : _payViaUPI,
                        child: const Text('Pay via UPI'),
                      ),
                    ),

                    const SizedBox(height: 8),

                    Center(
                      child: GestureDetector(
                        onTap: _showManualUPIDialog,
                        child: const Text(
                          'Having trouble?',
                          style: TextStyle(
                            fontSize: 13,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // 🔹 After payment
                    const Text(
                      'After payment',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),

                    TextField(
                      controller: _utrController,
                      keyboardType: TextInputType.number,
                      maxLength: 12,
                      decoration: const InputDecoration(
                        labelText: 'Reference ID (UTR)',
                        hintText: '12-digit UTR',
                        counterText: '',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),

                    const SizedBox(height: 12),

                    // 🔹 Screenshot placeholder
                    OutlinedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content:
                                Text('Screenshot upload will be added later'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.image),
                      label: const Text(
                        'Upload transaction screenshot (optional)',
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 🔹 Submit button (12-digit UTR only)
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _loading ||
                                !_isValidUTR(_utrController.text.trim())
                            ? null
                            : _submitRechargeRequest,
                        child: _loading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('Submit Reference ID'),
                      ),
                    ),

                    // 🔹 Status
                    if (_status != null) ...[
                      const SizedBox(height: 16),
                      Card(
                        color: Colors.orange.shade50,
                        child: const ListTile(
                          leading: Icon(
                            Icons.hourglass_bottom,
                            color: Colors.orange,
                          ),
                          title: Text('Status'),
                          subtitle: Text('Pending verification'),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
