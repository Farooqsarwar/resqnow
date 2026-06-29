import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:resqnow/screens/user%20_navigation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RequestHelpScreen extends StatefulWidget {
  const RequestHelpScreen({super.key});

  @override
  State<RequestHelpScreen> createState() => _RequestHelpScreenState();
}

class _RequestHelpScreenState extends State<RequestHelpScreen> with WidgetsBindingObserver {
  // Colors
  static const Color primary = Color(0xFFE43A45);
  static const Color backgroundDark = Color(0xFF121212);
  static const Color cardBg = Color(0xFF1E1E1E);
  static const Color textPrimary = Color(0xFFEAEAEA);
  static const Color textSecondary = Color(0xFF9CA3AF);

  final MapController _mapController = MapController();

  // Default location (San Francisco) used only until real location is found
  LatLng _userLocation = const LatLng(37.7749, -122.4194);
  bool _isLocationLoaded = false;

  StreamSubscription<Position>? _positionStreamSubscription;

  final List<_EmergencyType> _emergencyTypes = const [
    _EmergencyType(label: 'Medical', icon: Icons.medical_services),
    _EmergencyType(label: 'Fire', icon: Icons.local_fire_department),
    _EmergencyType(label: 'Disaster', icon: Icons.cyclone),
    _EmergencyType(label: 'Crime', icon: Icons.local_police),
  ];

  int _selectedEmergencyIndex = 0;
  final TextEditingController _descriptionController = TextEditingController();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    // Add observer to detect when user comes back from Settings
    WidgetsBinding.instance.addObserver(this);
    _checkPermissionsAndLocate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // If user returns to the app (resumed), try locating again
    if (state == AppLifecycleState.resumed) {
      _checkPermissionsAndLocate();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionStreamSubscription?.cancel();
    _descriptionController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  /// 1. Main Permission Logic
  Future<void> _checkPermissionsAndLocate() async {
    bool serviceEnabled;
    LocationPermission permission;

    // A. Check if GPS is on
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      _showErrorDialog(
        'Location Services Disabled',
        'Please enable Location Services on your device.',
        openSettings: true,
      );
      return;
    }

    // B. Check Permissions
    permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permissions are denied.')),
        );
        return;
      }
    }

    // C. Handle "Permanently Denied"
    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      _showErrorDialog(
        'Permission Required',
        'Location permission is permanently denied. Please enable it in App Settings to request help.',
        openSettings: true, // This enables the button to open settings
      );
      return;
    }

    // D. If we are here, we have permission! Start tracking.
    _startLiveTracking();
  }

  void _startLiveTracking() async {
    // Get single update quickly
    try {
      Position pos = await Geolocator.getCurrentPosition();
      _updateLocation(pos);
    } catch (e) {
      debugPrint("Error getting initial fix: $e");
    }

    // Listen to updates (Live Tracking)
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // Update every 5 meters
    );

    _positionStreamSubscription?.cancel(); // Cancel old stream if exists
    _positionStreamSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) {
        _updateLocation(position);
      },
      onError: (e) => debugPrint('Tracking error: $e'),
    );
  }

  void _updateLocation(Position position) {
    if (!mounted) return;
    setState(() {
      _userLocation = LatLng(position.latitude, position.longitude);
      _isLocationLoaded = true;
    });
    // Center map on user
    _mapController.move(_userLocation, 15.0);
  }

  /// Helper to show dialogs that guide the user
  void _showErrorDialog(String title, String message, {bool openSettings = false}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardBg,
        title: Text(title, style: const TextStyle(color: textPrimary)),
        content: Text(message, style: const TextStyle(color: textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          if (openSettings)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Geolocator.openAppSettings();
              },
              child: const Text('Open Settings', style: TextStyle(color: primary, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }

  Future<void> _onSendRequest() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not logged in.')));
      return;
    }

    if (!_isLocationLoaded) {
      _checkPermissionsAndLocate(); // Try asking again if they hit send
      return;
    }

    setState(() => _isSending = true);

    try {
      // 1. Insert and retrieve the created Row to get the ID
      final response = await supabase.from('emergency_requests').insert({
        'user_id': user.id,
        'emergency_type': _emergencyTypes[_selectedEmergencyIndex].label,
        'description': _descriptionController.text.trim(),
        'latitude': _userLocation.latitude,
        'longitude': _userLocation.longitude,
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      }).select().single(); // <--- FIXED: Added select().single()

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request Sent!'), backgroundColor: Colors.green),
      );

      // 2. Navigate passing the Request ID
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (context) => UserNavigationScreen(requestId: response['id']) // <--- FIXED: Passing ID
        ),
      );

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundDark,
      appBar: AppBar(
        backgroundColor: backgroundDark,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: textPrimary),
        ),
        title: const Text('Request Help', style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('What is the emergency?', style: TextStyle(color: textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.2,
                  ),
                  itemCount: _emergencyTypes.length,
                  itemBuilder: (context, index) {
                    final type = _emergencyTypes[index];
                    final bool isSelected = _selectedEmergencyIndex == index;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedEmergencyIndex = index),
                      child: Container(
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: isSelected ? primary : Colors.transparent, width: 2),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(type.icon, color: primary, size: 40),
                            const SizedBox(height: 8),
                            Text(type.label, style: const TextStyle(color: textPrimary, fontSize: 16, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),

                // Location Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Confirm Location', style: TextStyle(color: textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                    if (!_isLocationLoaded)
                      GestureDetector(
                        onTap: _checkPermissionsAndLocate, // Allow tapping to retry
                        child: const Text("Retry GPS", style: TextStyle(color: primary, fontWeight: FontWeight.bold)),
                      )
                    else
                      const Text("Live GPS Active", style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold))
                  ],
                ),
                const SizedBox(height: 12),

                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(initialCenter: _userLocation, initialZoom: 15),
                      children: [
                        TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.resqnow',  // ← ADD THIS LINE
                        ),

                        MarkerLayer(markers: [
                          Marker(
                            point: _userLocation,
                            width: 40, height: 40,
                            child: const Icon(Icons.location_on, color: primary, size: 40),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text('Brief Description', style: TextStyle(color: textSecondary)),
                const SizedBox(height: 8),
                TextField(
                  controller: _descriptionController,
                  maxLines: 3,
                  style: const TextStyle(color: textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Add details (optional)',
                    hintStyle: const TextStyle(color: Colors.grey),
                    filled: true, fillColor: cardBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
               Center(
                 child: Container(
                    color: backgroundDark,
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                        onPressed: (_isSending || !_isLocationLoaded) ? null : _onSendRequest,
                        child: _isSending
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Text(!_isLocationLoaded ? 'Waiting for GPS...' : 'Send Request', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ),
                  ),
               ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmergencyType {
  final String label;
  final IconData icon;
  const _EmergencyType({required this.label, required this.icon});
}