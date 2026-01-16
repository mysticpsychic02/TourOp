import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:driver_connect/screens/welcome_screen.dart';
import 'package:driver_connect/screens/account_tab.dart';
import 'package:driver_connect/screens/chat_screen.dart';
import 'package:driver_connect/screens/favorite_routes_screen.dart';
import 'package:driver_connect/data/indian_places.dart';
import 'dart:async';
import 'package:driver_connect/data/nearby_index.dart';
import 'package:driver_connect/data/state_clusters.dart';

/// Global helper used by the Publish form (kept as-is)
Widget buildPlaceAutocompleteField({
  required String label,
  required TextEditingController controller,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Autocomplete<String>(
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return const Iterable<String>.empty();
        }
        return indianPlaces.where(
          (place) => place.toLowerCase().contains(textEditingValue.text.toLowerCase()),
        );
      },
      onSelected: (String selection) {
        controller.text = selection;
      },
      fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
        textEditingController.text = controller.text;
        return TextField(
          controller: textEditingController,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          onChanged: (value) => controller.text = value,
        );
      },
    ),
  );
}

class DashboardScreen extends StatefulWidget {
  final String partnerName;
  final String partnerId;
  final String mobileNumber;
  final String firmName;
  final String address;

  const DashboardScreen({
    super.key,
    required this.partnerName,
    required this.partnerId,
    required this.mobileNumber,
    required this.firmName,
    required this.address,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  // Live greeting stream (updates when Firestore doc updates)
  late final Stream<String> _greetingStream;

  List<Widget> get _tabs => [
        const BookingTab(),
        const PublishTab(),
        const ExchangeTab(),
        AccountTab(
          partnerName: widget.partnerName,
          partnerId: widget.partnerId,
          mobileNumber: widget.mobileNumber,
          firmName: widget.firmName,
          address: widget.address,
        ),
      ];


  @override
  void initState() {
    super.initState();
    final u = FirebaseAuth.instance.currentUser;
    // 👇 copy this value to search in Firestore if needed
    debugPrint('DASH UID => ${u?.uid}  phone=${u?.phoneNumber}  displayName=${u?.displayName}');
    _greetingStream = _buildGreetingStream();

    // ensure canonical partners/{uid} exists & has name – no queries involved
    _ensureSelfPartnerDoc();
    _ensurePartnerDocHasName();

  }

  /// Ensure partners/{uid} has a partnerName (no queries; respects your rules).
  Future<void> _ensurePartnerDocHasName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final uid = user.uid;
    final partners = FirebaseFirestore.instance.collection('partners');
    final docRef = partners.doc(uid);

    // If already has a name, stop.
    final snap = await docRef.get();
    final data = snap.data() ?? {};
    final existing = (data['partnerName'] ?? '').toString().trim();
    if (existing.isNotEmpty) return;

    // Prefer the name you already pass into the widget.
    final incoming = (widget.partnerName).trim();
    if (incoming.isNotEmpty && incoming.toLowerCase() != 'null') {
      await docRef.set({'uid': uid, 'partnerName': incoming}, SetOptions(merge: true));
      try { await user.updateDisplayName(incoming); } catch (_) {}
      return;
    }

    // Fallback: Firebase Auth displayName
    final dn = (user.displayName ?? '').trim();
    if (dn.isNotEmpty) {
      await docRef.set({'uid': uid, 'partnerName': dn}, SetOptions(merge: true));
      return;
    }

    // If nothing found, leave it. Header will show "Driver" until user edits profile.
  }

  /// Create a live stream of the greeting name from partners/{uid}.
  Stream<String> _buildGreetingStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Stream.value('Driver');
    }
    final partners = FirebaseFirestore.instance.collection('partners');
    final docStream = partners.doc(user.uid).snapshots();
    return docStream.map((snap) {
      final data = snap.data();
      final name = (data?['partnerName'] ?? '').toString().trim();
      if (name.isNotEmpty) return name.split(' ').first;

      // fallback to Auth displayName if partners doc doesn't have a name yet
      final dn = (user.displayName ?? '').trim();
      if (dn.isNotEmpty) return dn.split(' ').first;

      return 'Driver';
    });
  }

  /// Ensure partners/{uid} exists & basic fields are set (no collection queries).
  Future<void> _ensureSelfPartnerDoc() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final uid = user.uid;
    final partners = FirebaseFirestore.instance.collection('partners');

    // Normalize phone into both E.164 and local variants
    final variants = _allPhoneVariants(user.phoneNumber);

    // If partners/{uid} already has a name, keep it; otherwise set what we have.
    final byId = await partners.doc(uid).get();
    final nameById = (byId.data()?['partnerName'] ?? '').toString().trim();

    // Choose the best available name (widget first, then existing, then displayName)
    final widgetName = (widget.partnerName).trim();
    final displayName = (user.displayName ?? '').trim();
    final chosenName = widgetName.isNotEmpty && widgetName.toLowerCase() != 'null'
        ? widgetName
        : (nameById.isNotEmpty ? nameById : displayName);

    await partners.doc(uid).set({
      'uid': uid,
      if (chosenName.isNotEmpty) 'partnerName': chosenName,
      if (variants.primary.isNotEmpty) 'mobileNumber': variants.primary, // local without country code
      if (variants.raw.isNotEmpty) 'phoneE164': variants.raw,            // +country
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Mirror to Auth displayName if we picked a better one
    if (chosenName.isNotEmpty && (user.displayName ?? '').trim() != chosenName) {
      try { await user.updateDisplayName(chosenName); } catch (_) {}
    }
  }

  // Helper to normalize phone number into common variants
  _PhoneVariants _allPhoneVariants(String? phone) {
    final raw = (phone ?? '').trim();             // e.g. +919876543210 / +14165551234
    final noPlus91 = raw.startsWith('+91') ? raw.substring(3) : raw;
    final noPlus1 = raw.startsWith('+1') ? raw.substring(2) : raw;
    final plus91 = noPlus91.isNotEmpty ? '+91$noPlus91' : '';
    final plus1 = noPlus1.isNotEmpty ? '+1$noPlus1' : '';

    // choose a primary normalized number to store: prefer no-country-code
    final primary = noPlus91 != raw ? noPlus91 : (noPlus1 != raw ? noPlus1 : raw);
    return _PhoneVariants(
      raw: raw,
      noPlus91: noPlus91,
      noPlus1: noPlus1,
      plus91: plus91,
      plus1: plus1,
      primary: primary,
    );
  }

  void _onTabTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.indigo.shade50,
      appBar: AppBar(
        backgroundColor: Colors.indigo,
        title: Row(
          children: [
            const Icon(Icons.directions_car, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: StreamBuilder<String>(
                stream: _greetingStream,
                builder: (context, snap) {
                  final name = (snap.data ?? '').trim();
                  return Text(
                    'Welcome, ${name.isEmpty ? 'Driver' : name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white),
                  );
                },
              ),
            ),
          ],
        ),
        // 👇 NEW: Chat icon to open all active chats
        actions: [
          IconButton(
            tooltip: 'Active chats',
            icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ActiveChatsScreen()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: _tabs[_selectedIndex],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onTabTapped,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.indigo,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.directions_car), label: 'Booking'),
          BottomNavigationBarItem(icon: Icon(Icons.publish), label: 'Publish'),
          BottomNavigationBarItem(icon: Icon(Icons.swap_horiz), label: 'Exchange'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Account'),
        ],
      ),
    );
  }
}

