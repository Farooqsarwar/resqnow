import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:resqnow/screens/userdashboard.dart';
import '../main.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController otpController = TextEditingController();


  bool _isLoading = false;
  bool _obscurePassword = true;

  // Validation error messages
  String? _nameError;
  String? _phoneError;
  String? _emailError;
  String? _passwordError;

  // Password strength
  double _passwordStrength = 0;
  String _passwordStrengthText = '';
  Color _passwordStrengthColor = Colors.red;

  final SupabaseClient supabase = Supabase.instance.client;

  // Validation Constants
  static const int nameMinLength = 4;
  static const int nameMaxLength = 16;
  static const int passwordMinLength = 6;
  static const int passwordMaxLength = 15;
  static const int phoneLength = 11;

  @override
  void initState() {
    super.initState();
    // Add listeners for real-time validation
    nameController.addListener(_validateNameRealTime);
    passwordController.addListener(_validatePasswordRealTime);
    phoneController.addListener(_validatePhoneRealTime);
    emailController.addListener(_validateEmailRealTime);
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    passwordController.dispose();
    otpController.dispose();
    super.dispose();
  }

  // --- VALIDATION METHODS ---

  void _validateNameRealTime() {
    final name = nameController.text;
    setState(() {
      _nameError = _getNameError(name);
    });
  }

  void _validatePasswordRealTime() {
    final password = passwordController.text;
    setState(() {
      _passwordError = _getPasswordError(password);
      _updatePasswordStrength(password);
    });
  }

  void _validatePhoneRealTime() {
    final phone = phoneController.text;
    setState(() {
      _phoneError = _getPhoneError(phone);
    });
  }

  void _validateEmailRealTime() {
    final email = emailController.text;
    setState(() {
      _emailError = _getEmailError(email);
    });
  }

  // Name Validation
  String? _getNameError(String name) {
    if (name.isEmpty) {
      return null; // Don't show error for empty field until submit
    }
    if (name.length < nameMinLength) {
      return 'Name must be at least $nameMinLength characters';
    }
    if (name.length > nameMaxLength) {
      return 'Name cannot exceed $nameMaxLength characters';
    }
    // Only allow letters, spaces, and common name characters like hyphen and apostrophe
    if (!RegExp(r"^[a-zA-Z\s\-']+$").hasMatch(name)) {
      return 'Name can only contain letters, spaces, hyphens, and apostrophes';
    }
    // Check for consecutive spaces
    if (name.contains('  ')) {
      return 'Name cannot have consecutive spaces';
    }
    // Must start with a letter
    if (!RegExp(r'^[a-zA-Z]').hasMatch(name)) {
      return 'Name must start with a letter';
    }
    return null;
  }

  // Password Validation
  String? _getPasswordError(String password) {
    if (password.isEmpty) {
      return null;
    }
    if (password.length < passwordMinLength) {
      return 'Password must be at least $passwordMinLength characters';
    }
    if (password.length > passwordMaxLength) {
      return 'Password cannot exceed $passwordMaxLength characters';
    }
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'Password must contain at least one uppercase letter';
    }
    if (!RegExp(r'[a-z]').hasMatch(password)) {
      return 'Password must contain at least one lowercase letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(password)) {
      return 'Password must contain at least one number';
    }
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) {
      return 'Password must contain at least one special character';
    }
    // Check for spaces
    if (password.contains(' ')) {
      return 'Password cannot contain spaces';
    }
    return null;
  }

  // Phone Validation
  String? _getPhoneError(String phone) {
    if (phone.isEmpty) {
      return null;
    }
    if (!RegExp(r'^[0-9]+$').hasMatch(phone)) {
      return 'Phone number can only contain digits';
    }
    if (phone.length != phoneLength) {
      return 'Phone number must be exactly $phoneLength digits';
    }
    return null;
  }

  // Email Validation
  String? _getEmailError(String email) {
    if (email.isEmpty) {
      return null;
    }
    if (!_isValidEmail(email)) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  // Password Strength Calculator
  void _updatePasswordStrength(String password) {
    double strength = 0;

    if (password.isEmpty) {
      _passwordStrength = 0;
      _passwordStrengthText = '';
      _passwordStrengthColor = Colors.red;
      return;
    }

    // Length contribution
    if (password.length >= 8) strength += 0.2;
    if (password.length >= 12) strength += 0.1;
    if (password.length >= 16) strength += 0.1;

    // Character type contributions
    if (RegExp(r'[a-z]').hasMatch(password)) strength += 0.15;
    if (RegExp(r'[A-Z]').hasMatch(password)) strength += 0.15;
    if (RegExp(r'[0-9]').hasMatch(password)) strength += 0.15;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) strength += 0.15;

    _passwordStrength = strength.clamp(0, 1);

    if (_passwordStrength < 0.3) {
      _passwordStrengthText = 'Weak';
      _passwordStrengthColor = Colors.red;
    } else if (_passwordStrength < 0.6) {
      _passwordStrengthText = 'Fair';
      _passwordStrengthColor = Colors.orange;
    } else if (_passwordStrength < 0.8) {
      _passwordStrengthText = 'Good';
      _passwordStrengthColor = Colors.yellow;
    } else {
      _passwordStrengthText = 'Strong';
      _passwordStrengthColor = Colors.green;
    }
  }

  // Comprehensive validation check
  bool _validateAllFields() {
    final name = nameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final phone = phoneController.text.trim();

    setState(() {
      _nameError = name.isEmpty ? 'Name is required' : _getNameError(name);
      _emailError = email.isEmpty ? 'Email is required' : _getEmailError(email);
      _passwordError = password.isEmpty ? 'Password is required' : _getPasswordError(password);
      _phoneError = phone.isEmpty ? 'Phone number is required' : _getPhoneError(phone);
    });

    return _nameError == null &&
        _emailError == null &&
        _passwordError == null &&
        _phoneError == null;
  }

  // --- LOGIC SECTION ---

  Future<void> _signUp() async {
    if (!_validateAllFields()) {
      _showMessage('Please fix the errors above', isError: true);
      return;
    }

    final name = nameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final phone = phoneController.text.trim();

    setState(() => _isLoading = true);

    try {
      final AuthResponse response = await supabase.auth.signUp(
        email: email,
        password: password,
        data: {'name': name, 'phone': phone},
      );

      if (response.user == null) throw Exception('Sign up failed');

      await _createUserProfile(response.user!.id, name, email, phone);

      if (mounted) {
        _showOtpDialog(email);
      }
    } on AuthException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (e) {
      _showMessage('Error: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyOtp(String email) async {
    final token = otpController.text.trim();
    if (token.length != 6) {
      _showMessage('Please enter a valid 6-digit code', isError: true);
      return;
    }

    try {
      final AuthResponse res = await supabase.auth.verifyOTP(
        type: OtpType.signup,
        token: token,
        email: email,
      );

      if (res.session != null) {
        await supabase.from('profiles').update({'email_verified': true}).eq('id', res.user!.id);
        if (mounted) {
          Navigator.of(context).pop();
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const UserDashboard()));
        }
      }
    } catch (e) {
      _showMessage('Invalid Code', isError: true);
    }
  }

  Future<void> _createUserProfile(String userId, String name, String email, String phone) async {
    await supabase.from('profiles').upsert({
      'id': userId,
      'name': name,
      'email': email,
      'phone': phone,
      'role': 'user',
      'email_verified': false,
    });
  }

  // --- UI COMPONENTS ---

  void _showOtpDialog(String email) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Verify Account', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Enter the code sent to\n$email',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 24),
            TextField(
              controller: otpController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: Colors.white, fontSize: 32, letterSpacing: 12, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                counterText: '',
                hintText: '000000',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.1)),
                filled: true,
                fillColor: Colors.black45,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: RescueApp.primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => _verifyOtp(email),
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = RescueApp.primaryColor;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topLeft,
            radius: 1.5,
            colors: [
              RescueApp.backgroundDark.withBlue(40),
              RescueApp.backgroundDark,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Glowing Logo
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: primary.withOpacity(0.3), blurRadius: 20, spreadRadius: 5),
                      ],
                    ),
                    child: Icon(Icons.local_hospital, color: primary, size: 72),
                  ),
                  const SizedBox(height: 16),
                  Text('RESQUENOW',
                      style: TextStyle(color: primary, fontWeight: FontWeight.w900, letterSpacing: 4, fontSize: 18)),
                  const SizedBox(height: 40),

                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Create Account', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Join our rescue network today', style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.5))),
                  ),
                  const SizedBox(height: 32),

                  // Name Field with validation
                  _buildNameField(),
                  const SizedBox(height: 20),

                  // Phone Field with validation
                  _buildPhoneField(),
                  const SizedBox(height: 20),

                  // Email Field with validation
                  _buildEmailField(),
                  const SizedBox(height: 20),

                  // Password Field with validation and strength indicator
                  _buildPasswordField(),

                  const SizedBox(height: 40),

                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _isLoading ? null : _signUp,
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Sign Up', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),

                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("Already have an account? ", style: TextStyle(color: Colors.white.withOpacity(0.6))),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Text("Login", style: TextStyle(color: primary, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Name Field with character limit and validation
  Widget _buildNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: nameController,
          maxLength: nameMaxLength,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z\s\-']")),
          ],
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Full Name',
            labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
            prefixIcon: Icon(Icons.person_outline, color: RescueApp.primaryColor.withOpacity(0.7)),
            counterText: '', // Hide the counter
            suffixIcon: _nameError == null && nameController.text.isNotEmpty
                ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                : null,
            filled: true,
            fillColor: RescueApp.fieldBackground.withOpacity(0.3),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: _nameError != null ? Colors.redAccent : Colors.white.withOpacity(0.05),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: _nameError != null ? Colors.redAccent : RescueApp.primaryColor.withOpacity(0.5),
              ),
            ),
          ),
        ),
        if (_nameError != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 4),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _nameError!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        // Character count hint
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 4),
          child: Text(
            '${nameController.text.length}/$nameMaxLength characters (min $nameMinLength)',
            style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11),
          ),
        ),
      ],
    );
  }

  // Phone Field with validation
  Widget _buildPhoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: phoneController,
          keyboardType: TextInputType.phone,
          maxLength: phoneLength,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Phone Number',
            labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
            prefixIcon: Icon(Icons.phone_android_outlined, color: RescueApp.primaryColor.withOpacity(0.7)),
            counterText: '',
            suffixIcon: _phoneError == null && phoneController.text.length == phoneLength
                ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                : null,
            filled: true,
            fillColor: RescueApp.fieldBackground.withOpacity(0.3),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: _phoneError != null ? Colors.redAccent : Colors.white.withOpacity(0.05),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: _phoneError != null ? Colors.redAccent : RescueApp.primaryColor.withOpacity(0.5),
              ),
            ),
          ),
        ),
        if (_phoneError != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 4),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 14),
                const SizedBox(width: 4),
                Text(
                  _phoneError!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // Email Field with validation
  Widget _buildEmailField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Email Address',
            labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
            prefixIcon: Icon(Icons.email_outlined, color: RescueApp.primaryColor.withOpacity(0.7)),
            suffixIcon: _emailError == null && emailController.text.isNotEmpty
                ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                : null,
            filled: true,
            fillColor: RescueApp.fieldBackground.withOpacity(0.3),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: _emailError != null ? Colors.redAccent : Colors.white.withOpacity(0.05),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: _emailError != null ? Colors.redAccent : RescueApp.primaryColor.withOpacity(0.5),
              ),
            ),
          ),
        ),
        if (_emailError != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 4),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _emailError!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // Password Field with strength indicator
  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: passwordController,
          obscureText: _obscurePassword,
          maxLength: passwordMaxLength,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Password',
            labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
            prefixIcon: Icon(Icons.lock_outline, color: RescueApp.primaryColor.withOpacity(0.7)),
            counterText: '',
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_passwordError == null && passwordController.text.isNotEmpty)
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.white38),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ],
            ),
            filled: true,
            fillColor: RescueApp.fieldBackground.withOpacity(0.3),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: _passwordError != null ? Colors.redAccent : Colors.white.withOpacity(0.05),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: _passwordError != null ? Colors.redAccent : RescueApp.primaryColor.withOpacity(0.5),
              ),
            ),
          ),
        ),

        // Password Strength Indicator
        if (passwordController.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _passwordStrength,
                    backgroundColor: Colors.white.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(_passwordStrengthColor),
                    minHeight: 4,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _passwordStrengthText,
                style: TextStyle(color: _passwordStrengthColor, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],

        // Error message
        if (_passwordError != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 4),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _passwordError!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

        // Password Requirements
        const SizedBox(height: 12),
        _buildPasswordRequirements(),
      ],
    );
  }

  // Password Requirements Checklist
  Widget _buildPasswordRequirements() {
    final password = passwordController.text;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Password must contain:',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _buildRequirementChip('8+ chars', password.length >= 8),
              _buildRequirementChip('A-Z', RegExp(r'[A-Z]').hasMatch(password)),
              _buildRequirementChip('a-z', RegExp(r'[a-z]').hasMatch(password)),
              _buildRequirementChip('0-9', RegExp(r'[0-9]').hasMatch(password)),
              _buildRequirementChip('!@#\$', RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRequirementChip(String label, bool met) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          met ? Icons.check_circle : Icons.circle_outlined,
          size: 14,
          color: met ? Colors.green : Colors.white.withOpacity(0.3),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: met ? Colors.green : Colors.white.withOpacity(0.3),
            fontSize: 11,
            fontWeight: met ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  bool _isValidEmail(String email) => RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
}