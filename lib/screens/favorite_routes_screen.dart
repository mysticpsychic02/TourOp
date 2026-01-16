import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FavoriteRoutesScreen extends StatelessWidget {
  const FavoriteRoutesScreen({super.key});

  Future<void> _publishRoute(BuildContext context, Map<String, dynamic> route) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Publish this route?"),
        content: const Text("Are you sure you want to publish this favorite route?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Yes")),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final uid = FirebaseAuth.instance.currentUser!.uid;
        final phone = FirebaseAuth.instance.currentUser?.phoneNumber?.replaceAll('+1', '') ?? '';

        String partnerName = 'Unknown';

        final query = await FirebaseFirestore.instance
            .collection('partners')
            .where('mobileNumber', isEqualTo: phone)
            .limit(1)
            .get();

        if (query.docs.isNotEmpty) {
          partnerName = query.docs.first.data()['partnerName'] ?? 'Unknown';
        }

        final fullRouteData = {
          ...route,
          'timestamp': Timestamp.now(),
          'partnerId': uid,
          'partnerName': partnerName,
        };


        await FirebaseFirestore.instance.collection('routes').add(fullRouteData);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Route published successfully!")),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: ${e.toString()}")),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text("Your Favorite Routes")),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('favoriteRoutes')
            .where('uid', isEqualTo: uid)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text("No favorite routes saved."));
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;

              final from = data['from'] ?? '-';
              final to = data['to'] ?? '-';
              final date = data['date'] ?? '-';
              final time = data['time'] ?? '-';
              final vehicleType = data['vehicleType'] ?? '-';
              final vehicleMake = data['vehicleMake'] ?? '-';
              final status = data['status'] ?? '-';

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  onTap: () => _publishRoute(context, data),
                  title: Text("From: $from → To: $to", style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text("Date: $date"),
                      Text("Time: $time"),
                      Text("Vehicle: $vehicleMake ($vehicleType)"),
                      Text("Status: $status"),
                    ],
                  ),
                  trailing: const Icon(Icons.publish, color: Colors.indigo),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
