import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final supabase = Supabase.instance.client;

  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _currentPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  String? _localImagePath;
  bool _isLoading = false;

  // Toggle visibility for password fields
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentData() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    final profile = await supabase.from('profiles').select().eq('id', user.id).maybeSingle();

    setState(() {
      _nameController.text = profile?['name'] ?? "";
      _localImagePath = prefs.getString('avatar_${user.id}');
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 50);
    if (picked != null) {
      final prefs = await SharedPreferences.getInstance();
      final userId = supabase.auth.currentUser!.id;
      await prefs.setString('avatar_$userId', picked.path);
      setState(() => _localImagePath = picked.path);
    }
  }



  Future<void> _saveChanges() async {
    final name = _nameController.text.trim();
    final currentPass = _currentPasswordController.text.trim();
    final newPass = _newPasswordController.text.trim();
    final confirmPass = _confirmPasswordController.text.trim();

    setState(() => _isLoading = true);

    try {
      // 1. Update Name in Database
      if (name.isNotEmpty) {
        await supabase.from('profiles').update({'name': name}).eq('id', supabase.auth.currentUser!.id);
      }

      // 2. Handle Password Change
      if (newPass.isNotEmpty) {
        // Validation checks
        if (currentPass.isEmpty) throw 'Please enter your current password to set a new one';
        if (newPass != confirmPass) throw 'New passwords do not match';
        if (newPass.length < 6) throw 'New password must be at least 6 characters';

        // Step A: Re-authenticate the user (Security check)
        final email = supabase.auth.currentUser?.email;
        await supabase.auth.signInWithPassword(
          email: email!,
          password: currentPass,
        );

        // Step B: Update Password in Auth system
        await supabase.auth.updateUser(UserAttributes(password: newPass));

        // Clear password fields on success
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
      }

      if (mounted) {
        _showSnackBar("Settings updated successfully!", Colors.green);
        Navigator.pop(context);
      }
    } catch (e) {
      _showSnackBar(e.toString().replaceAll('Exception: ', ''), Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryRed = Color(0xFFE43A45);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Account Settings", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.grey[900],
                    backgroundImage: _localImagePath != null ? FileImage(File(_localImagePath!)) : null,
                    child: _localImagePath == null ? const Icon(Icons.person, size: 60, color: Colors.white24) : null,
                  ),
                  Positioned(
                    bottom: 0, right: 0,
                    child: GestureDetector(
                      onTap: _showPickerOptions,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(color: primaryRed, shape: BoxShape.circle),
                        child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                      ),
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 40),

            // Profile Section
            _sectionHeader("PERSONAL INFORMATION"),
            _buildTextField(
              controller: _nameController,
              label: "Display Name",
              icon: Icons.person_outline,
              hint: "Update your name",
            ),

            const SizedBox(height: 32),

            // Security Section
            _sectionHeader("SECURITY"),
            _buildTextField(
              controller: _currentPasswordController,
              label: "Current Password",
              icon: Icons.lock_open,
              hint: "Verify identity",
              isPassword: true,
              obscure: _obscureCurrent,
              onToggle: () => setState(() => _obscureCurrent = !_obscureCurrent),
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _newPasswordController,
              label: "New Password",
              icon: Icons.lock_outline,
              hint: "Min. 6 characters",
              isPassword: true,
              obscure: _obscureNew,
              onToggle: () => setState(() => _obscureNew = !_obscureNew),
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _confirmPasswordController,
              label: "Confirm New Password",
              icon: Icons.check_circle_outline,
              hint: "Match new password",
              isPassword: true,
              obscure: _obscureConfirm,
              onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),

            const SizedBox(height: 40),

            // Save Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryRed,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 4,
                ),
                onPressed: _isLoading ? null : _saveChanges,
                child: _isLoading
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text("Save All Changes",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(title,
          style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String hint,
    bool isPassword = false,
    bool obscure = false,
    VoidCallback? onToggle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
            prefixIcon: Icon(icon, color: const Color(0xFFE43A45), size: 20),
            suffixIcon: isPassword ? IconButton(
              icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, color: Colors.white60, size: 20),
              onPressed: onToggle,
            ) : null,
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  void _showPickerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.white70),
              title: const Text('Gallery', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(context); _pickImage(ImageSource.gallery); },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.white70),
              title: const Text('Camera', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(context); _pickImage(ImageSource.camera); },
            ),
          ],
        ),
      ),
    );
  }
}