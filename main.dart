import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';

// Use RELATIVE imports that match your real files:
import 'package:driver_connect/screens/welcome_screen.dart';
import 'package:driver_connect/screens/login_screen.dart';
import 'package:driver_connect/screens/otp_screen.dart';
import 'package:driver_connect/screens/dashboard_screen.dart';
import 'package:driver_connect/screens/profile_page.dart';
import 'package:driver_connect/screens/recharge_wallet_screen.dart';
import 'package:driver_connect/screens/chat_screen.dart';
import 'package:driver_connect/screens/account_tab.dart';
import 'package:driver_connect/screens/favorite_routes_screen.dart';
import 'package:driver_connect/screens/support_screen.dart';
import 'package:driver_connect/screens/admin_tab.dart';
import 'package:driver_connect/screens/auth_gate.dart';
import 'package:driver_connect/screens/splash_screen.dart';
import 'package:driver_connect/screens/send_money_screen.dart';
import 'package:driver_connect/screens/sign_up_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Android may auto-create the default Firebase app already.
  // So if it exists, do not create it again.
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  runApp(const MyApp());
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TourOp',
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const AuthGate(),
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/otp':
            final args = (settings.arguments as Map?) ?? {};
            return MaterialPageRoute(
              builder: (_) => OTPScreen(
                phoneNumber: (args['phoneNumber'] ?? '') as String,
                verificationId: (args['verificationId'] ?? '') as String,
                resendToken: args['resendToken'] as int?,
                countryCode: (args['countryCode'] ?? '+91') as String,
              ),
            );

          case '/dashboard':
            final a = (settings.arguments as Map?) ?? {};
            return MaterialPageRoute(
              builder: (_) => DashboardScreen(
                partnerName: (a['partnerName'] ?? '') as String,
                partnerId: (a['partnerId'] ?? '') as String,
                mobileNumber: (a['mobileNumber'] ?? '') as String,
                firmName: (a['firmName'] ?? '') as String,
                address: (a['address'] ?? '') as String,
              ),
            );

          default:
            return MaterialPageRoute(builder: (_) => const AuthGate());
        }
      },
    );
  }
}
