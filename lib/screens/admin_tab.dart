import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:driver_connect/services/shortcode_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminTab extends StatefulWidget {
  const AdminTab({super.key});

  @override
  State<AdminTab> createState() => _AdminTabState();

  Future<void> probeAdminPermissions(BuildContext context) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  final db = FirebaseFirestore.instance;

  if (uid == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Not signed in (uid=null)')),
    );
    return;
  }

  // A) Does /admins/<uid> exist?
  try {
    final a = await db.collection('admins').doc(uid).get();
    debugPrint('PROBE admins/$uid exists=${a.exists}');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('/admins/$uid exists=${a.exists}')),
    );
  } catch (e) {
    debugPrint('READ /admins/$uid FAILED: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('READ /admins/<uid> blocked by rules')),
    );
    return; // if you can’t read this, admin will fail too
  }

  // B) Can you create an admin_log? (admin-only)
  try {
    await db.collection('admin_logs').add({
      'probe': true,
      'by': uid,
      'at': FieldValue.serverTimestamp(),
    });
    debugPrint('CREATE admin_logs OK');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CREATE admin_logs OK')),
    );
  } catch (e) {
    debugPrint('CREATE admin_logs FAILED: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CREATE admin_logs FAILED (not admin?)')),
    );
    return;
  }

  // C) Can you update partners? (admin-only)
  final pRef = db.collection('partners').doc('_probe_do_not_use');
  try {
    await pRef.set({'touchedBy': uid, 'at': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    await pRef.delete().catchError((_) {});
    debugPrint('WRITE partners OK');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('WRITE partners OK')),
    );
  } catch (e) {
    debugPrint('WRITE partners FAILED: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('WRITE partners FAILED (not admin?)')),
    );
  }
}

}

class _AdminTabState extends State<AdminTab> {
  // Search (Partners)
  final _partnerSearchCtrl = TextEditingController();

  // Wallet inputs (accept short code / partner doc id / legacy uid)
  final _walletCodeCtrl = TextEditingController();
  final _walletAmountCtrl = TextEditingController();
  final _walletReasonCtrl = TextEditingController(text: 'Admin Adjustment');

  // Rewards inputs (accept short code / partner doc id / legacy uid)
  final _rewardsCodeCtrl = TextEditingController();
  final _rewardsPointsCtrl = TextEditingController();
  final _rewardsReasonCtrl = TextEditingController(text: 'Admin Adjustment');

  bool _mutating = false;

  @override
  void initState() {
    super.initState();
    _verifyAdminOrWarn();
  }

  @override
  void dispose() {
    _partnerSearchCtrl.dispose();
    _walletCodeCtrl.dispose();
    _walletAmountCtrl.dispose();
    _walletReasonCtrl.dispose();
    _rewardsCodeCtrl.dispose();
    _rewardsPointsCtrl.dispose();
    _rewardsReasonCtrl.dispose();
    super.dispose();
  }

  // ------------ helpers ------------

