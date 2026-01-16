import 'package:flutter/material.dart';
import 'profile_page.dart';
import 'package:driver_connect/screens/welcome_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:driver_connect/screens/send_money_screen.dart';
import 'package:share_plus/share_plus.dart';
import 'package:driver_connect/screens/recharge_wallet_screen.dart';
import 'package:driver_connect/screens/support_screen.dart';
import 'package:driver_connect/screens/admin_tab.dart';
import 'package:flutter/services.dart'; // Clipboard

class AccountTab extends StatefulWidget {
  final String partnerName;
  final String partnerId;
  final String mobileNumber;
  final String firmName;
  final String address;

  const AccountTab({
    super.key,
    required this.partnerName,
    required this.partnerId,
    required this.mobileNumber,
    required this.firmName,
    required this.address,
  });

  @override
  State<AccountTab> createState() => _AccountTabState();
}

class _AccountTabState extends State<AccountTab> {
  String? _referralCode;
  bool _refLoading = true;

  String _makeRefCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no I/O/1/0
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
      final snap = await FirebaseFirestore.instance
          .collection('partners')
          .where('referralCode', isEqualTo: code)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return code;
    }
  }

  Future<void> _ensureReferralCodeExists() async {
    final ref =
        FirebaseFirestore.instance.collection('partners').doc(widget.partnerId);
    final snap = await ref.get();
    final data = snap.data() as Map<String, dynamic>?;
    String? code = data?['referralCode']?.toString();

    if (code == null || code.isEmpty) {
      code = await _getUniqueRefCode();
      await ref.set({'referralCode': code}, SetOptions(merge: true));
    }
    setState(() {
      _referralCode = code;
      _refLoading = false;
    });
  }

  String? _selectedSection;
  bool _isAdmin = false;
  bool _loading = true;
  String _countryCode = '+91';

  @override
  void initState() {
    super.initState();
    _loadAdminFlag();
    _ensureReferralCodeExists();
  }

  Future<void> _loadAdminFlag() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('partners')
          .doc(widget.partnerId)
          .get();
      final data = snap.data() as Map<String, dynamic>?;

      setState(() {
        _isAdmin = (data?['isAdmin'] == true);
        final cc = (data?['countryCode'] as String?)?.trim();
        if (cc != null && cc.isNotEmpty) _countryCode = cc;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _isAdmin = false;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.person),
          title: const Text('Profile'),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProfilePage(
                  partnerName: widget.partnerName,
                  firmName: widget.firmName,
                  mobileNumber: widget.mobileNumber,
                  address: widget.address,
                  partnerId: widget.partnerId,
                ),
              ),
            );
          },
        ),

        // Admin Console entry — only if admin
        if (_isAdmin)
          ListTile(
            leading: const Icon(Icons.admin_panel_settings),
            title: const Text('Admin Console'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminTab()),
              );
            },
          ),

        ListTile(
          title: const Text('Reward Points'),
          leading: const Icon(Icons.stars),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () => setState(() => _selectedSection = 'Rewards'),
        ),
        ListTile(
          title: const Text('Wallet'),
          leading: const Icon(Icons.account_balance_wallet),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () => setState(() => _selectedSection = 'Wallet'),
        ),
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.red),
          title: const Text('Sign Out'),
          onTap: () async {
            await FirebaseAuth.instance.signOut();
            if (context.mounted) {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                (route) => false,
              );
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.share),
          title: const Text('Refer Your Friend'),
          onTap: () async {
            final pSnap = await FirebaseFirestore.instance
                .collection('partners')
                .doc(widget.partnerId)
                .get();
            final code = (pSnap.data()?['referralCode'] ?? '').toString();
            final link = 'https://tourop.page.link/?ref=$code';
            Share.share(
              code.isEmpty
                  ? 'Join TourOp!'
                  : 'Join TourOp using my referral: $code\n$link',
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.help_outline),
          title: const Text('Support / Help'),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SupportScreen()),
            );
          },
        ),

        const Divider(height: 1),
        Expanded(
          child: _buildSectionContent(),
        ),
      ],
    );
  }

  Widget _buildSectionContent() {
    switch (_selectedSection) {
      case 'Profile':
        return _buildProfileSection();
      case 'Rewards':
        return _buildRewardsSection();
      case 'Wallet':
        return _buildWalletSection();
      default:
        return const Center(child: Text('Select a section above'));
    }
  }

  Widget _buildProfileSection() {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('partners')
          .doc(widget.partnerId)
          .get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snap.data?.data() as Map<String, dynamic>?;

        final countryCode = (data?['countryCode'] ?? _countryCode).toString();
        final referralCode =
            (data?['referralCode'] ?? _referralCode ?? '').toString();

        final shortCodeRaw = (data?['shortCode'] ?? '').toString();
        String userCode;
        if (shortCodeRaw.isNotEmpty) {
          userCode = shortCodeRaw.toUpperCase();
        } else {
          final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
          userCode =
              uid.isEmpty ? '—' : uid.substring(uid.length - 6).toUpperCase();
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Your Profile',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            _buildInfoCard('Partner Name', widget.partnerName, Icons.badge),
            _buildInfoCard('Firm Name', widget.firmName, Icons.business),
            _buildInfoCard('Mobile Number',
                '$countryCode ${widget.mobileNumber}', Icons.phone),
            _buildInfoCard('Address', widget.address, Icons.home),

            Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: ListTile(
                leading: const Icon(Icons.verified_user),
                title: const Text('Your User Code'),
                subtitle: Text(
                  userCode,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 16),
                ),
                trailing: IconButton(
                  tooltip: 'Copy',
                  icon: const Icon(Icons.copy),
                  onPressed: userCode == '—'
                      ? null
                      : () async {
                          await Clipboard.setData(ClipboardData(text: userCode));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('User code copied')),
                          );
                        },
                ),
              ),
            ),

            const SizedBox(height: 8),
            Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: ListTile(
                leading: const Icon(Icons.card_giftcard),
                title: const Text('Your Referral Code'),
                subtitle: Text(
                  referralCode.isEmpty ? 'Generating…' : referralCode,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    IconButton(
                      tooltip: 'Copy',
                      icon: const Icon(Icons.copy),
                      onPressed: referralCode.isEmpty
                          ? null
                          : () async {
                              await Clipboard.setData(
                                  ClipboardData(text: referralCode));
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Referral code copied')),
                              );
                            },
                    ),
                    IconButton(
                      tooltip: 'Share',
                      icon: const Icon(Icons.share),
                      onPressed: referralCode.isEmpty
                          ? null
                          : () async {
                              final link =
                                  'https://tourop.page.link/?ref=$referralCode';
                              Share.share(
                                  'Join TourOp using my referral: $referralCode\n$link');
                            },
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildWalletSection() {
    final walletRef =
        FirebaseFirestore.instance.collection('wallets').doc(widget.partnerId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: walletRef.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final wdata = snap.data?.data() ?? {};
        final balance = (wdata['balance'] is num)
            ? (wdata['balance'] as num).toDouble()
            : 0.0;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const RechargeWalletScreen()),
                      );
                    },
                    icon: const Icon(Icons.add_circle),
                    label: const Text('Recharge Wallet'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const SendMoneyScreen()));
                    },
                    icon: const Icon(Icons.send),
                    label: const Text('Send Money'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              child: ListTile(
                leading:
                    const Icon(Icons.account_balance_wallet, color: Colors.green),
                title: const Text('Wallet Balance'),
                subtitle: Text('₹${balance.toStringAsFixed(2)}'),
              ),
            ),
            const SizedBox(height: 10),
            const Text('History', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),

            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('wallet_logs')
                  .where('partnerId', isEqualTo: widget.partnerId)
                  .orderBy('at', descending: true)
                  .limit(50)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(8),
                    child: LinearProgressIndicator(minHeight: 2),
                  );
                }
                if (snap.hasError) {
                  return const Text('No wallet history yet.');
                }

                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Text('No wallet history yet.');
                }

                return Column(
                  children: docs.map((d) {
                    final m = d.data();
                    final delta =
                        (m['delta'] is num) ? (m['delta'] as num).toDouble() : 0.0;
                    final reason = (m['reason'] ?? '').toString();
                    final at = (m['at'] as Timestamp?)?.toDate();
                    final by = (m['by'] ?? '').toString();
                    final before =
                        (m['before'] is num) ? m['before'] as num : null;
                    final after =
                        (m['after'] is num) ? m['after'] as num : null;

                    final isCredit = delta >= 0;
                    return Card(
                      child: ListTile(
                        leading: Icon(
                            isCredit ? Icons.arrow_downward : Icons.arrow_upward,
                            color: isCredit ? Colors.green : Colors.red),
                        title: Text(isCredit ? 'Credit' : 'Debit'),
                        subtitle: Text([
                          if (reason.isNotEmpty) reason,
                          if (by.isNotEmpty) 'by: $by',
                          if (before != null && after != null)
                            '($before → $after)'
                        ].join(' • ')),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${isCredit ? '+' : '-'}₹${delta.abs().toStringAsFixed(2)}',
                              style: TextStyle(
                                color: isCredit ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (at != null)
                              Text(
                                '${at.day}/${at.month}/${at.year}',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey),
                              ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoCard(String label, String value, IconData icon) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: Text(value),
      ),
    );
  }

  Widget _buildRewardsSection() {
    final rewardsRef =
        FirebaseFirestore.instance.collection('rewards').doc(widget.partnerId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: rewardsRef.snapshots(),
      builder: (context, totalSnap) {
        if (totalSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final rdata = totalSnap.data?.data() ?? {};
        final totalPoints = (rdata['points'] is num)
            ? (rdata['points'] as num).toInt()
            : 0;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 2,
              child: ListTile(
                leading: const Icon(Icons.stars, color: Colors.orange),
                title: const Text('Total Reward Points'),
                subtitle: Text('$totalPoints points'),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Reward History', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),

            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('rewards_logs')
                  .where('partnerId', isEqualTo: widget.partnerId)
                  .orderBy('at', descending: true)
                  .limit(50)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(8),
                    child: LinearProgressIndicator(minHeight: 2),
                  );
                }
                if (snap.hasError) {
                  return const Text('No reward history yet.');
                }

                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Text('No reward history yet.');
                }

                return Column(
                  children: docs.map((d) {
                    final m = d.data();
                    final delta = (m['delta'] is num) ? (m['delta'] as num).toInt() : 0;
                    final reason = (m['reason'] ?? '').toString();
                    final at = (m['at'] as Timestamp?)?.toDate();
                    final by = (m['by'] ?? '').toString();
                    final before = (m['before'] is num) ? (m['before'] as num).toInt() : null;
                    final after  = (m['after']  is num) ? (m['after']  as num).toInt() : null;

                    final isGain = delta >= 0;
                    return Card(
                      child: ListTile(
                        leading: Icon(isGain ? Icons.add_circle : Icons.remove_circle,
                            color: isGain ? Colors.green : Colors.red),
                        title: Text(isGain ? 'Points Added' : 'Points Deducted'),
                        subtitle: Text([
                          if (reason.isNotEmpty) reason,
                          if (by.isNotEmpty) 'by: $by',
                          if (before != null && after != null) '($before → $after)',
                        ].join(' • ')),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${isGain ? '+' : '-'}${delta.abs()}',
                              style: TextStyle(
                                color: isGain ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (at != null)
                              Text(
                                '${at.day}/${at.month}/${at.year}',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        );
      },
    );
  }

}