class _PhoneVariants {
  final String raw;
  final String noPlus91;
  final String noPlus1;
  final String plus91;
  final String plus1;
  final String primary;
  _PhoneVariants({
    required this.raw,
    required this.noPlus91,
    required this.noPlus1,
    required this.plus91,
    required this.plus1,
    required this.primary,
  });
}


/* ===========================
 *        BOOKING TAB
 * =========================== */

class BookingTab extends StatefulWidget {
  const BookingTab({super.key});
  @override
  State<BookingTab> createState() => _BookingTabState();
}

class _BookingTabState extends State<BookingTab>
    with AutomaticKeepAliveClientMixin<BookingTab> {
  @override
  bool get wantKeepAlive => true;

  // ---------- filters ----------
  final TextEditingController _fromFilter = TextEditingController();
  final TextEditingController _toFilter = TextEditingController();
  final TextEditingController _dateFilter = TextEditingController();
  bool _filterNoCabOnly = false;

  // Only expanding TO (by request)
  List<String> _expandedToCandidates = [];

  // ---------- request-a-cab form ----------
  final _reqFormKey = GlobalKey<FormState>();
  final TextEditingController _reqFrom = TextEditingController();
  final TextEditingController _reqTo = TextEditingController();
  final TextEditingController _reqDate = TextEditingController();
  final TextEditingController _reqTime = TextEditingController();
  String? _reqVehicleType;

  // Vehicle list for request dialog (without "no car")
  final List<String> _vehicleTypesSansNoCar = const [
    '4+1 hatchback - 4+1 seater',
    '4+1 sedan - 4+1 seater',
    '4+1 suv - 4+1 seater',
    '6+1 seater other than innova Crysta',
    '6+1 innova Crysta',
    '7+1 innova Crysta',
  ];

  String? currentUserId;

  // 🔔 open chats linked to a posting (only if unread > 0 and status=open)
  List<DocumentSnapshot<Map<String, dynamic>>> _openChatDocs = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _chatSub;
  final Map<String, String> _nameCache = {};

  @override
  void initState() {
    super.initState();
    currentUserId = FirebaseAuth.instance.currentUser?.uid;
    _listenForOpenChatsBubble();
  }

  @override
  void dispose() {
    _fromFilter.dispose();
    _toFilter.dispose();
    _dateFilter.dispose();

    _reqFrom.dispose();
    _reqTo.dispose();
    _reqDate.dispose();
    _reqTime.dispose();

    _chatSub?.cancel();
    super.dispose();
  }

  // ---------- expand TO with nearby + state ----------
  List<String> _expandWithNearbyAndState(String input) {
    if (input.trim().isEmpty) return const <String>[];
    final key = input.trim();

    final exact = <String>[key];
    final nearby = (kNearbyIndex[key] ?? const <String>[]).cast<String>();

    final stateName = kCityToState[key];
    final stateCities = (stateName != null)
        ? (kStateToCities[stateName]?.cast<String>() ?? const <String>[])
        : const <String>[];

    return <String>{...exact, ...nearby, ...stateCities}.toList();
  }

  // ---------- filtering actions ----------
  void _applyFilter() {
    _expandedToCandidates = _expandWithNearbyAndState(_toFilter.text);
    setState(() {});
  }

  void _clearFilter() {
    _fromFilter.clear();
    _toFilter.clear();
    _dateFilter.clear();
    _filterNoCabOnly = false;
    _expandedToCandidates = [];
    setState(() {});
  }

  void _showFilterDialog() {
    bool tempNoCabOnly = _filterNoCabOnly;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Filter Routes'),
              content: SizedBox(
                width: 320,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildPlaceAutocompleteField(
                        label: "From",
                        controller: _fromFilter,
                      ),
                      _buildPlaceAutocompleteField(
                        label: "To",
                        controller: _toFilter,
                      ),
                      _buildDatePickerField(context, "Date", _dateFilter),
                      const SizedBox(height: 6),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text("Show only 'Need a Cab' posts"),
                        value: tempNoCabOnly,
                        onChanged: (v) => setStateDialog(() => tempNoCabOnly = v),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _filterNoCabOnly = tempNoCabOnly;
                      _applyFilter();
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Apply'),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _fromFilter.clear();
                      _toFilter.clear();
                      _dateFilter.clear();
                      _filterNoCabOnly = false;
                      _expandedToCandidates = [];
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Reset'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ---------- request-a-cab ----------
  void _openRequestCabDialog() {
    _reqFrom.clear();
    _reqTo.clear();
    _reqDate.clear();
    _reqTime.clear();
    _reqVehicleType = null;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Need a Cab"),
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
            maxWidth: 420,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Form(
              key: _reqFormKey,
              autovalidateMode: AutovalidateMode.disabled,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildPlaceAutocompleteField(
                    label: "From",
                    controller: _reqFrom,
                    asFormField: true,
                    requiredField: true,
                  ),
                  _buildPlaceAutocompleteField(
                    label: "To",
                    controller: _reqTo,
                    asFormField: true,
                    requiredField: true,
                  ),
                  _buildDatePickerFormField(
                    context: context,
                    label: "Date",
                    controller: _reqDate,
                    requiredField: true,
                  ),
                  _buildTimePickerFormField(
                    context: context,
                    label: "Time",
                    controller: _reqTime,
                    requiredField: true,
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _reqVehicleType,
                    decoration: const InputDecoration(
                      labelText: 'Preferred Vehicle Type',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    items: _vehicleTypesSansNoCar
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setState(() => _reqVehicleType = v),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: _postNoCabRequest, child: const Text('Post')),
        ],
      ),
    );
  }

  Future<void> _postNoCabRequest() async {
    if (!(_reqFormKey.currentState?.validate() ?? false)) return;

    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    try {
      String partnerName =
          FirebaseAuth.instance.currentUser?.displayName ?? 'Unknown Partner';

      final phone = FirebaseAuth.instance.currentUser?.phoneNumber
          ?.replaceAll('+91', '')
          ?.replaceAll('+1', '');
      if (phone != null) {
        final q = await FirebaseFirestore.instance
            .collection('partners')
            .where('mobileNumber', isEqualTo: phone)
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) {
          partnerName =
              (q.docs.first.data()['partnerName'] ?? partnerName).toString();
        }
      }

      await FirebaseFirestore.instance.collection('routes').add({
        'from': _reqFrom.text.trim(),
        'to': _reqTo.text.trim(),
        'date': _reqDate.text.trim(),
        'time': _reqTime.text.trim(),
        'vehicleType': 'no car',
        'requestedVehicleType': _reqVehicleType,
        'isNoCab': true,
        'partnerId': me.uid,
        'partnerName': partnerName,
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cab request posted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  // ---------- chat helpers ----------
  String _chatIdStable(String a, String b) =>
      a.hashCode <= b.hashCode ? '$a-$b' : '$b-$a';

  Future<void> _startChatWithPartnerFromRoute({
    required String routeDocId,
    required String partnerId,
    required String partnerName,
  }) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    final chatId = _chatIdStable(me.uid, partnerId);
    final chatRef = FirebaseFirestore.instance.collection('chats').doc(chatId);

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => ChatScreen(
          currentUserId: me.uid,
          partnerId: partnerId,
          partnerName: partnerName.isEmpty ? 'Driver' : partnerName,
          originRouteId: routeDocId,
          originCollection: 'routes',
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    ).then((_) => _refreshOpenChatsOnce());

    Future.microtask(() async {
      try {
        await chatRef.set({
          'participants': [me.uid, partnerId],
          'partnerName_${me.uid}': me.displayName ?? 'You',
          'partnerName_$partnerId': partnerName,
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'open',
          'originCollection': 'routes',
          'originRouteId': routeDocId,
        }, SetOptions(merge: true));
      } catch (_) {}
    });
  }

  // ---------- bubble logic (unread-only + status=open) ----------
  void _listenForOpenChatsBubble() {
    final uid = currentUserId;
    if (uid == null) return;

    _chatSub?.cancel();
    _chatSub = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: uid)
        .where('status', isEqualTo: 'open')
        .snapshots()
        .listen((snapshot) {
      final filtered = snapshot.docs.where((d) {
        final data = d.data();
        final myUnreadRaw = data['unread_$uid'];
        final myUnread =
            (myUnreadRaw is int) ? myUnreadRaw : int.tryParse('$myUnreadRaw') ?? 0;
        final hasOrigin =
            data['originRouteId'] != null || data['originCollection'] != null;
        return hasOrigin && myUnread > 0;
      }).toList();

      _primeNameCacheForOpenChats(filtered);
      setState(() => _openChatDocs = filtered);
    });
  }

  Future<void> _refreshOpenChatsOnce() async {
    final uid = currentUserId;
    if (uid == null) return;

    final snap = await FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: uid)
        .where('status', isEqualTo: 'open')
        .get();

    final filtered = snap.docs.where((d) {
      final data = d.data();
      final myUnreadRaw = data['unread_$uid'];
      final myUnread =
          (myUnreadRaw is int) ? myUnreadRaw : int.tryParse('$myUnreadRaw') ?? 0;
      final hasOrigin =
          data['originRouteId'] != null || data['originCollection'] != null;
      return hasOrigin && myUnread > 0;
    }).toList();

    _primeNameCacheForOpenChats(filtered);
    if (!mounted) return;
    setState(() => _openChatDocs = filtered);
  }

  void _primeNameCacheForOpenChats(
      List<DocumentSnapshot<Map<String, dynamic>>> docs) {
    for (final doc in docs) {
      final data = doc.data() ?? {};
      final participants =
          (data['participants'] as List?)?.cast<String>() ?? const [];
      final otherId =
          participants.firstWhere((id) => id != currentUserId, orElse: () => '');
      if (otherId.isEmpty) continue;

      final inDoc = (data['partnerName_$otherId'] ?? '').toString().trim();
      if (inDoc.isNotEmpty && inDoc.toLowerCase() != 'driver') {
        _nameCache[otherId] = inDoc;
        continue;
      }

      if (!_nameCache.containsKey(otherId)) {
        FirebaseFirestore.instance
            .collection('partners')
            .doc(otherId)
            .get()
            .then((snap) async {
          final fetched =
              (snap.data()?['partnerName'] ?? '').toString().trim();
          if (fetched.isNotEmpty) {
            _nameCache[otherId] = fetched;
            await FirebaseFirestore.instance
                .collection('chats')
                .doc(doc.id)
                .set({'partnerName_$otherId': fetched}, SetOptions(merge: true));
            if (mounted) setState(() {});
          }
        });
      }
    }
  }

  String _displayNameFor(Map<String, dynamic> data, String otherId) {
    final fromDoc = (data['partnerName_$otherId'] ?? '').toString().trim();
    if (fromDoc.isNotEmpty && fromDoc.toLowerCase() != 'driver') return fromDoc;
    final cached = _nameCache[otherId];
    if (cached != null && cached.isNotEmpty) return cached;
    return 'Driver';
  }

  void _onTapBubble() {
    if (_openChatDocs.isEmpty || currentUserId == null) return;

    if (_openChatDocs.length == 1) {
      _openChatFromDoc(_openChatDocs.first);
      return;
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Active chats'),
        content: SizedBox(
          width: 360,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _openChatDocs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final doc = _openChatDocs[i];
              final data = doc.data() ?? {};
              final participants =
                  (data['participants'] as List?)?.cast<String>() ?? const [];
              final otherId =
                  participants.firstWhere((id) => id != currentUserId, orElse: () => '');
              final displayName =
                  otherId.isEmpty ? 'Driver' : _displayNameFor(data, otherId);

              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(displayName),
                subtitle: data['lastMessage'] != null
                    ? Text(
                        data['lastMessage'].toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : null,
                onTap: () async {
                  Navigator.pop(context);
                  await _openChatFromDoc(doc);
                  await _refreshOpenChatsOnce();
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))
        ],
      ),
    );
  }

  Future<void> _openChatFromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) async {
    final uid = currentUserId;
    if (uid == null) return;

    final data = doc.data() ?? {};
    final participants =
        (data['participants'] as List?)?.cast<String>() ?? const [];
    final partnerId = participants.firstWhere((id) => id != uid, orElse: () => '');
    if (partnerId.isEmpty) return;

    final partnerName = _displayNameFor(data, partnerId);

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => ChatScreen(
          currentUserId: uid,
          partnerId: partnerId,
          partnerName: partnerName,
          originRouteId: (data['originRouteId'] ?? '').toString().isEmpty
              ? null
              : (data['originRouteId'] as String),
          originCollection: (data['originCollection'] ?? 'routes').toString(),
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    ).then((_) => _refreshOpenChatsOnce());
  }

  // ---------- UI helpers ----------
  Widget _meta({required IconData icon, required String text}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade700),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: Colors.grey.shade800)),
      ],
    );
  }

  Widget _buildPlaceAutocompleteField({
    required String label,
    required TextEditingController controller,
    bool asFormField = false,
    bool requiredField = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Autocomplete<String>(
        optionsBuilder: (v) {
          if (v.text.isEmpty) return const Iterable<String>.empty();
          return indianPlaces.where(
            (p) => p.toLowerCase().contains(v.text.toLowerCase()),
          );
        },
        onSelected: (s) => controller.text = s,
        fieldViewBuilder:
            (context, textController, focusNode, onFieldSubmitted) {
          textController.text = controller.text;

          final decoration = const InputDecoration(
            labelText: '',
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
          ).copyWith(labelText: label);

          if (asFormField) {
            return TextFormField(
              controller: textController,
              focusNode: focusNode,
              decoration: decoration,
              onChanged: (val) => controller.text = val,
              validator: (v) =>
                  (requiredField && (v == null || v.trim().isEmpty))
                      ? 'Required'
                      : null,
            );
          }

          return TextField(
            controller: textController,
            focusNode: focusNode,
            decoration: decoration,
            onChanged: (val) => controller.text = val,
          );
        },
      ),
    );
  }

  Widget _buildDatePickerField(
      BuildContext context, String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GestureDetector(
        onTap: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: now,
            firstDate: DateTime(2020),
            lastDate: DateTime(2035),
            helpText: 'Select $label',
          );
          if (picked != null) {
            final dd = picked.day.toString().padLeft(2, '0');
            final mm = picked.month.toString().padLeft(2, '0');
            final yyyy = picked.year.toString();
            controller.text = '$dd-$mm-$yyyy';
            setState(() {});
          }
        },
        child: AbsorbPointer(
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Date',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
            readOnly: true,
          ),
        ),
      ),
    );
  }

  Widget _buildDatePickerFormField({
    required BuildContext context,
    required String label,
    required TextEditingController controller,
    bool requiredField = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: controller,
        readOnly: true,
        decoration: const InputDecoration(
          labelText: 'Date',
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
        validator: (v) =>
            (requiredField && (v == null || v.trim().isEmpty)) ? 'Required' : null,
        onTap: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: now,
            firstDate: DateTime(2020),
            lastDate: DateTime(2035),
            helpText: 'Select $label',
          );
          if (picked != null) {
            final dd = picked.day.toString().padLeft(2, '0');
            final mm = picked.month.toString().padLeft(2, '0');
            final yyyy = picked.year.toString();
            controller.text = '$dd-$mm-$yyyy';
            setState(() {});
          }
        },
      ),
    );
  }

  Widget _buildTimePickerFormField({
    required BuildContext context,
    required String label,
    required TextEditingController controller,
    bool requiredField = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: controller,
        readOnly: true,
        decoration: const InputDecoration(
          labelText: 'Time',
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
        validator: (v) =>
            (requiredField && (v == null || v.trim().isEmpty)) ? 'Required' : null,
        onTap: () async {
          final picked = await showTimePicker(
            context: context,
            initialTime: TimeOfDay.now(),
            helpText: 'Select $label',
          );
          if (picked != null) {
            controller.text = picked.format(context);
            setState(() {});
          }
        },
      ),
    );
  }

  // ---------- route card ----------
  Widget _routeCard({
    required String docId,
    required Map<String, dynamic> data,
    required bool isOwnRoute,
  }) {
    final partnerName = (data['partnerName'] ?? 'Unknown Partner').toString();
    final from = (data['from'] ?? '').toString();
    final to = (data['to'] ?? '').toString();
    final date = (data['date'] ?? '').toString();
    final time = (data['time'] ?? '').toString();
    final vehicleMake = (data['vehicleMake'] ?? '').toString();
    final vehicleType = (data['vehicleType'] ?? '').toString();
    final partnerId = (data['partnerId'] ?? '').toString();

    final isNoCar = vehicleType.toLowerCase().trim() == 'no car';

    final myId = FirebaseAuth.instance.currentUser?.uid;
    final bool dealClosedGlobal = data['dealClosed'] == true;
    final Map<String, dynamic> dealWithRaw =
        (data['dealClosedWith'] is Map)
            ? (data['dealClosedWith'] as Map).map(
                (k, v) => MapEntry(k.toString(), v),
              )
            : <String, dynamic>{};
    final bool dealClosedForMe =
        dealClosedGlobal || (myId != null && (dealWithRaw[myId] == true));

    return Card(
      color: isNoCar ? Colors.amber.shade50 : null,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      elevation: isNoCar ? 6 : 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isNoCar
            ? BorderSide(color: Colors.amber.shade300, width: 1)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.directions_car, color: Colors.indigo),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    partnerName.isEmpty ? 'Unknown Partner' : partnerName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (dealClosedForMe)
                  Chip(
                    label: const Text('Deal closed'),
                    avatar: const Icon(Icons.check_circle,
                        size: 18, color: Colors.green),
                    labelStyle: const TextStyle(
                        color: Colors.green, fontWeight: FontWeight.w600),
                    backgroundColor: Colors.green.shade50,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  )
                else if (isNoCar)
                  Chip(
                    label: const Text('Need a Cab'),
                    avatar: const Icon(Icons.local_taxi,
                        size: 18, color: Colors.orange),
                    labelStyle: const TextStyle(
                        color: Colors.orange, fontWeight: FontWeight.w600),
                    backgroundColor: Colors.orange.shade50,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 6),

            Text("$from → $to",
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 6),

            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                if (date.isNotEmpty) _meta(icon: Icons.event, text: date),
                if (time.isNotEmpty) _meta(icon: Icons.access_time, text: time),
                if (vehicleMake.isNotEmpty || vehicleType.isNotEmpty)
                  _meta(
                    icon: Icons.directions_car_filled,
                    text: isNoCar
                        ? (data['requestedVehicleType']?.toString().isNotEmpty ==
                                true
                            ? 'Needs: ${data['requestedVehicleType']}'
                            : 'No car')
                        : (vehicleMake.isEmpty
                            ? vehicleType
                            : "$vehicleMake ($vehicleType)"),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                if (!isOwnRoute && !dealClosedForMe)
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text("Chat with partner"),
                      onPressed: () => _startChatWithPartnerFromRoute(
                        routeDocId: docId,
                        partnerId: partnerId,
                        partnerName:
                            partnerName.isEmpty ? 'Driver' : partnerName,
                      ),
                    ),
                  ),
                if (isOwnRoute)
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text("Delete"),
                      onPressed: () => _deleteRoute(context, docId),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteRoute(BuildContext context, String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Route"),
        content: const Text("Are you sure you want to delete this route?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Delete",
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseFirestore.instance.collection('routes').doc(docId).delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Route deleted")));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // KeepAlive
    return Stack(
      children: [
        Column(
          children: [
            // Top actions in ONE line (3 equal buttons)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 16, right: 16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _showFilterDialog,
                      icon: const Icon(Icons.filter_alt),
                      label: const Text('Filter'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _clearFilter,
                      child: const Text('Reset'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _openRequestCabDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade600,
                        foregroundColor: Colors.white,
                      ),
                      child: const Icon(Icons.local_taxi),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('routes')
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }

                  final docs = snapshot.data?.docs ?? [];

                  // Apply filters
                  final filtered = docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;

                    final toStr   = (data['to']?.toString() ?? '');
                    final dateStr = (data['date']?.toString() ?? '');
                    final vehicleType =
                        (data['vehicleType']?.toString() ?? '')
                            .toLowerCase()
                            .trim();
                    final isNoCab =
                        vehicleType == 'no car' || (data['isNoCab'] == true);

                    bool okTo = true;
                    if (_toFilter.text.isNotEmpty) {
                      final toLower   = toStr.toLowerCase();
                      final typedTo   = _toFilter.text.trim().toLowerCase();
                      final toSet     = _expandedToCandidates
                          .map((e) => e.toLowerCase())
                          .toSet();

                      okTo = toLower.contains(typedTo) || toSet.contains(toLower);
                    }

                    final okDate = _dateFilter.text.isEmpty ||
                        dateStr
                            .toLowerCase()
                            .contains(_dateFilter.text.toLowerCase());

                    final okNoCab = !_filterNoCabOnly || isNoCab;

                    return okTo && okDate && okNoCab;
                  }).toList();

                  if (filtered.isEmpty) {
                    return const Center(child: Text("No matching routes."));
                  }

                  // Put “no car” at top
                  final List<QueryDocumentSnapshot> noCar = [];
                  final List<QueryDocumentSnapshot> others = [];
                  for (final d in filtered) {
                    final vt = ((d.data() as Map<String, dynamic>)['vehicleType'] ?? '')
                        .toString()
                        .toLowerCase()
                        .trim();
                    if (vt == 'no car') {
                      noCar.add(d);
                    } else {
                      others.add(d);
                    }
                  }
                  final ordered = <QueryDocumentSnapshot>[...noCar, ...others];

                  final myId = FirebaseAuth.instance.currentUser?.uid;
                  return ListView.builder(
                    itemCount: ordered.length,
                    cacheExtent: 800,
                    itemBuilder: (context, index) {
                      final doc = ordered[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final isOwnRoute =
                          myId != null && myId == data['partnerId'];
                      return _routeCard(
                        docId: doc.id,
                        data: data,
                        isOwnRoute: isOwnRoute,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),

        // Unread bubble
        if (_openChatDocs.isNotEmpty)
          Positioned(
            bottom: 20,
            right: 20,
            child: GestureDetector(
              onTap: _onTapBubble,
              child: CircleAvatar(
                radius: 28,
                backgroundColor: Colors.red,
                child: Text(
                  _openChatDocs.length.toString(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/* ===========================
 *        PUBLISH TAB
 * =========================== */

class PublishTab extends StatefulWidget {
  const PublishTab({super.key});
  @override
  State<PublishTab> createState() => _PublishTabState();
}

class _PublishTabState extends State<PublishTab> {
  final _formKey = GlobalKey<FormState>();

  final _routeController = TextEditingController(); // (kept for compatibility)
  final _vehicleTypeController = TextEditingController();
  final _vehicleMakeController = TextEditingController();
  final _seatingController = TextEditingController();
  final _dateController = TextEditingController();
  final _timeController = TextEditingController();
  final _fromController = TextEditingController();
  final _toController = TextEditingController();

  bool _addToFavorite = false;
  bool _isLoading = false;

  Future<void> _submitData() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not signed in')),
        );
        return;
      }

      final uid = user.uid;
      final partnerName =
          (user.displayName ?? '').trim().isNotEmpty ? user.displayName!.trim() : 'Unknown Partner';

      // 🔐 IMPORTANT: include partnerId == auth.uid to satisfy your Firestore rules
      final routeData = {
        'vehicleType': _vehicleTypeController.text.trim(),
        'vehicleMake': _vehicleMakeController.text.trim(),
        'seatingCapacity': int.tryParse(_seatingController.text.trim()) ?? 0,
        'date': _dateController.text.trim(),
        'time': _timeController.text.trim(),
        'from': _fromController.text.trim(),
        'to': _toController.text.trim(),
        'status': 'Available',
        'availableForExchange': false,
        'timestamp': FieldValue.serverTimestamp(),
        'partnerName': partnerName,
        'partnerId': uid, // ✅ required by rules
      };

      await FirebaseFirestore.instance.collection('routes').add(routeData);

      if (_addToFavorite) {
        await FirebaseFirestore.instance.collection('favoriteRoutes').add({
          'uid': uid, // your favoriteRoutes rule requires this to match auth.uid
          'route': _routeController.text.trim(),
          'vehicleType': _vehicleTypeController.text.trim(),
          'vehicleMake': _vehicleMakeController.text.trim(),
          'seatingCapacity': int.tryParse(_seatingController.text.trim()) ?? 0,
          'date': _dateController.text.trim(),
          'time': _timeController.text.trim(),
          'from': _fromController.text.trim(),
          'to': _toController.text.trim(),
          'status': 'Available',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Route published successfully!")),
      );

      _formKey.currentState!.reset();
      _vehicleTypeController.clear();
      _vehicleMakeController.clear();
      _seatingController.clear();
      _dateController.clear();
      _timeController.clear();
      _fromController.clear();
      _toController.clear();

      setState(() {
        _addToFavorite = false;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              color: Colors.orange.shade100,
              elevation: 3,
              child: ListTile(
                leading: const Icon(Icons.favorite, color: Colors.red),
                title: const Text('Favorite Routes'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const FavoriteRoutesScreen()),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Route Info", style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      buildPlaceAutocompleteField(label: "From", controller: _fromController),
                      buildPlaceAutocompleteField(label: "To", controller: _toController),

                      // Date
                      GestureDetector(
                        onTap: () async {
                          final pickedDate = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2023),
                            lastDate: DateTime(2030),
                          );
                          if (pickedDate != null) {
                            _dateController.text =
                                "${pickedDate.day.toString().padLeft(2, '0')}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.year}";
                          }
                        },
                        child: AbsorbPointer(child: _buildTextField(_dateController, "Date")),
                      ),

                      // Time
                      GestureDetector(
                        onTap: () async {
                          final pickedTime = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.now(),
                          );
                          if (pickedTime != null) {
                            _timeController.text = pickedTime.format(context);
                          }
                        },
                        child: AbsorbPointer(child: _buildTextField(_timeController, "Time")),
                      ),

                      const SizedBox(height: 20),
                      const Text("Vehicle Type", style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: _vehicleTypeController.text.isNotEmpty ? _vehicleTypeController.text : null,
                        decoration: const InputDecoration(labelText: 'Select Vehicle Type', border: OutlineInputBorder()),
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(value: '4+1 hatchback - 4+1 seater', child: Text('4+1 hatchback - 4+1 seater')),
                          DropdownMenuItem(value: '4+1 sedan - 4+1 seater', child: Text('4+1 sedan - 4+1 seater')),
                          DropdownMenuItem(value: '4+1 suv - 4+1 seater', child: Text('4+1 suv - 4+1 seater')),
                          DropdownMenuItem(value: '6+1 seater other than innova Crysta', child: Text('6+1 seater other than innova Crysta')),
                          DropdownMenuItem(value: '6+1 innova Crysta', child: Text('6+1 innova Crysta')),
                          DropdownMenuItem(value: '7+1 innova Crysta', child: Text('7+1 innova Crysta')),
                          DropdownMenuItem(value: 'No car', child: Text('No car')),
                        ],
                        onChanged: (value) => _vehicleTypeController.text = value ?? '',
                        validator: (v) => (v == null || v.isEmpty) ? 'Select vehicle type' : null,
                      ),

                      const SizedBox(height: 10),
                      SwitchListTile(
                        title: const Text("Add as Favorite Route"),
                        value: _addToFavorite,
                        onChanged: (value) => setState(() => _addToFavorite = value),
                      ),

                      const SizedBox(height: 20),
                      _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.publish),
                                onPressed: _submitData,
                                label: const Text("Publish Route"),
                              ),
                            ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    bool isNumber = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        validator: (value) {
          if (value == null || value.isEmpty) return 'Required';
          if (isNumber && int.tryParse(value) == null) return 'Enter a number';
          return null;
        },
      ),
    );
  }
}

/* ===========================
 *        EXCHANGE TAB
 * =========================== */

class ExchangeTab extends StatefulWidget {
  const ExchangeTab({super.key});
  @override
  State<ExchangeTab> createState() => _ExchangeTabState();
}

class _ExchangeTabState extends State<ExchangeTab>
    with AutomaticKeepAliveClientMixin<ExchangeTab> {
  @override
  bool get wantKeepAlive => true;
  final Map<String, VoidCallback> controllerListenerMap = {};
  final _vehicleFieldKey = GlobalKey<FormFieldState<String>>();

  final _formKey = GlobalKey<FormState>();

  // 👇 make them re-creatable
  late TextEditingController _fromController;
  late TextEditingController _toController;
  late TextEditingController _dateController;
  late TextEditingController _timeController;

  final TextEditingController _fromFilter = TextEditingController();
  final TextEditingController _toFilter = TextEditingController();

  String? _selectedVehicleType;
  bool _isLoading = false;

  // used to force-rebuild form internals (Autocomplete/Dropdown)
  int _formResetSeed = 0;

  final List<String> _vehicleTypes = const [
    '4+1 hatchback - 4+1 seater',
    '4+1 sedan - 4+1 seater',
    '4+1 suv - 4+1 seater',
    '6+1 seater other than innova Crysta',
    '6+1 innova Crysta',
    '7+1 innova Crysta',
  ];

  @override
  void initState() {
    super.initState();
    _fromController = TextEditingController();
    _toController = TextEditingController();
    _dateController = TextEditingController();
    _timeController = TextEditingController();
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    _fromFilter.dispose();
    _toFilter.dispose();
    super.dispose();
  }

  // ---------- filter dialog ----------
  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter Exchange Routes'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildFilterAutoField("From", _fromFilter, indianPlaces),
              _buildFilterAutoField("To", _toFilter, indianPlaces),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              setState(() {});
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
            child: const Text("Apply"),
          ),
          ElevatedButton(
            onPressed: () {
              _fromFilter.clear();
              _toFilter.clear();
              setState(() {});
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
            child: const Text("Reset"),
          ),
        ],
      ),
    );
  }

  // ---------- autocomplete fields ----------
  Widget _buildAutoField(
    String label,
    TextEditingController controller,
    List<String> options,
    String keyId,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Autocomplete<String>(
        key: ValueKey('auto-$keyId-$_formResetSeed'),
        optionsBuilder: (TextEditingValue v) {
          if (v.text.isEmpty) return const Iterable<String>.empty();
          final q = v.text.toLowerCase();
          return options.where((o) => o.toLowerCase().contains(q));
        },
        onSelected: (s) => controller.text = s,
        fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
          // keep internal + external controllers in sync
          textController.text = controller.text;
          textController.removeListener(controllerListenerMap[keyId] ?? () {});
          final listener = () => controller.text = textController.text;
          textController.addListener(listener);
          controllerListenerMap[keyId] = listener;

          return TextFormField(
            key: ValueKey('$keyId-field-$_formResetSeed'),
            controller: textController, // <-- use Autocomplete's controller
            focusNode: focusNode,
            decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            onFieldSubmitted: (_) => onFieldSubmitted(),
          );
        },
      ),
    );
  }

  Widget _buildFilterAutoField(
    String label,
    TextEditingController controller,
    List<String> options,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Autocomplete<String>(
        optionsBuilder: (TextEditingValue v) {
          if (v.text.isEmpty) return const Iterable<String>.empty();
          final q = v.text.toLowerCase();
          return options.where((o) => o.toLowerCase().contains(q));
        },
        onSelected: (s) => controller.text = s,
        fieldViewBuilder: (context, _ignored, focusNode, onFieldSubmitted) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
            onSubmitted: (_) => onFieldSubmitted(),
          );
        },
      ),
    );
  }

  // ---------- chat helpers ----------
  String _chatIdStable(String a, String b) => a.hashCode <= b.hashCode ? '$a-$b' : '$b-$a';

  Future<void> _startChatWithPartner({
    required String partnerId,
    required String partnerName,
    String? originRouteId,
  }) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    final chatId = _chatIdStable(me.uid, partnerId);
    final chatRef = FirebaseFirestore.instance.collection('chats').doc(chatId);

    Navigator.of(context)
        .push(PageRouteBuilder(
          pageBuilder: (_, __, ___) => ChatScreen(
            currentUserId: me.uid,
            partnerId: partnerId,
            partnerName: partnerName.isEmpty ? 'Driver' : partnerName,
            originRouteId: originRouteId,
            originCollection: 'exchangeRoutes',
          ),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ))
        .then((_) => setState(() {}));

    Future.microtask(() async {
      try {
        await chatRef.set({
          'participants': [me.uid, partnerId],
          'partnerName_${me.uid}': me.displayName ?? 'You',
          'partnerName_$partnerId': partnerName,
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'open',
          'originCollection': 'exchangeRoutes',
          if (originRouteId != null && originRouteId.isNotEmpty) 'originRouteId': originRouteId,
        }, SetOptions(merge: true));
      } catch (_) {}
    });
  }

  // ---------- submit ----------
  Future<void> _submitExchange() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not signed in')),
        );
        return;
      }

      await FirebaseFirestore.instance.collection('exchangeRoutes').add({
        'from': _fromController.text.trim(),
        'to': _toController.text.trim(),
        'date': _dateController.text.trim(),
        'time': _timeController.text.trim(),
        'vehicleType': _selectedVehicleType ?? 'no car',
        'partnerId': user.uid,
        'partnerName': (user.displayName ?? '').trim().isEmpty
            ? 'Unknown Partner'
            : user.displayName!.trim(),
        'timestamp': FieldValue.serverTimestamp(),
      });

      // --- Hard reset without disposing too early ---
      final oldFrom = _fromController;
      final oldTo   = _toController;
      final oldDate = _dateController;
      final oldTime = _timeController;

      setState(() {
        _fromController = TextEditingController();
        _toController   = TextEditingController();
        _dateController = TextEditingController();
        _timeController = TextEditingController();
        _selectedVehicleType = null;
        _formKey.currentState?.reset();
        _formResetSeed++; // forces Autocomplete/Dropdown to rebuild clean
        _vehicleFieldKey.currentState?.reset();
      });

      // drop focus so keyboards close and fields stop using old controllers
      FocusScope.of(context).unfocus();

      // dispose old controllers on the next frame (prevents “disposed” errors)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oldFrom.dispose();
        oldTo.dispose();
        oldDate.dispose();
        oldTime.dispose();

        // ensure dropdown visually clears
        _vehicleFieldKey.currentState?.didChange(null);
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Exchange route published!")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------- misc ui helpers ----------
  Widget _buildTextField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        key: ValueKey('$label-$_formResetSeed'),
        controller: controller,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        validator: (value) => value == null || value.isEmpty ? 'Required' : null,
      ),
    );
  }

  Widget _meta({required IconData icon, required String text}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade700),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: Colors.grey.shade800)),
      ],
    );
  }

  Widget _buildExchangeCard({
    required String docId,
    required Map<String, dynamic> data,
    required bool isOwnRoute,
  }) {
    final me = FirebaseAuth.instance.currentUser;
    final partnerName = (data['partnerName'] ?? 'Driver').toString();
    final partnerId = (data['partnerId'] ?? '').toString();
    final from = (data['from'] ?? '').toString();
    final to = (data['to'] ?? '').toString();
    final date = (data['date'] ?? '').toString();
    final time = (data['time'] ?? '').toString();
    final vehicleType = (data['vehicleType'] ?? '').toString();
    final dealClosed = data['dealClosed'] == true;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.indigo.shade50,
                  child: const Icon(Icons.swap_horiz, color: Colors.indigo),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    partnerName.isEmpty ? 'Unknown Partner' : partnerName,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (dealClosed)
                  Chip(
                    label: const Text('Deal closed'),
                    avatar: const Icon(Icons.check_circle, size: 18, color: Colors.green),
                    labelStyle: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
                    backgroundColor: Colors.green.shade50,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text("$from → $to", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                if (date.isNotEmpty) _meta(icon: Icons.event, text: date),
                if (time.isNotEmpty) _meta(icon: Icons.access_time, text: time),
                _meta(icon: Icons.directions_car_filled, text: vehicleType.isEmpty ? 'no car' : vehicleType),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (!isOwnRoute)
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text("Chat with partner"),
                      onPressed: () {
                        if (partnerId.isEmpty || me == null) return;
                        _startChatWithPartner(
                          partnerId: partnerId,
                          partnerName: partnerName,
                          originRouteId: docId,
                        );
                      },
                    ),
                  ),
                if (isOwnRoute)
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text("Delete"),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text("Delete Exchange Route"),
                            content: const Text("Are you sure you want to delete this exchange route?"),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
                              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await FirebaseFirestore.instance.collection('exchangeRoutes').doc(docId).delete();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Exchange route deleted")));
                        }
                      },
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              ExpansionTile(
                title: const Text("➤ Publish Exchange Route", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                children: [
                  Card(
                    key: ValueKey('form-card-$_formResetSeed'),
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            _buildAutoField('From', _fromController, indianPlaces, 'from'),
                            _buildAutoField('To', _toController, indianPlaces, 'to'),
                            GestureDetector(
                              onTap: () async {
                                final pickedDate = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime.now(),
                                  firstDate: DateTime(2023),
                                  lastDate: DateTime(2035),
                                );
                                if (pickedDate != null) {
                                  _dateController.text =
                                      "${pickedDate.day.toString().padLeft(2, '0')}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.year}";
                                }
                              },
                              child: AbsorbPointer(child: _buildTextField(_dateController, "Date")),
                            ),
                            GestureDetector(
                              onTap: () async {
                                final pickedTime = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay.now(),
                                );
                                if (pickedTime != null) {
                                  _timeController.text = pickedTime.format(context);
                                }
                              },
                              child: AbsorbPointer(child: _buildTextField(_timeController, "Time")),
                            ),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              key: _vehicleFieldKey,
                              isExpanded: true,
                              value: _selectedVehicleType,
                              decoration: const InputDecoration(labelText: 'Vehicle Type', border: OutlineInputBorder()),
                              items: _vehicleTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                              onChanged: (v) => setState(() => _selectedVehicleType = v),
                              validator: (v) => (v == null || v.isEmpty) ? 'Select a vehicle type' : null,
                            ),
                            const SizedBox(height: 12),
                            _isLoading
                                ? const CircularProgressIndicator()
                                : SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      onPressed: _submitExchange,
                                      child: const Text("Publish Exchange"),
                                    ),
                                  ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.filter_alt),
                    label: const Text("Filter"),
                    onPressed: _showFilterDialog,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    child: const Text("Reset"),
                    onPressed: () {
                      _fromFilter.clear();
                      _toFilter.clear();
                      setState(() {});
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text("All Exchange Routes", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),

              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('exchangeRoutes')
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Text('Error: ${snapshot.error}');
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Text("No exchange routes yet.");
                  }

                  final filteredDocs = snapshot.data!.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final from = (data['from'] ?? '').toString().toLowerCase();
                    final to = (data['to'] ?? '').toString().toLowerCase();
                    final fFrom = _fromFilter.text.toLowerCase();
                    final fTo = _toFilter.text.toLowerCase();
                    final okFrom = fFrom.isEmpty || from.contains(fFrom);
                    final okTo = fTo.isEmpty || to.contains(fTo);
                    return okFrom && okTo;
                  }).toList();

                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filteredDocs.length,
                    itemBuilder: (context, index) {
                      final doc = filteredDocs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final isOwnRoute = data['partnerId'] == currentUserId;

                      return _buildExchangeCard(
                        docId: doc.id,
                        data: data,
                        isOwnRoute: isOwnRoute,
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ===========================
 *     ACTIVE CHATS SCREEN
 * =========================== */

class ActiveChatsScreen extends StatelessWidget {
  const ActiveChatsScreen({super.key});

  String _otherId(List participants, String myId) {
    final list = participants.map((e) => e.toString()).toList();
    for (final id in list) {
      if (id != myId) return id;
    }
    return '';
    }

  String _displayName(Map<String, dynamic> data, String otherId) {
    final fromDoc = (data['partnerName_$otherId'] ?? '').toString().trim();
    if (fromDoc.isNotEmpty && fromDoc.toLowerCase() != 'driver') {
      return fromDoc;
    }
    return 'Driver';
  }

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;
    final myId = me?.uid;
    if (myId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Active Chats')),
        body: const Center(child: Text('Not signed in')),
      );
    }

    final query = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: myId)
        .where('status', isEqualTo: 'open')
        .orderBy('createdAt', descending: true);

    return Scaffold(
      appBar: AppBar(title: const Text('Active Chats')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('No active chats'));
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final doc = docs[i];
              final data = doc.data();
              final participants = (data['participants'] as List?) ?? const [];
              final otherId = _otherId(participants, myId);
              final partnerName = otherId.isEmpty ? 'Driver' : _displayName(data, otherId);

              final lastMsg = (data['lastMessage'] ?? '').toString();
              final unreadRaw = data['unread_$myId'];
              final unread = (unreadRaw is int) ? unreadRaw : int.tryParse('$unreadRaw') ?? 0;

              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(partnerName),
                subtitle: lastMsg.isEmpty
                    ? null
                    : Text(lastMsg, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: (unread > 0)
                    ? CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.red,
                        child: Text(
                          unread.toString(),
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      )
                    : null,
                onTap: () {
                  Navigator.of(context).push(
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) => ChatScreen(
                        currentUserId: myId,
                        partnerId: otherId,
                        partnerName: partnerName,
                        originRouteId: (data['originRouteId'] ?? '').toString().isEmpty
                            ? null
                            : (data['originRouteId'] as String),
                        originCollection: (data['originCollection'] ?? 'routes').toString(),
                      ),
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
