import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:supabase/supabase.dart' as supabase_dart;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../main.dart';
import 'Admin_login.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final supabase = Supabase.instance.client;
  static const String _sbUrl = 'https://sawjwzjtovqnuwmyrjcy.supabase.co';
  static const String _sbKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNhd2p3emp0b3ZxbnV3bXlyamN5Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NDg2NTUzOSwiZXhwIjoyMDgwNDQxNTM5fQ.crBt9MKmiUjG4JZK9PTlKpoO_Qqnrw7XLik-vUoPu_8';
  final String _serviceId = 'service_w81u6dx';
  final String _templateId = 'template_d1o9gzk';
  final String _userId = 'd4QKVyw1hgy6hiY1E';
  late final supabase_dart.SupabaseClient _adminClient;

  bool _isLoading = false;
  int _idx = 0;
  List<Map<String, dynamic>> users = [], emergencies = [], applications = [];
  int get totalUsers => users.where((u) => u['role'] == 'user').length;
  int get totalRescuers => users.where((u) => u['role'] == 'rescuer').length;
  int get pendingApps => applications.where((a) => a['status'] == 'pending').length;
  int get activeEmergencies => emergencies.where((e) => ['pending', 'accepted'].contains(e['status'])).length;
  int get completedEmergencies => emergencies.where((e) => ['completed', 'cancelled', 'rejected'].contains(e['status'])).length;

  @override
  void initState() {
    super.initState();
    _adminClient = supabase_dart.SupabaseClient(_sbUrl, _sbKey, authOptions: const supabase_dart.AuthClientOptions(autoRefreshToken: false));
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      final res = await Future.wait([
        supabase.from('profiles').select('*').order('created_at', ascending: false),
        supabase.from('emergency_requests').select('*').order('created_at', ascending: false),
        supabase.from('rescuer_applications').select('*').order('created_at', ascending: false),
      ]);
      users = List<Map<String, dynamic>>.from(res[0]);
      emergencies = List<Map<String, dynamic>>.from(res[1]);
      applications = List<Map<String, dynamic>>.from(res[2]);
    } catch (e) {
      _snack('Error: $e', isError: true);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  // ==================== EMAIL LOGIC (FIXED) ====================
  Future<bool> _sendEmail(String name, String email, String pass) async {
    debugPrint("📧 Attempting to send email to $email...");
    try {
      final res = await http.post(
          Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
          headers: {'Content-Type': 'application/json', 'origin': 'http://localhost'},
          body: jsonEncode({
            'service_id': _serviceId,
            'template_id': _templateId,
            'user_id': _userId,
            'template_params': {
              'to_name': name,
              'to_email': email,
              'from_name': 'ResQNow',
              'reply_to': 'noreply@resqnow.com',
              'message': 'Account Approved.\n\nLogin Credentials:\nEmail: $email\nPassword: $pass',
              'subject': 'ResQNow - Your Rescuer Account Credentials',
              'name': name,
              'email': email, // Redundant key for safety
              'password': pass,
              'user_email': email,
              'user_password': pass,
              'recipient_email': email,
              'recipient_name': name,
            }
          })
      );
      debugPrint("📧 EmailJS Response: ${res.statusCode} | ${res.body}");
      return res.statusCode == 200;
    } catch (e) {
      debugPrint("❌ Email Error: $e");
      return false;
    }
  }

  // ==================== ACTIONS ====================
  Future<void> _handleCert(String? url, String? name) async {
    if (url == null) return _snack('No certificate', isError: true);
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } else {
      await Clipboard.setData(ClipboardData(text: url));
      _snack('URL copied to clipboard');
    }
  }

  Future<void> _deleteApp(Map<String, dynamic> app) async {
    if (!await _confirmDialog('Delete Application?', 'Delete ${app['name']}? Includes cert deletion.', isDestructive: true)) return;
    setState(() => _isLoading = true);
    try {
      if (app['certificate_url'] != null) {
        try {
          final name = Uri.parse(app['certificate_url']).pathSegments.last;
          await _adminClient.storage.from('certificates').remove([name]);
        } catch (_) {}
      }
      await _adminClient.from('rescuer_applications').delete().eq('id', app['id']);
      _snack('Deleted');
      await _loadAllData();
    } catch (e) {
      _snack('Error: $e', isError: true);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _clearApps() async {
    if (!await _confirmDialog('Clear Processed?', 'Delete all approved/rejected apps?', isDestructive: true)) return;
    setState(() => _isLoading = true);
    try {
      await _adminClient.from('rescuer_applications').delete().neq('status', 'pending');
      _snack('Cleared processed apps');
      await _loadAllData();
    } catch (e) {
      _snack('Error: $e', isError: true);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _deleteEmergency(String id) async {
    if (!await _confirmDialog('Delete Emergency?', 'Cannot be undone.', isDestructive: true)) return;
    setState(() => _isLoading = true);
    try {
      await _adminClient.from('emergency_requests').delete().eq('id', id);
      _snack('Deleted');
      await _loadAllData();
    } catch (e) {
      _snack('Error: $e', isError: true);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _clearEmergencies() async {
    if (!await _confirmDialog('Clear Completed?', 'Delete completed/cancelled?', isDestructive: true)) return;
    setState(() => _isLoading = true);
    try {
      await _adminClient.from('emergency_requests').delete().inFilter('status', ['completed', 'cancelled', 'rejected']);
      _snack('Cleared completed');
      await _loadAllData();
    } catch (e) {
      _snack('Error: $e', isError: true);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _updateStatus(String id, String status) async {
    try {
      await _adminClient.from('emergency_requests').update({'status': status, 'updated_at': DateTime.now().toIso8601String()}).eq('id', id);
      _snack('Updated to $status');
      await _loadAllData();
    } catch (e) {
      _snack('Error: $e', isError: true);
    }
  }

  Future<void> _approveApp(Map<String, dynamic> app) async {
    if (!await _confirmDialog('Approve ${app['name']}?', 'Creates account & emails credentials.')) return;
    setState(() => _isLoading = true);
    final email = app['email'];
    final pass = String.fromCharCodes(Iterable.generate(12, (_) => 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789!@#\$%'.codeUnitAt(Random.secure().nextInt(60))));
    try {
      final userRes = await _adminClient.auth.admin.createUser(supabase_dart.AdminUserAttributes(
          email: email, password: pass, emailConfirm: true, userMetadata: {'full_name': app['name'], 'role': 'rescuer', 'phone': app['phone']}
      ));
      if (userRes.user == null) throw 'User creation failed';

      await _adminClient.from('profiles').upsert({
        'id': userRes.user!.id, 'name': app['name'], 'email': email, 'phone': app['phone'], 'role': 'rescuer', 'email_verified': true, 'created_at': DateTime.now().toIso8601String()
      });
      await _adminClient.from('rescuer_applications').update({'status': 'approved', 'approved_by': supabase.auth.currentUser?.id}).eq('id', app['id']);

      await _loadAllData();
      final sent = await _sendEmail(app['name'], email, pass);
      _showResult(app['name'], email, pass, sent);
    } catch (e) {
      _snack('Error: $e', isError: true);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _deleteUser(Map<String, dynamic> u) async {
    if (!await _confirmDialog('Delete ${u['name']}?', 'PERMANENTLY deletes Account, Profile, History (Cascade).', isDestructive: true)) return;
    setState(() => _isLoading = true);
    try {
      await _adminClient.auth.admin.deleteUser(u['id']);
      _snack('User deleted');
      await _loadAllData();
    } catch (e) {
      _snack('Error: $e', isError: true);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  // ==================== UI HELPERS ====================
  void _snack(String m, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m), backgroundColor: isError ? Colors.red : Colors.green, behavior: SnackBarBehavior.floating, width: 400
    ));
  }

  Future<bool> _confirmDialog(String title, String content, {bool isDestructive = false}) async {
    return await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: Text(title, style: TextStyle(color: isDestructive ? Colors.red : Colors.white)),
      content: Text(content, style: const TextStyle(color: Colors.white70)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: isDestructive ? Colors.red : Colors.green),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(isDestructive ? 'Delete' : 'Confirm', style: const TextStyle(color: Colors.white)),
        )
      ],
    )) ?? false;
  }

  void _showResult(String name, String email, String pass, bool sent) {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(sent ? Icons.check_circle : Icons.warning, color: sent ? Colors.green : Colors.orange, size: 40),
        const SizedBox(height: 10),
        Text(sent ? 'Email Sent' : 'Email Failed', style: const TextStyle(color: Colors.white, fontSize: 18)),
        const SizedBox(height: 20),
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
            child: Column(children: [_row('Name', name), _row('Email', email), _row('Pass', pass)])),
        TextButton.icon(onPressed: () => Clipboard.setData(ClipboardData(text: 'Email: $email\nPass: $pass')), icon: const Icon(Icons.copy), label: const Text('Copy'))
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    ));
  }

  Widget _row(String l, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [
    SizedBox(width: 60, child: Text('$l:', style: const TextStyle(color: Colors.white54, fontSize: 12))),
    Expanded(child: SelectableText(v, style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13)))
  ]));

  // ==================== WIDGETS ====================
  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 900;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Row(children: [
        if (isDesktop) _sidebar(),
        Expanded(child: Column(children: [
          _topBar(isDesktop),
          Expanded(child: _isLoading ? const Center(child: CircularProgressIndicator()) : _content()),
        ]))
      ]),
      drawer: !isDesktop ? Drawer(child: _sidebar()) : null,
    );
  }

  Widget _sidebar() => Container(width: 220, color: const Color(0xFF1A1A1A), child: Column(children: [
    const SizedBox(height: 40), const Icon(Icons.admin_panel_settings, color: Colors.red, size: 40),
    const Text('RESQNOW', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2)),
    const SizedBox(height: 40),
    ...[
      [0, 'Dashboard', Icons.dashboard], [1, 'Users', Icons.people],
      [2, 'Rescuers', Icons.local_fire_department], [3, 'Emergencies', Icons.emergency],
      [4, 'Apps', Icons.assignment_ind]
    ].map((e) => ListTile(
      leading: Icon(e[2] as IconData, color: _idx == e[0] ? Colors.red : Colors.white54),
      title: Text(e[1] as String, style: TextStyle(color: _idx == e[0] ? Colors.white : Colors.white70)),
      tileColor: _idx == e[0] ? Colors.red.withOpacity(0.1) : null,
      trailing: (e[0] == 4 && pendingApps > 0) ? _badge(pendingApps, Colors.red) : (e[0] == 3 && activeEmergencies > 0) ? _badge(activeEmergencies, Colors.orange) : null,
      onTap: () => setState(() => _idx = e[0] as int),
    )),
    const Spacer(),
    ListTile(leading: const Icon(Icons.logout, color: Colors.red), title: const Text('Logout', style: TextStyle(color: Colors.red)), onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdminLogin()))),
  ]));

  Widget _badge(int count, Color color) => Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: color, shape: BoxShape.circle), child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 10)));

  Widget _topBar(bool isDesktop) => Container(height: 60, color: const Color(0xFF1A1A1A), padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
    if (!isDesktop) IconButton(icon: const Icon(Icons.menu, color: Colors.white), onPressed: () => Scaffold.of(context).openDrawer()),
    const Text('Admin Dashboard', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
    const Spacer(), IconButton(icon: const Icon(Icons.refresh, color: Colors.white54), onPressed: _loadAllData),
  ]));

  Widget _content() {
    if (_idx == 0) return _dashboard();
    if (_idx == 1 || _idx == 2) return _userList(_idx == 2);
    if (_idx == 3) return _emergencyList();
    return _appList();
  }

  Widget _dashboard() => Padding(padding: const EdgeInsets.all(20), child: Wrap(spacing: 20, runSpacing: 20, children: [
    _card('Users', totalUsers, Colors.blue, Icons.people), _card('Rescuers', totalRescuers, Colors.orange, Icons.local_fire_department),
    _card('Pending', pendingApps, Colors.purple, Icons.pending_actions), _card('Active', activeEmergencies, Colors.red, Icons.emergency),
    _card('Completed', completedEmergencies, Colors.green, Icons.check_circle),
  ]));

  Widget _card(String t, int v, Color c, IconData i) => Container(
    width: 160, padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.withOpacity(0.3))),
    child: Column(children: [Icon(i, color: c, size: 24), Text('$v', style: TextStyle(color: c, fontSize: 24, fontWeight: FontWeight.bold)), Text(t, style: const TextStyle(color: Colors.white54))]),
  );

  Widget _userList(bool rescuers) {
    final list = users.where((u) => u['role'] == (rescuers ? 'rescuer' : 'user')).toList();
    return ListView.builder(padding: const EdgeInsets.all(16), itemCount: list.length, itemBuilder: (_, i) => Card(
      color: const Color(0xFF1A1A1A),
      child: ListTile(
        leading: Icon(rescuers ? Icons.local_fire_department : Icons.person, color: rescuers ? Colors.orange : Colors.blue),
        title: Text(list[i]['name'] ?? 'Unknown', style: const TextStyle(color: Colors.white)),
        subtitle: Text(list[i]['email'] ?? '', style: const TextStyle(color: Colors.white54)),
        trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteUser(list[i])),
      ),
    ));
  }

  Widget _emergencyList() => Column(children: [
    _header('Emergencies', _clearEmergencies, completedEmergencies > 0),
    Expanded(child: ListView.builder(padding: const EdgeInsets.all(16), itemCount: emergencies.length, itemBuilder: (_, i) {
      final e = emergencies[i]; final color = {'pending':Colors.orange, 'accepted':Colors.blue, 'completed':Colors.green}[e['status']] ?? Colors.grey;
      return Card(color: const Color(0xFF1A1A1A), child: ListTile(
        leading: Icon(Icons.emergency, color: color),
        title: Text(e['emergency_type'] ?? 'Unknown', style: const TextStyle(color: Colors.white)),
        subtitle: Text('${e['status']} • ${e['created_at'].toString().split('T')[0]}', style: const TextStyle(color: Colors.white54)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (['pending', 'accepted'].contains(e['status'])) PopupMenuButton(
            icon: const Icon(Icons.edit, color: Colors.white54), color: const Color(0xFF2A2A2A),
            onSelected: (v) => _updateStatus(e['id'], v),
            itemBuilder: (_) => ['accepted', 'completed', 'cancelled', 'rejected'].map((s) => PopupMenuItem(value: s, child: Text(s, style: const TextStyle(color: Colors.white)))).toList(),
          ),
          IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteEmergency(e['id'])),
        ]),
      ));
    }))
  ]);

  Widget _appList() {
    final pending = applications.where((a) => a['status'] == 'pending').toList();
    return Column(children: [
      _header('Applications (${pending.length} pending)', _clearApps, applications.any((a) => a['status'] != 'pending')),
      Expanded(child: ListView.builder(padding: const EdgeInsets.all(16), itemCount: applications.length, itemBuilder: (_, i) {
        final a = applications[i]; final isPending = a['status'] == 'pending';
        return Card(color: const Color(0xFF1A1A1A), child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.person, color: isPending ? Colors.purple : Colors.grey),
            title: Text(a['name'] ?? 'Unknown', style: const TextStyle(color: Colors.white)),
            subtitle: Text(a['email'] ?? '', style: const TextStyle(color: Colors.white54)),
            trailing: Chip(label: Text(a['status'].toUpperCase(), style: const TextStyle(fontSize: 10)), backgroundColor: (isPending ? Colors.purple : Colors.grey).withOpacity(0.2)),
          ),
          _row('Phone', a['phone'] ?? ''), _row('Exp', a['experience'] ?? ''),
          if (a['certificate_url'] != null) TextButton.icon(onPressed: () => _handleCert(a['certificate_url'], a['certificate_name']), icon: const Icon(Icons.file_open, size: 16), label: const Text('View Cert')),
          const SizedBox(height: 10),
          Row(children: [
            if (isPending) ...[
              Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.green), onPressed: () => _approveApp(a), child: const Text('Approve'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(foregroundColor: Colors.red), onPressed: () => _adminClient.from('rescuer_applications').update({'status': 'rejected'}).eq('id', a['id']), child: const Text('Reject'))),
            ] else
              Expanded(child: OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: Colors.red), onPressed: () => _deleteApp(a), icon: const Icon(Icons.delete, size: 16), label: const Text('Delete'))),
          ])
        ])));
      }))
    ]);
  }

  Widget _header(String title, VoidCallback onClear, bool showClear) => Container(
    padding: const EdgeInsets.all(16), color: const Color(0xFF1A1A1A),
    child: Row(children: [
      Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      const Spacer(),
      if (showClear) TextButton.icon(icon: const Icon(Icons.delete_sweep, size: 18), label: const Text('Clear Old'), style: TextButton.styleFrom(foregroundColor: Colors.red), onPressed: onClear)
    ]),
  );
}