  Future<void> _verifyAdminOrWarn() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final doc = await FirebaseFirestore.instance.collection('admins').doc(uid).get();
      if (!doc.exists && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This account is not recognized as Admin. Admin actions will be blocked by Firestore rules.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _diagnosePermissions() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '<no-auth>';
    final db = FirebaseFirestore.instance;

    Future<void> ok(String msg) async {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ $msg')));
    }

    Future<void> fail(String where, Object e) async {
      // make the failure super explicit
      final msg = '❌ Permission denied at $where';
      // console
      // ignore: avoid_print
      print('$msg: $e  (AUTH_UID=$uid)');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$msg')));
    }

    try {
      // 0) show who we are and whether admins/<uid> exists
      final adminDoc = await db.collection('admins').doc(uid).get();
      // ignore: avoid_print
      print('DIAG: AUTH_UID=$uid  admins/<uid>.exists=${adminDoc.exists}');
      if (!adminDoc.exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This UID is NOT in /admins. Admin writes will fail.')),
        );
      }

      // 1) probe admin_logs create (must succeed for admins)
      try {
        await db.collection('admin_logs').add({
          'probe': 'admin_logs',
          'by': uid,
          'at': FieldValue.serverTimestamp(),
        });
        await ok('admin_logs.create passed');
      } catch (e) {
        await fail('admin_logs.create', e);
        return; // stop early — rules are blocking admin scope
      }

      // 2) probe partners update (write guarded by isAdmin)
      final probeRef = db.collection('partners').doc('_probe_admin_write_do_not_use');
      try {
        // harmless upsert + revert
        await db.runTransaction((tx) async {
          final snap = await tx.get(probeRef);
          final before = snap.data();
          tx.set(probeRef, {
            'probe': true,
            'touchedBy': uid,
            'at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          // revert (delete) inside the same transaction is not allowed;
          // do it after tx completes
        });
        await probeRef.delete().catchError((_) {});
        await ok('partners.write passed');
      } catch (e) {
        await fail('partners.write', e);
        return;
      }

      // 3) probe wallet_logs create
      try {
        await db.collection('wallet_logs').add({
          'probe': 'wallet_logs',
          'by': uid,
          'at': FieldValue.serverTimestamp(),
        });
        await ok('wallet_logs.create passed');
      } catch (e) {
        await fail('wallet_logs.create', e);
        return;
      }

      // 4) probe rewards_logs create
      try {
        await db.collection('rewards_logs').add({
          'probe': 'rewards_logs',
          'by': uid,
          'at': FieldValue.serverTimestamp(),
        });
        await ok('rewards_logs.create passed');
      } catch (e) {
        await fail('rewards_logs.create', e);
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Diagnostics: all admin writes passed.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Diagnostics failed: $e')));
    }
  }

  Future<void> _logAdminAction(String action, Map<String, dynamic> payload) async {
    await FirebaseFirestore.instance.collection('admin_logs').add({
      'action': action,
      'payload': payload,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<bool> _confirm(BuildContext context, String msg) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm'),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('OK')),
        ],
      ),
    );
    return res == true;
  }

  /// Resolve whatever admin typed (short code / partners doc id / legacy uid)
  /// to the canonical partners **doc id**.
  Future<String?> _resolvePartnerDocId(String raw) async {
    final input = raw.trim();
    if (input.isEmpty) return null;

    final codeUpper = input.toUpperCase();
    final db = FirebaseFirestore.instance;

    // 1) shortCode directly on partners
    final byCode = await db.collection('partners').where('shortCode', isEqualTo: codeUpper).limit(1).get();
    if (byCode.docs.isNotEmpty) return byCode.docs.first.id;

    // 2) direct partner doc id
    final direct = await db.collection('partners').doc(input).get();
    if (direct.exists) return direct.id;

    // 3) legacy uid field on partners
    final byUid = await db.collection('partners').where('uid', isEqualTo: input).limit(1).get();
    if (byUid.docs.isNotEmpty) return byUid.docs.first.id;

    // 4) optional mapping: codes/{shortCode} -> uid -> partner by uid
    final codeMap = await db.collection('codes').doc(codeUpper).get();
    if (codeMap.exists) {
      final m = codeMap.data() as Map<String, dynamic>?;
      final uid = (m?['uid'] ?? '').toString();
      if (uid.isNotEmpty) {
        final byUid2 = await db.collection('partners').where('uid', isEqualTo: uid).limit(1).get();
        if (byUid2.docs.isNotEmpty) return byUid2.docs.first.id;
      }
    }

    return null;
  }

  num _parseNum(String s) => num.tryParse(s.trim()) ?? 0;

  // ----- Rewards & Wallet mutations on partners/{docId} (transactional) -----

  Future<void> _runRewardsMutation({
    required String partnerDocId,
    required num pointsDelta, // + for add, - for subtract
    required String reason,
  }) async {
    final db = FirebaseFirestore.instance;
    await db.runTransaction((tx) async {
      final ref = db.collection('partners').doc(partnerDocId);
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw 'Partner not found';
      }
      final data = snap.data() as Map<String, dynamic>;
      final current = (data['rewardPoints'] is num) ? data['rewardPoints'] as num : 0;
      final next = current + pointsDelta;
      if (next < 0) throw 'Reward points cannot go negative';

      tx.update(ref, {'rewardPoints': next});

      final logRef = db.collection('rewards_logs').doc();
      tx.set(logRef, {
        'partnerId': partnerDocId,
        'delta': pointsDelta,
        'before': current,
        'after': next,
        'reason': reason,
        'at': FieldValue.serverTimestamp(),
        'by': 'admin_console',
      });
    });
  }

