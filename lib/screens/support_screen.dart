import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  void _launchPhone(BuildContext context) async {
    final Uri url = Uri(scheme: 'tel', path: '9815820541');
    try {
      final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!launched) throw 'Could not open phone dialer';
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open phone dialer')),
      );
    }
  }

  void _launchEmail(BuildContext context) async {
    final Uri url = Uri(
      scheme: 'mailto',
      path: 'jepdprimeworks@gmail.com',
      queryParameters: {
        'subject': 'Support Needed',
        'body': 'Hi, I need help with...',
      },
    );

    try {
      // Force open in Gmail or default email app
      final launched = await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) throw 'No email app found';
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open email app')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Support')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Need Help?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'If you’re facing any issues or need assistance, feel free to contact our support team using the options below.',
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.call),
            title: const Text('Call Support'),
            onTap: () => _launchPhone(context),
          ),
          ListTile(
            leading: const Icon(Icons.email),
            title: const Text('Email Support'),
            onTap: () => _launchEmail(context),
          ),
        ],
      ),
    );
  }
}
