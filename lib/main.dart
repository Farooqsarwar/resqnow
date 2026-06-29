import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:resqnow/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://sawjwzjtovqnuwmyrjcy.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNhd2p3emp0b3ZxbnV3bXlyamN5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ4NjU1MzksImV4cCI6MjA4MDQ0MTUzOX0.Fe3YMMbV5BQIqH9VybuoNpGYrYrmeE5Ls6qROwfwpW4',
    authOptions: FlutterAuthClientOptions(
      authFlowType: kIsWeb ? AuthFlowType.implicit : AuthFlowType.pkce,
      autoRefreshToken: !kIsWeb, // Don't auto refresh on web
    ),
  );
  // Clear any existing session on web startup
  if (kIsWeb) {
    await Supabase.instance.client.auth.signOut();
  }

  runApp(const RescueApp());
}

class RescueApp extends StatelessWidget {
  const RescueApp({super.key});

  static const Color primaryColor = Color(0xFFE43A45);
  static const Color backgroundDark = Color(0xFF211112);
  static const Color fieldBackground = Color(0x80462528);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: primaryColor,
        scaffoldBackgroundColor: backgroundDark,
        useMaterial3: true,
        textTheme: kIsWeb
            ? const TextTheme(
          bodyLarge: TextStyle(fontSize: 16),
          bodyMedium: TextStyle(fontSize: 14),
        )
            : null,
      ),
      builder: (context, child) {
        if (kIsWeb) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.0),
            ),
            child: child!,
          );
        }
        return child!;
      },
      home: const SplashScreen(),
    );
  }
}