  Future<void> _runWalletMutation({
    required String partnerDocId,
    required num amountDelta, // + for credit, - for debit
    required String reason,
  }) async {
    final db = FirebaseFirestore.instance;
    await db.runTransaction((tx) async {
      final ref = db.collection('partners').doc(partnerDocId);
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw 'Partner not found';
      }
      final data = snap.data() as Map<String, dynamic>;
      final current = (data['walletBalance'] is num) ? data['walletBalance'] as num : 0;
      final next = current + amountDelta;
      if (next < 0) throw 'Wallet cannot go negative';

      tx.update(ref, {'walletBalance': next});

      final logRef = db.collection('wallet_logs').doc();
      tx.set(logRef, {
        'partnerId': partnerDocId,
        'delta': amountDelta,
        'before': current,
        'after': next,
        'reason': reason,
        'at': FieldValue.serverTimestamp(),
        'by': 'admin_console',
      });
    });
  }

  // ----- Button handlers (Rewards) -----

  Future<void> _rewardsAdd() async {
    final code = _rewardsCodeCtrl.text.trim();
    final pts = _parseNum(_rewardsPointsCtrl.text);
    final reason = _rewardsReasonCtrl.text.trim().isEmpty ? 'Admin Adjustment' : _rewardsReasonCtrl.text.trim();

    if (code.isEmpty || pts <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter partner code and positive points.')));
      return;
    }

    setState(() => _mutating = true);
    try {
      final docId = await _resolvePartnerDocId(code);
      if (docId == null) throw 'Partner not found';
      final ok = await _confirm(context, 'Add $pts reward points to $docId?');
      if (!ok) return;

      await _runRewardsMutation(partnerDocId: docId, pointsDelta: pts, reason: reason);
      await _logAdminAction('rewards_add', {'partnerDocId': docId, 'points': pts, 'reason': reason});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rewards added.')));
      _rewardsPointsCtrl.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _rewardsSubtract() async {
    final code = _rewardsCodeCtrl.text.trim();
    final pts = _parseNum(_rewardsPointsCtrl.text);
    final reason = _rewardsReasonCtrl.text.trim().isEmpty ? 'Admin Adjustment' : _rewardsReasonCtrl.text.trim();

    if (code.isEmpty || pts <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter partner code and positive points.')));
      return;
    }

    setState(() => _mutating = true);
    try {
      final docId = await _resolvePartnerDocId(code);
      if (docId == null) throw 'Partner not found';
      final ok = await _confirm(context, 'Subtract $pts reward points from $docId?');
      if (!ok) return;

      await _runRewardsMutation(partnerDocId: docId, pointsDelta: -pts, reason: reason);
      await _logAdminAction('rewards_subtract', {'partnerDocId': docId, 'points': -pts, 'reason': reason});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rewards subtracted.')));
      _rewardsPointsCtrl.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  // ----- Button handlers (Wallet) -----

  Future<void> _walletCredit() async {
    final code = _walletCodeCtrl.text.trim();
    final amt = _parseNum(_walletAmountCtrl.text);
    final reason = _walletReasonCtrl.text.trim().isEmpty ? 'Admin Adjustment' : _walletReasonCtrl.text.trim();

    if (code.isEmpty || amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter partner code and positive amount.')));
      return;
    }

    setState(() => _mutating = true);
    try {
      final docId = await _resolvePartnerDocId(code);
      if (docId == null) throw 'Partner not found';
      final ok = await _confirm(context, 'Credit ₹$amt to wallet of $docId?');
      if (!ok) return;

      await _runWalletMutation(partnerDocId: docId, amountDelta: amt, reason: reason);
      await _logAdminAction('wallet_credit', {'partnerDocId': docId, 'amount': amt, 'reason': reason});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wallet credited.')));
      _walletAmountCtrl.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _walletDebit() async {
    final code = _walletCodeCtrl.text.trim();
    final amt = _parseNum(_walletAmountCtrl.text);
    final reason = _walletReasonCtrl.text.trim().isEmpty ? 'Admin Adjustment' : _walletReasonCtrl.text.trim();

    if (code.isEmpty || amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter partner code and positive amount.')));
      return;
    }

    setState(() => _mutating = true);
    try {
      final docId = await _resolvePartnerDocId(code);
      if (docId == null) throw 'Partner not found';
      final ok = await _confirm(context, 'Debit ₹$amt from wallet of $docId?');
      if (!ok) return;

      await _runWalletMutation(partnerDocId: docId, amountDelta: -amt, reason: reason);
      await _logAdminAction('wallet_debit', {'partnerDocId': docId, 'amount': -amt, 'reason': reason});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wallet debited.')));
      _walletAmountCtrl.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  // ------------ UI ------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onLongPress: _diagnosePermissions, // Hidden diagnostic: long-press title
          child: const Text('Admin Console'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text('Admin Controls', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),

          // ===== Partners =====
          Card(
            elevation: 2,
            child: ExpansionTile(
              leading: const Icon(Icons.people_alt),
              title: const Text('Partners'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _partnerSearchCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Search by name / phone / code',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('partners')
                      .orderBy('partnerName')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(),
                      );
                    }

                    final q = _partnerSearchCtrl.text.trim().toLowerCase();
                    final docs = snapshot.data!.docs.where((d) {
                      final data = d.data() as Map<String, dynamic>;
                      final n = (data['partnerName'] ?? '').toString().toLowerCase();
                      final m = (data['mobileNumber'] ?? '').toString().toLowerCase();
                      final sc = (data['shortCode'] ?? '').toString().toLowerCase();
                      return q.isEmpty || n.contains(q) || m.contains(q) || sc.contains(q);
                    }).toList();

                    if (docs.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('No partners found.'),
                      );
                    }

                    return Column(
                      children: docs.map((d) {
                        final data = d.data() as Map<String, dynamic>;
                        final docId = d.id;
                        final name = data['partnerName'] ?? 'Unknown';
                        final mobile = data['mobileNumber'] ?? '';
                        final ccRaw = (data['countryCode'] as String?)?.trim();
                        final ccToShow = (ccRaw != null && ccRaw.isNotEmpty) ? ccRaw : '+91';
                        final shortCode = (data['shortCode'] ?? '').toString().toUpperCase();
                        final isAdmin = data['isAdmin'] == true;
                        final disabled = data['disabled'] == true;

                        return ListTile(
                          leading: const Icon(Icons.person),
                          title: Text(name),
                          subtitle: Text('Code: ${shortCode.isNotEmpty ? shortCode : "—"} • $ccToShow $mobile'),
                          trailing: Wrap(
                            spacing: 8,
                            children: [
                              // Make/Remove Admin (with UID backfill)
                              TextButton(
                                onPressed: () async {
                                  final db = FirebaseFirestore.instance;
                                  String? uid = (data['uid'] ?? '').toString().trim();

                                  // Try backfill from codes/{shortCode}.uid if uid missing
                                  if (uid.isEmpty) {
                                    final sc = (data['shortCode'] ?? '').toString().toUpperCase().trim();
                                    if (sc.isNotEmpty) {
                                      final codeDoc = await db.collection('codes').doc(sc).get();
                                      final mappedUid = (codeDoc.data()?['uid'] ?? '').toString().trim();
                                      if (mappedUid.isNotEmpty) {
                                        await d.reference.set({'uid': mappedUid}, SetOptions(merge: true));
                                        uid = mappedUid;
                                      }
                                    }
                                  }

                                  // If still missing, ask admin to paste the UID once
                                  if (uid.isEmpty) {
                                    final pasted = await showDialog<String>(
                                      context: context,
                                      builder: (_) {
                                        final ctrl = TextEditingController();
                                        return AlertDialog(
                                          title: const Text('Link Auth UID'),
                                          content: TextField(
                                            controller: ctrl,
                                            decoration: const InputDecoration(
                                              labelText: 'Paste Firebase Auth UID',
                                              border: OutlineInputBorder(),
                                            ),
                                          ),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                                            TextButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Save')),
                                          ],
                                        );
                                      },
                                    );
                                    if (pasted == null || pasted.isEmpty) {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Cannot make admin: partner has no UID on record')),
                                      );
                                      return;
                                    }
                                    await d.reference.set({'uid': pasted}, SetOptions(merge: true));
                                    uid = pasted;
                                  }

                                  final ok = await _confirm(context, isAdmin ? 'Remove admin?' : 'Make admin?');
                                  if (!ok) return;

                                  if (!isAdmin) {
                                    await db.collection('admins').doc(uid).set({'at': FieldValue.serverTimestamp()}, SetOptions(merge: true));
                                    await d.reference.set({'isAdmin': true}, SetOptions(merge: true)); // UI flag only
                                    await _logAdminAction('toggle_admin', {'targetPartnerDoc': docId, 'uid': uid, 'to': true});
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Admin granted.')));
                                    }
                                  } else {
                                    await db.collection('admins').doc(uid).delete();
                                    await d.reference.set({'isAdmin': false}, SetOptions(merge: true)); // UI flag only
                                    await _logAdminAction('toggle_admin', {'targetPartnerDoc': docId, 'uid': uid, 'to': false});
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Admin removed.')));
                                    }
                                  }
                                },
                                child: Text(isAdmin ? 'Remove Admin' : 'Make Admin'),
                              ),

                              // Disable / Enable
                              TextButton(
                                onPressed: () async {
                                  final ok = await _confirm(context, disabled ? 'Enable account?' : 'Disable account?');
                                  if (!ok) return;
                                  await d.reference.set({'disabled': !disabled}, SetOptions(merge: true));
                                  await _logAdminAction('toggle_disabled', {
                                    'targetPartnerDoc': docId,
                                    'to': !disabled
                                  });
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(disabled ? 'Enabled' : 'Disabled')),
                                    );
                                  }
                                },
                                child: Text(disabled ? 'Enable' : 'Disable'),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),

          // ===== Routes (Booking) =====
          Card(
            elevation: 2,
            child: ExpansionTile(
              leading: const Icon(Icons.route),
              title: const Text('Booking Routes (latest 100)'),
              children: [
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('routes')
                      .orderBy('timestamp', descending: true)
                      .limit(100)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(),
                      );
                    }
                    final docs = snapshot.data!.docs;
                    if (docs.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('No routes.'),
                      );
                    }
                    return Column(
                      children: docs.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final title = "${data['from'] ?? '?'} → ${data['to'] ?? '?'}";
                        final subtitle = "${data['date'] ?? ''} ${data['time'] ?? ''} • ${(data['partnerName'] ?? 'Driver')}";
                        return ListTile(
                          title: Text(title),
                          subtitle: Text(subtitle),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () async {
                              final ok = await _confirm(context, 'Delete this route?');
                              if (!ok) return;
                              await doc.reference.delete();
                              await _logAdminAction('delete_route', {'routeId': doc.id});
                            },
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),

          // ===== Exchange Routes =====
          Card(
            elevation: 2,
            child: ExpansionTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Exchange Routes (latest 100)'),
              children: [
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('exchange_routes')
                      .orderBy('timestamp', descending: true)
                      .limit(100)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(),
                      );
                    }
                    final docs = snapshot.data!.docs;
                    if (docs.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('No exchange routes.'),
                      );
                    }
                    return Column(
                      children: docs.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final title = "${data['from'] ?? '?'} → ${data['to'] ?? '?'}";
                        final subtitle = "${data['date'] ?? ''} ${data['time'] ?? ''} • ${(data['partnerName'] ?? 'Driver')}";
                        return ListTile(
                          title: Text(title),
                          subtitle: Text(subtitle),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () async {
                              final ok = await _confirm(context, 'Delete this exchange route?');
                              if (!ok) return;
                              await doc.reference.delete();
                              await _logAdminAction('delete_exchange_route', {'exchangeId': doc.id});
                            },
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),

          // ===== Wallets (Credit / Debit) =====
          Card(
            elevation: 2,
            child: ExpansionTile(
              leading: const Icon(Icons.account_balance_wallet),
              title: const Text('Wallets (Credit / Debit)'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      TextField(
                        controller: _walletCodeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Partner Code (short code / partner doc id / legacy uid)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _walletAmountCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Amount (positive number)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _walletReasonCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Reason',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.arrow_downward),
                              label: const Text('Credit Wallet'),
                              onPressed: _mutating ? null : _walletCredit,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.arrow_upward),
                              label: const Text('Debit Wallet'),
                              onPressed: _mutating ? null : _walletDebit,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ===== Rewards (Add / Subtract) =====
          Card(
            elevation: 2,
            child: ExpansionTile(
              leading: const Icon(Icons.stars),
              title: const Text('Rewards (Add / Subtract Points)'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      TextField(
                        controller: _rewardsCodeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Partner Code (short code / partner doc id / legacy uid)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _rewardsPointsCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Points (positive number)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _rewardsReasonCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Reason',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.add),
                              label: const Text('Add Points'),
                              onPressed: _mutating ? null : _rewardsAdd,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.remove),
                              label: const Text('Subtract Points'),
                              onPressed: _mutating ? null : _rewardsSubtract,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ===== Reports (light) =====
          Card(
            elevation: 2,
            child: ExpansionTile(
              leading: const Icon(Icons.analytics),
              title: const Text('Reports (Snapshot)'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: FutureBuilder<List<int>>(
                    future: _counts(),
                    builder: (context, snap) {
                      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                      final counts = snap.data!;
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _statCard('Partners', counts[0]),
                          _statCard('Routes', counts[1]),
                          _statCard('Exchange Routes', counts[2]),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<List<int>> _counts() async {
    final partnersSnap = await FirebaseFirestore.instance.collection('partners').count().get();
    final routesSnap = await FirebaseFirestore.instance.collection('routes').count().get();
    final exchSnap = await FirebaseFirestore.instance.collection('exchange_routes').count().get();

    final int partners = partnersSnap.count ?? 0;
    final int routes = routesSnap.count ?? 0;
    final int exch = exchSnap.count ?? 0;

    return [partners, routes, exch];
  }

  Widget _statCard(String label, int value) {
    return Card(
      elevation: 1,
      child: Container(
        width: 160,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 6),
            Text('$value', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
