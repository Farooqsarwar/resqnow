import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:resqnow/screens/signup.dart';
import 'package:resqnow/screens/userdashboard.dart';
import 'package:resqnow/rescue//ResponderDashboard.dart';
import '../main.dart';
import 'Apply.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  final SupabaseClient supabase = Supabase.instance.client;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  // --- UI Constants ---
  static const Color primary = RescueApp.primaryColor;
  static const Color fieldBg = RescueApp.fieldBackground;
  static const Color dialogBg = Color(0xFF1E1E1E);

  // --- Helper: Styled TextField ---
  Widget _buildDialogTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    bool obscure = false,
    VoidCallback? onToggle,
    bool isOtp = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: isOtp
          ? TextInputType.number
          : (isPassword ? TextInputType.text : TextInputType.emailAddress),
      maxLength: isOtp ? 6 : null,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        counterText: "",
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: Icon(icon, color: Colors.white70, size: 20),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  obscure ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white70,
                ),
                onPressed: onToggle,
              )
            : null,
        filled: true,
        fillColor: fieldBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 12,
        ),
      ),
    );
  }

  // --- Unified Login Logic ---
  Future<void> _handleLogin() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showMessage('Please fill in all fields', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final AuthResponse res = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (res.user == null) throw const AuthException('Login failed');

      final userId = res.user!.id;
      var profileData = await supabase
          .from('profiles')
          .select('role')
          .eq('id', userId)
          .maybeSingle();

      // Create basic profile if missing
      if (profileData == null) {
        final newProfile = {
          'id': userId,
          'email': email,
          'role': 'user',
          'name': email.split('@')[0],
          'updated_at': DateTime.now().toIso8601String(),
        };
        await supabase.from('profiles').insert(newProfile);
        profileData = newProfile;
      }

      final String userRole = profileData['role'] ?? 'user';
      if (!mounted) return;

      // Auto-redirect based on role
      if (userRole == 'rescuer' || userRole == 'admin') {
        _showMessage('Welcome back, Rescuer!');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ResponderDashboardScreen()),
        );
      } else {
        _showMessage('Welcome back!');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const UserDashboard()),
        );
      }
    } on AuthException catch (e) {
      _showMessage('Login failed: ${e.message}', isError: true);
    } catch (e) {
      _showMessage('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- Forgot Password Dialog ---
  void _showForgotPasswordDialog() {
    final emailCtrl = TextEditingController();
    bool isSending = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: dialogBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Reset Password',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Enter your email for a 6-digit OTP code.',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 20),
                _buildDialogTextField(
                  controller: emailCtrl,
                  hint: 'Email Address',
                  icon: Icons.email,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSending ? null : () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white60),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: isSending
                  ? null
                  : () async {
                      if (emailCtrl.text.isEmpty) return;
                      setDialogState(() => isSending = true);
                      try {
                        await supabase.auth.resetPasswordForEmail(
                          emailCtrl.text.trim(),
                        );
                        if (context.mounted) {
                          Navigator.pop(context);
                          _showOTPVerificationDialog(emailCtrl.text.trim());
                        }
                      } catch (e) {
                        _showMessage('Failed to send OTP', isError: true);
                        setDialogState(() => isSending = false);
                      }
                    },
              child: isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Send OTP'),
            ),
          ],
        ),
      ),
    );
  }

  void _showOTPVerificationDialog(String email) {
    final otpCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final confCtrl = TextEditingController();
    bool isVerifying = false;
    bool obs1 = true;
    bool obs2 = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: dialogBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Verify OTP',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Sending to $email',
                    style: const TextStyle(color: primary, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  _buildDialogTextField(
                    controller: otpCtrl,
                    hint: '6-Digit OTP',
                    icon: Icons.numbers,
                    isOtp: true,
                  ),
                  const SizedBox(height: 12),
                  _buildDialogTextField(
                    controller: passCtrl,
                    hint: 'New Password',
                    icon: Icons.lock,
                    isPassword: true,
                    obscure: obs1,
                    onToggle: () => setDialogState(() => obs1 = !obs1),
                  ),
                  const SizedBox(height: 12),
                  _buildDialogTextField(
                    controller: confCtrl,
                    hint: 'Confirm Password',
                    icon: Icons.lock_outline,
                    isPassword: true,
                    obscure: obs2,
                    onToggle: () => setDialogState(() => obs2 = !obs2),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isVerifying ? null : () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white60),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: primary),
              onPressed: isVerifying
                  ? null
                  : () async {
                      if (passCtrl.text != confCtrl.text) {
                        _showMessage('Passwords mismatch', isError: true);
                        return;
                      }
                      setDialogState(() => isVerifying = true);
                      try {
                        final res = await supabase.auth.verifyOTP(
                          type: OtpType.recovery,
                          email: email,
                          token: otpCtrl.text.trim(),
                        );
                        if (res.session != null) {
                          await supabase.auth.updateUser(
                            UserAttributes(password: passCtrl.text.trim()),
                          );
                          if (context.mounted) {
                            Navigator.pop(context);
                            _showMessage('Password reset successfully!');
                          }
                        }
                      } catch (e) {
                        _showMessage('Invalid OTP', isError: true);
                      } finally {
                        setDialogState(() => isVerifying = false);
                      }
                    },
              child: isVerifying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Reset Password'),
            ),
          ],
        ),
      ),
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                children: [
                  // Logo Section
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.local_hospital,
                      color: primary,
                      size: 64,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'ResQnow',
                    style: TextStyle(
                      color: primary,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Emergency Response System',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                  const SizedBox(height: 40),

                  // Welcome Text
                  const Text(
                    'Welcome Back',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sign in to continue',
                    style: TextStyle(color: Colors.white60, fontSize: 14),
                  ),
                  const SizedBox(height: 32),

                  // Email Field
                  _buildDialogTextField(
                    controller: emailController,
                    hint: 'Email',
                    icon: Icons.email,
                  ),
                  const SizedBox(height: 16),

                  // Password Field
                  _buildDialogTextField(
                    controller: passwordController,
                    hint: 'Password',
                    icon: Icons.lock,
                    isPassword: true,
                    obscure: _obscurePassword,
                    onToggle: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),

                  // Forgot Password
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _showForgotPasswordDialog,
                      child: const Text(
                        'Forgot Password?',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Single Login Button
                  _isLoading
                      ? const CircularProgressIndicator(color: primary)
                      : SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _handleLogin,
                            icon: const Icon(Icons.login, color: Colors.white),
                            label: const Text(
                              'Login',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),

                  const SizedBox(height: 24),

                  // Sign Up Link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "Don't have an account? ",
                        style: TextStyle(color: Colors.white60),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SignUpScreen(),
                          ),
                        ),
                        child: const Text(
                          'Sign Up',
                          style: TextStyle(
                            color: primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Divider
                  const SizedBox(height: 30),
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.white24)),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'OR',
                          style: TextStyle(color: Colors.white38),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.white24)),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Apply to be a Rescuer Button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ApplyRescuerScreen(),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.volunteer_activism,
                        color: Colors.orangeAccent,
                      ),
                      label: const Text(
                        'Apply to be a Rescuer',
                        style: TextStyle(
                          color: Colors.orangeAccent,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                          color: Colors.orangeAccent,
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Info text
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: Colors.orangeAccent,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Want to help save lives? Apply to become a certified rescuer.',
                            style: TextStyle(
                              color: Colors.orangeAccent.withOpacity(0.8),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
