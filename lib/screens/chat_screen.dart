import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class ChatScreen extends StatefulWidget {
  final String currentUserId;
  final String partnerId;
  final String partnerName;

  final String? originRouteId;
  final String originCollection;

  const ChatScreen({
    super.key,
    required this.currentUserId,
    required this.partnerId,
    required this.partnerName,
    this.originRouteId,
    this.originCollection = 'routes',
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<DocumentSnapshot> messages = [];

  late String chatId;
  StreamSubscription<QuerySnapshot>? _sub;

  String? _originRouteId;
  late String _originCollection;

  @override
  void initState() {
    super.initState();

    chatId = _getChatId(widget.currentUserId, widget.partnerId);
    _originRouteId = widget.originRouteId;
    _originCollection = widget.originCollection;

    _resetUnreadForMe();
    _ensureOriginOnChat();
    _listenToMessages();
  }

  @override
  void dispose() {
    _sub?.cancel();

    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _getChatId(String u1, String u2) =>
      u1.hashCode <= u2.hashCode ? '$u1-$u2' : '$u2-$u1';

  Future<void> _ensureOriginOnChat() async {
    final chatRef = FirebaseFirestore.instance.collection('chats').doc(chatId);

    await chatRef.set({
      'participants': [widget.currentUserId, widget.partnerId],
      'partnerName_${widget.currentUserId}':
          FirebaseAuth.instance.currentUser?.displayName ?? 'You',
      'partnerName_${widget.partnerId}': widget.partnerName,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'open',
      if (_originRouteId != null && _originRouteId!.isNotEmpty) ...{
        'origin': {
          'collection': _originCollection,
          'routeId': _originRouteId,
          'ownerId': widget.partnerId,
        },
        'originCollection': _originCollection,
        'originRouteId': _originRouteId,
      },
    }, SetOptions(merge: true));
  }

  Future<void> _resetUnreadForMe() async {
    try {
      final chatRef = FirebaseFirestore.instance.collection('chats').doc(chatId);
      await chatRef.set({
        'unread_${widget.currentUserId}': 0,
        'lastRead_${widget.currentUserId}': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  void _listenToMessages() {
    _sub?.cancel();
    _sub = FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      setState(() => messages = snapshot.docs);
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    final chatRef = FirebaseFirestore.instance.collection('chats').doc(chatId);

    try {
      await chatRef.collection('messages').add({
        'message': text,
        'senderId': widget.currentUserId,
        'receiverId': widget.partnerId,
        'timestamp': Timestamp.now(),
        'type': 'text',
      });

      await chatRef.set({
        'unread_${widget.partnerId}': FieldValue.increment(1),
        'unread_${widget.currentUserId}': 0,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessage': text,
      }, SetOptions(merge: true));

      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to send: $e')));
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ===========================================================
  // ✅ RESTORED: END CHAT (3 DOTS MENU)
  // ===========================================================
  Future<void> _endChat() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('End chat?'),
        content: const Text('This will delete the entire conversation.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End Chat', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final chatRef = FirebaseFirestore.instance.collection('chats').doc(chatId);

    try {
      while (true) {
        final batchSnap = await chatRef.collection('messages').limit(200).get();
        if (batchSnap.docs.isEmpty) break;

        final wb = FirebaseFirestore.instance.batch();
        for (final m in batchSnap.docs) {
          wb.delete(m.reference);
        }
        await wb.commit();
      }

      await chatRef.delete();
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to delete chat: $e')));
    }
  }

  // ===========================================================
  // ✅ RESTORED: CLOSE DEAL (3 DOTS MENU)
  // ===========================================================
  Future<void> _closeDeal() async {
    if (_originRouteId == null || _originRouteId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No linked route to close.")),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Close Deal?"),
        content: const Text("This will mark the route as 'Deal Closed'."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Close Deal"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await FirebaseFirestore.instance
          .collection(_originCollection)
          .doc(_originRouteId)
          .set({
        'dealClosed': true,
        'dealClosedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to close deal: $e")),
      );
    }
  }

  // =========================
  // 💲 SEND MONEY
  // =========================
  void _openSendMoneySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // ✅ FIX: allow full height + keyboard
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SingleChildScrollView(
        // ✅ FIX: prevent button being covered by keyboard
        child: _SendMoneySheet(
          partnerId: widget.partnerId,
          partnerName: widget.partnerName,
        ),
      ),
    );
  }

  // =========================
  // 🎁 SEND REWARD POINTS
  // =========================
  void _openSendRewardPointsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // ✅ FIX: allow full height + keyboard
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SingleChildScrollView(
        // ✅ FIX: prevent button being covered by keyboard
        child: _SendRewardPointsSheet(
          partnerId: widget.partnerId,
          partnerName: widget.partnerName,
        ),
      ),
    );
  }

  Future<void> _copyToClipboard(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Copied')));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.indigo,
        title: Row(
          children: [
            Expanded(
              child: Text(
                widget.partnerName,
                style: const TextStyle(color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.currency_rupee, color: Colors.white),
              onPressed: _openSendMoneySheet,
            ),
            IconButton(
              icon: const Icon(Icons.card_giftcard, color: Colors.white),
              onPressed: _openSendRewardPointsSheet,
            ),
          ],
        ),

        // ✅ RESTORED 3 DOTS MENU (End Chat / Close Deal)
        actionsIconTheme: const IconThemeData(color: Colors.white),
        actions: [
          PopupMenuButton<String>(
            color: Colors.white,
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (val) {
              if (val == 'end') _endChat();
              if (val == 'close') _closeDeal();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'end', child: Text('End Chat')),
              PopupMenuItem(value: 'close', child: Text('Close Deal')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                reverse: true,
                controller: _scrollController,
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final data = messages[index].data() as Map<String, dynamic>;
                  final msg = (data['message'] ?? '').toString();
                  final isMe = data['senderId'] == widget.currentUserId;

                  return Align(
                    alignment:
                        isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: GestureDetector(
                      onLongPress: () => _copyToClipboard(msg),
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                            vertical: 4, horizontal: 10),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.indigo : Colors.grey[300],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: SelectableText(
                          msg,
                          style: TextStyle(
                              color: isMe ? Colors.white : Colors.black),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              color: Colors.grey[100],
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: "Type a message...",
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send, color: Colors.indigo),
                    onPressed: _sendMessage,
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================
// 💲 SEND MONEY SHEET (UNCHANGED)
// ===========================================================
class _SendMoneySheet extends StatefulWidget {
  final String partnerId;
  final String partnerName;

  const _SendMoneySheet({
    required this.partnerId,
    required this.partnerName,
  });

  @override
  State<_SendMoneySheet> createState() => _SendMoneySheetState();
}

class _SendMoneySheetState extends State<_SendMoneySheet> {
  bool _loading = false;
  double? _selectedAmount;
  final TextEditingController _customController = TextEditingController();

  Future<void> _sendSelectedAmount() async {
    final amount =
        _selectedAmount ?? double.tryParse(_customController.text.trim());

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final user = FirebaseAuth.instance.currentUser!;
      final token = await user.getIdToken();

      final res = await http.post(
        Uri.parse(
          'https://asia-south2-tourop-6d58a.cloudfunctions.net/sendMoneyHttp',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'toUid': widget.partnerId,
          'amount': amount,
        }),
      );

      if (res.statusCode != 200) {
        throw Exception(res.body);
      }

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('₹${amount.toInt()} sent to ${widget.partnerName}'),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().contains('insufficient')
                ? 'Insufficient wallet balance'
                : 'Transfer failed',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _amountChip(int amount) {
    return ChoiceChip(
      label: Text('₹$amount'),
      selected: _selectedAmount == amount.toDouble(),
      onSelected: (_) {
        setState(() {
          _selectedAmount = amount.toDouble();
          _customController.clear();
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Send money to ${widget.partnerName}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            children: [
              _amountChip(50),
              _amountChip(100),
              _amountChip(200),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _customController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Custom amount',
              prefixText: '₹ ',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) {
              setState(() => _selectedAmount = null);
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _loading ? null : _sendSelectedAmount,
              child: _loading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(
                      _selectedAmount != null
                          ? 'Send ₹${_selectedAmount!.toInt()}'
                          : 'Send',
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================
// 🎁 SEND REWARD POINTS SHEET (UNCHANGED LOGIC)
// ===========================================================
class _SendRewardPointsSheet extends StatefulWidget {
  final String partnerId;
  final String partnerName;

  const _SendRewardPointsSheet({
    required this.partnerId,
    required this.partnerName,
  });

  @override
  State<_SendRewardPointsSheet> createState() => _SendRewardPointsSheetState();
}

class _SendRewardPointsSheetState extends State<_SendRewardPointsSheet> {
  bool _loading = false;

  // ✅ NEW: selected preset points
  int? _selectedPoints;

  // kept from your code
  final TextEditingController _customController = TextEditingController();

  Future<void> _sendSelectedPoints() async {
    final points =
        _selectedPoints ?? int.tryParse(_customController.text.trim());

    if (points == null || points <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid points')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final user = FirebaseAuth.instance.currentUser!;
      final token = await user.getIdToken();

      final res = await http.post(
        Uri.parse(
          'https://asia-south2-tourop-6d58a.cloudfunctions.net/sendRewardPoints',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'toUid': widget.partnerId,
          'points': points,
        }),
      );

      if (res.statusCode != 200) {
        throw Exception(res.body);
      }

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$points reward points sent')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().toLowerCase().contains('insufficient')
                ? 'Insufficient reward points'
                : 'Transfer failed',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _pointsChip(int pts) {
    return ChoiceChip(
      label: Text('$pts'),
      selected: _selectedPoints == pts,
      onSelected: (_) {
        setState(() {
          _selectedPoints = pts;
          _customController.clear();
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Send reward points',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            children: [
              _pointsChip(50),
              _pointsChip(100),
              _pointsChip(200),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _customController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Custom points',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) {
              setState(() => _selectedPoints = null);
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _loading ? null : _sendSelectedPoints,
              child: _loading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(
                      _selectedPoints != null ? 'Send $_selectedPoints' : 'Send',
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
