import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SendMoneyScreen extends StatefulWidget {
  const SendMoneyScreen({super.key});

  @override
  State<SendMoneyScreen> createState() => _SendMoneyScreenState();
}

class _SendMoneyScreenState extends State<SendMoneyScreen> {
  String? selectedDriverId;
  final TextEditingController _amountController = TextEditingController();
  bool _loading = false;

  Future<void> sendMoney() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final amount = double.tryParse(_amountController.text.trim());
    if (selectedDriverId == null || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid details')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final token = await user.getIdToken();

      final url = Uri.parse(
        'https://asia-south2-tourop-6d58a.cloudfunctions.net/sendMoneyHttp',
      );

      final res = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'toUid': selectedDriverId,
          'amount': amount,
        }),
      );

      if (res.statusCode != 200) {
        throw Exception(res.body);
      }

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Money sent successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Send Money')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('partners')
                  .orderBy('partnerName')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const CircularProgressIndicator();
                }

                final drivers = snapshot.data!.docs
                    .where((d) => d.id != currentUserId)
                    .toList();

                return DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Select Driver',
                    border: OutlineInputBorder(),
                  ),
                  items: drivers.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return DropdownMenuItem<String>(
                      value: doc.id,
                      child: Text(data['partnerName'] ?? 'Driver'),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => selectedDriverId = v),
                );
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount (₹)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _loading ? null : sendMoney,
                child: _loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Send Money'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
