import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'firebase_options.dart';
import 'core/app_theme.dart';
import 'services/user_service.dart';
import 'services/purchase_service.dart';          // ← ADD THIS IMPORT
import 'screens/auth/login_screen.dart';
import 'services/notification_service.dart';
import 'screens/main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppTheme.setSystemUI();

  await JustAudioBackground.init(
    androidNotificationChannelId:           'com.gotitmaderecords.app.audio',
    androidNotificationChannelName:         'YITADEE Music',
    androidNotificationIcon:                'mipmap/ic_launcher',
    androidNotificationOngoing:             true,
    androidStopForegroundOnPause:           true,
    androidNotificationClickStartsActivity: true,
    notificationColor:                      const Color(0xFFFFB800),
  );

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await NotificationService.instance.init();

  await UserService.instance.loadFromCache();

  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser != null && !UserService.instance.isLoaded) {
    await UserService.instance.loadFromFirestore();
  }

  // ← Init purchases AFTER Firebase + Auth are ready
  // Only loads the locker if the user is already logged in
  await PurchaseService.instance.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YITADEE',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: FirebaseAuth.instance.currentUser != null
          ? const MainScreen()
          : const LoginScreen(),
    );
  }
}