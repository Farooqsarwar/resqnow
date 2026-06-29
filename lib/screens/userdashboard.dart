import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'login.dart';
import 'RequestHelp.dart';
import 'SettingsScreen.dart';

class UserDashboard extends StatefulWidget {
  const UserDashboard({super.key});

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  // Theme Colors
  static const Color primary = Color(0xFFE43A45);
  static const Color backgroundDark = Color(0xFF121212);
  static const Color cardDark = Color(0xFF1C1C1E);
  static const Color textDarkPrimary = Color(0xFFEAEAEA);
  static const Color textDarkSecondary = Color(0xFF8E8E93);

  final SupabaseClient supabase = Supabase.instance.client;

  String _userName = 'User';
  String? _localImagePath;
  bool _isLoading = true;
  List<Map<String, dynamic>> _recentRequests = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // --- Logic: Data Loading ---
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await _loadUserProfile();
    await _loadRecentRequests();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadUserProfile() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final prefs = await SharedPreferences.getInstance();
      final localPath = prefs.getString('avatar_${user.id}');

      final profileData = await supabase
          .from('profiles')
          .select('name')
          .eq('id', user.id)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _userName = profileData?['name'] ?? 'User';
          _localImagePath = localPath;
        });
      }
    } catch (e) {
      debugPrint('Profile Load Error: $e');
    }
  }

  Future<void> _loadRecentRequests() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final requestsData = await supabase
          .from('emergency_requests')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(5);

      if (mounted) {
        setState(() {
          _recentRequests = List<Map<String, dynamic>>.from(requestsData);
        });
      }
    } catch (e) {
      debugPrint('Requests Load Error: $e');
    }
  }

  // --- Logic: Image Viewer ---
  void _viewFullImage() {
    if (_localImagePath == null) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.file(
                  File(_localImagePath!),
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _callPolice() async {
    final Uri launchUri = Uri(scheme: 'tel', path: '15');
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    }
  }

  // --- UI: Profile Bottom Sheet ---
  void _showProfileBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () {
                if (_localImagePath != null) {
                  Navigator.pop(context);
                  _viewFullImage();
                }
              },
              child: CircleAvatar(
                radius: 45,
                backgroundColor: primary.withOpacity(0.2),
                backgroundImage: _localImagePath != null
                    ? FileImage(File(_localImagePath!))
                    : null,
                child: _localImagePath == null
                    ? Text(_userName[0].toUpperCase(),
                    style: const TextStyle(color: primary, fontSize: 32, fontWeight: FontWeight.bold))
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            Text(_userName, style: const TextStyle(color: textDarkPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),

            ListTile(
              leading: const Icon(Icons.settings, color: textDarkPrimary),
              title: const Text('Account Settings', style: TextStyle(color: textDarkPrimary)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))
                    .then((_) => _loadUserProfile());
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text('Sign Out', style: TextStyle(color: Colors.redAccent)),
              onTap: () async {
                await supabase.auth.signOut();
                if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final buttonSize = (screenWidth * 0.45).clamp(140.0, 190.0);

    return Scaffold(
      backgroundColor: backgroundDark,
      appBar: AppBar(
        backgroundColor: backgroundDark,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(10.0),
          child: GestureDetector(
            onTap: () => _showProfileBottomSheet(context),
            child: CircleAvatar(
              backgroundColor: primary.withOpacity(0.2),
              backgroundImage: _localImagePath != null
                  ? FileImage(File(_localImagePath!))
                  : null,
              child: _localImagePath == null
                  ? Text(_userName.isNotEmpty ? _userName[0].toUpperCase() : 'U',
                  style: const TextStyle(color: primary, fontSize: 14, fontWeight: FontWeight.bold))
                  : null,
            ),
          ),
        ),
        title: Text("Hello, $_userName",
            style: const TextStyle(color: textDarkPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              Center(
                child: SizedBox(
                  width: buttonSize,
                  height: buttonSize,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      shape: const CircleBorder(),
                      elevation: 10,
                      shadowColor: primary.withOpacity(0.5),
                    ),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RequestHelpScreen()))
                        .then((_) => _loadRecentRequests()),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.sos, size: 50, color: Colors.white),
                        Text('Request Help', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 30),

              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: primary, width: 2),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                onPressed: _callPolice,
                icon: const Icon(Icons.local_police, color: primary),
                label: const Text('Call Police (15)', style: TextStyle(color: primary, fontWeight: FontWeight.bold)),
              ),

              const SizedBox(height: 40),
              const Text('Recent Requests',
                  style: TextStyle(color: textDarkPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),

              if (_isLoading)
                const Center(child: CircularProgressIndicator(color: primary))
              else if (_recentRequests.isEmpty)
                _buildEmptyState()
              else
                ..._recentRequests.map((req) => _buildRequestCard(req)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> req) {
    bool isActive = req['status'] == 'pending' || req['status'] == 'accepted';
    return Card(
      color: cardDark,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text(req['emergency_type'] ?? 'Emergency', style: const TextStyle(color: textDarkPrimary, fontWeight: FontWeight.bold)),
        subtitle: Text(req['created_at'].toString().split('T')[0], style: const TextStyle(color: textDarkSecondary)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? primary.withOpacity(0.2) : Colors.white10,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            req['status'].toString().toUpperCase(),
            style: TextStyle(color: isActive ? primary : textDarkSecondary, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(color: cardDark, borderRadius: BorderRadius.circular(15)),
      child: const Column(
        children: [
          Icon(Icons.history, color: textDarkSecondary, size: 40),
          SizedBox(height: 10),
          Text('No history found', style: TextStyle(color: textDarkSecondary)),
        ],
      ),
    );
  }
}