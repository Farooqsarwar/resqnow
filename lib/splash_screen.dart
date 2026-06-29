// lib/splash_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

// Mobile screens
import 'package:resqnow/screens/login.dart';
import 'package:resqnow/screens/userdashboard.dart';
import 'package:resqnow/rescue//ResponderDashboard.dart';

// Admin screens
import 'Admin/Admin_dashboard.dart';
import 'Admin/Admin_login.dart';

import '../main.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // Animations
  late Animation<double> _logoRotate;
  late Animation<double> _logoScale;
  late Animation<Offset> _logoTranslate;
  late Animation<Offset> _textParentTranslate;

  // Text letters - different for web vs mobile
  List<String> get _letters => kIsWeb
      ? ['R', 'e', 's', 'Q', 'n', 'o', 'w', ' ', 'A', 'd', 'm', 'i', 'n']
      : ['R', 'e', 's', 'Q', 'n', 'o', 'w'];

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: kIsWeb ? 2500 : 3500),
    );

    _logoRotate = Tween<double>(begin: 0.0, end: 2 * 3.14159).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOutCubic),
      ),
    );

    _logoScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOutCubic),
      ),
    );

    _logoTranslate = Tween<Offset>(
      begin: Offset.zero,
      end: Offset(kIsWeb ? -140 : -100, 0),
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 0.6, curve: Curves.easeInOutCubic),
      ),
    );

    _textParentTranslate = Tween<Offset>(
      begin: const Offset(80, 0),
      end: const Offset(20, 0),
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 0.6, curve: Curves.linear),
      ),
    );

    _controller.forward().then((_) {
      _handleNavigation();
    });
  }

  Future<void> _handleNavigation() async {
    Widget nextScreen;

    // ============ WEB → ADMIN ONLY ============
    if (kIsWeb) {
      nextScreen = await _handleWebNavigation();
    }
    // ============ MOBILE → USER/RESCUER ============
    else {
      nextScreen = await _handleMobileNavigation();
    }

    if (mounted) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => nextScreen,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  /// WEB: Only Admin Login / Admin Dashboard
  Future<Widget> _handleWebNavigation() async {
    final supabase = Supabase.instance.client;
    final session = supabase.auth.currentSession;

    // No session → Admin Login
    if (session == null) {
      return const AdminLogin();
    }

    // Has session → Check if admin
    try {
      final profile = await supabase
          .from('profiles')
          .select('role')
          .eq('id', session.user.id)
          .maybeSingle();

      final role = profile?['role'] ?? 'user';

      if (role == 'admin') {
        return const AdminDashboard();
      } else {
        // Not admin → Sign out and go to Admin Login
        await supabase.auth.signOut();
        _showAdminOnlyMessage();
        return const AdminLogin();
      }
    } catch (e) {
      await supabase.auth.signOut();
      return const AdminLogin();
    }
  }

  /// MOBILE: User Login / User Dashboard / Rescuer Dashboard
  Future<Widget> _handleMobileNavigation() async {
    final supabase = Supabase.instance.client;
    final session = supabase.auth.currentSession;

    // No session → Login
    if (session == null) {
      return const LoginScreen();
    }

    // Has session → Check role
    try {
      final profile = await supabase
          .from('profiles')
          .select('role')
          .eq('id', session.user.id)
          .maybeSingle();

      final role = profile?['role'] ?? 'user';

      if (role == 'rescuer' || role == 'admin') {
        return const ResponderDashboardScreen();
      } else {
        return const UserDashboard();
      }
    } catch (e) {
      await supabase.auth.signOut();
      return const LoginScreen();
    }
  }

  void _showAdminOnlyMessage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.white),
                SizedBox(width: 12),
                Text('Web portal is for admin access only'),
              ],
            ),
            backgroundColor: Colors.orange.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color primary = RescueApp.primaryColor;
    final Color background = RescueApp.backgroundDark;

    return Scaffold(
      backgroundColor: background,
      body: Stack(
        children: [
          // Background gradient for web
          if (kIsWeb)
            Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.5,
                  colors: [
                    primary.withOpacity(0.1),
                    background,
                  ],
                ),
              ),
            ),

          // Main Content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 120,
                  width: double.infinity,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Logo
                      AnimatedBuilder(
                        animation: _controller,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: _logoTranslate.value,
                            child: Transform.rotate(
                              angle: _logoRotate.value,
                              child: Transform.scale(
                                scale: _logoScale.value,
                                child: child,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: primary.withOpacity(0.3),
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: Icon(
                            kIsWeb ? Icons.admin_panel_settings : Icons.local_hospital,
                            color: primary,
                            size: kIsWeb ? 72 : 64,
                          ),
                        ),
                      ),

                      // Text
                      AnimatedBuilder(
                        animation: _textParentTranslate,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: _textParentTranslate.value,
                            child: child,
                          );
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(_letters.length, (index) {
                            double start = 0.45 + (index * 0.03);
                            double end = (start + 0.10).clamp(0.0, 1.0);

                            return _IndividualLetter(
                              letter: _letters[index],
                              controller: _controller,
                              start: start,
                              end: end,
                              primaryColor: primary,
                              isWeb: kIsWeb,
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ),

                // Web subtitle
                if (kIsWeb) ...[
                  const SizedBox(height: 24),
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      final opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
                        CurvedAnimation(
                          parent: _controller,
                          curve: const Interval(0.7, 0.9),
                        ),
                      );
                      return Opacity(opacity: opacity.value, child: child);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(
                        color: primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: primary.withOpacity(0.3)),
                      ),
                      child: Text(
                        'CONTROL CENTER',
                        style: TextStyle(
                          color: primary.withOpacity(0.8),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 4,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Loading indicator
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
                  CurvedAnimation(
                    parent: _controller,
                    curve: const Interval(0.8, 1.0),
                  ),
                );
                return Opacity(opacity: opacity.value, child: child);
              },
              child: Column(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(primary.withOpacity(0.5)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    kIsWeb ? 'Loading Admin Portal...' : 'Loading...',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Version
          Positioned(
            bottom: 20,
            right: 20,
            child: Text(
              'v1.0.0',
              style: TextStyle(
                color: Colors.white.withOpacity(0.2),
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IndividualLetter extends StatelessWidget {
  final String letter;
  final AnimationController controller;
  final double start;
  final double end;
  final Color primaryColor;
  final bool isWeb;

  const _IndividualLetter({
    required this.letter,
    required this.controller,
    required this.start,
    required this.end,
    required this.primaryColor,
    this.isWeb = false,
  });

  @override
  Widget build(BuildContext context) {
    final Animation<double> opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: controller, curve: Interval(start, end)),
    );

    final Animation<Offset> translate = Tween<Offset>(
      begin: const Offset(20, 0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: controller, curve: Interval(start, end)),
    );

    if (letter == ' ') {
      return const SizedBox(width: 8);
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Opacity(
          opacity: opacity.value,
          child: Transform.translate(
            offset: translate.value,
            child: Text(
              letter,
              style: TextStyle(
                fontSize: isWeb ? 28 : 26,
                color: primaryColor,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ),
        );
      },
    );
  }
}