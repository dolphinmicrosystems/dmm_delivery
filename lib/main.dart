import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'config/infra_config.dart';
import 'firebase_options.dart';
import 'screens/auth/auth_gate.dart';
import 'services/push_notifications.dart';
import 'state/auth_state.dart';
import 'theme/app_theme.dart';
import 'util/app_log.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final options = DefaultFirebaseOptions.currentPlatform;
  await Firebase.initializeApp(options: options);
  // Before runApp, as Firebase requires: draws the live run notification
  // while the app is closed.
  if (!kIsWeb) FirebaseMessaging.onBackgroundMessage(pushBackgroundHandler);
  // Which environment a build is actually pointed at explains a whole class
  // of "works for me" auth/storage failures, so state it once at startup
  // rather than inferring it from a stack trace later.
  AppLog.auth('Firebase initialized', {
    'projectId': options.projectId,
    'appId': options.appId,
    'runSheetsBucket': InfraConfig.runSheetsBucket,
  });
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Blue Dot',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: AuthGate(authState: AuthState()),
    );
  }
}
