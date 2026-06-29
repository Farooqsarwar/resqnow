// lib/screens/ResponderDashboardScreen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:resqnow/rescue//Rescuer_history.dart';
import 'package:resqnow/screens/login.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'ResponderNavigationScreen.dart';

class ResponderDashboardScreen extends StatefulWidget {
  const ResponderDashboardScreen({super.key});

  @override
  State<ResponderDashboardScreen> createState() => _ResponderDashboardScreenState();
}

class _ResponderDashboardScreenState extends State<ResponderDashboardScreen> {
  static const Color primary = Color(0xFFD93434);
  static const Color backgroundDark = Color(0xFF121212);
  static const Color textPrimaryDark = Color(0xFFE0E0E0);
  static const Color cardDark = Color(0xFF1E1E1E);

  bool _onDuty = true;
  String _responderName = 'Responder';

  LatLng _responderLocation = const LatLng(37.7749, -122.4194);
  final Distance _distanceCalculator = const Distance();
  final SupabaseClient supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;
  String? _locationError;
  String? _dbStatus;

  StreamSubscription? _realtimeSubscription;
  Timer? _locationUpdateTimer;

  @override
  void initState() {
    super.initState();
    _initializeResponder();
  }

  Future<void> _initializeResponder() async {
    await _loadResponderProfile();
    await _getCurrentLocation();
    await _loadRequests();
    _setupRealtimeSubscription();
  }

  @override
  void dispose() {
    _realtimeSubscription?.cancel();
    _locationUpdateTimer?.cancel();
    // Set off duty when leaving the screen
    _updateResponderLocationInDB(isOnDuty: false);
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // NEW: Logout Functionality
  // ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
  // UPDATED: Logout Functionality
  // ---------------------------------------------------------------------------
  Future<void> _handleLogout() async {
    // 1. Show Confirmation Dialog
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardDark,
        title: const Text('Logout', style: TextStyle(color: textPrimaryDark)),
        content: const Text(
          'Are you sure you want to log out? You will be marked as Off Duty.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout', style: TextStyle(color: primary)),
          ),
        ],
      ),
    );

    if (shouldLogout != true) return;

    // 2. Show Loading Indicator
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: primary)),
    );

    try {
      // 3. Mark as Off Duty in DB first (while still authenticated)
      await _updateResponderLocationInDB(isOnDuty: false);

      // 4. Cancel listeners
      _realtimeSubscription?.cancel();
      _locationUpdateTimer?.cancel();

      // 5. Sign out from Supabase
      await supabase.auth.signOut();

      if (mounted) {
        // Pop the loader
        Navigator.pop(context);

        // 6. Navigate to Login Screen and remove all previous routes
        // REPLACE 'LoginScreen()' WITH YOUR ACTUAL LOGIN SCREEN WIDGET
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
              (route) => false, // This predicates removes all back stack history
        );
      }
    } catch (e) {
      debugPrint("Error logging out: $e");
      if (mounted) {
        Navigator.pop(context); // Pop loader
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error logging out: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
  /// Save/Update responder location in the database
  Future<void> _updateResponderLocationInDB({bool? isOnDuty}) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('❌ Cannot update location: No user ID');
        return;
      }

      final bool dutyStatus = isOnDuty ?? _onDuty;

      debugPrint('📍 Updating responder_locations: lat=${_responderLocation.latitude}, lng=${_responderLocation.longitude}, onDuty=$dutyStatus');

      // Upsert: Insert if not exists, Update if exists
      await supabase.from('responder_locations').upsert({
        'responder_id': userId,
        'name': _responderName,
        'latitude': _responderLocation.latitude,
        'longitude': _responderLocation.longitude,
        'is_on_duty': dutyStatus,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'responder_id');

      debugPrint(' Responder location saved to database');

      if (mounted) {
        setState(() {
          _dbStatus = ' DB Updated: ${_responderLocation.latitude.toStringAsFixed(4)}, ${_responderLocation.longitude.toStringAsFixed(4)}';
        });
      }
    } catch (e) {
      debugPrint(' Error updating responder location in DB: $e');
      if (mounted) {
        setState(() {
          _dbStatus = ' DB Error: $e';
        });
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      setState(() {
        _locationError = null;
        _dbStatus = 'Getting location...';
      });

      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locationError = 'Location services are disabled';
          _dbStatus = 'Location disabled';
        });
        return;
      }

      // Check permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _locationError = 'Location permission denied';
            _dbStatus = 'Permission denied';
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _locationError = 'Location permission permanently denied';
          _dbStatus = 'Permission permanently denied';
        });
        return;
      }

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      setState(() {
        _responderLocation = LatLng(position.latitude, position.longitude);
        _dbStatus = '📍 Got location, saving to DB...';
      });

      debugPrint('📍 Got location: ${position.latitude}, ${position.longitude}');

      // Save location to database
      await _updateResponderLocationInDB();

      // Start periodic location updates
      if (_onDuty) {
        _startLocationUpdates();
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
      setState(() {
        _locationError = 'Error getting location';
        _dbStatus = '❌ Error: $e';
      });
    }
  }

  void _startLocationUpdates() {
    _locationUpdateTimer?.cancel();

    if (!_onDuty) return;

    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!_onDuty || !mounted) return;

      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );

        if (mounted) {
          final newLocation = LatLng(position.latitude, position.longitude);

          // Check if location changed significantly (more than 10 meters)
          final distance = _distanceCalculator.as(
            LengthUnit.Meter,
            _responderLocation,
            newLocation,
          );

          setState(() {
            _responderLocation = newLocation;
          });

          // Only update DB if moved more than 10 meters (to reduce DB calls)
          if (distance > 10) {
            await _updateResponderLocationInDB();
            debugPrint('📍 Location updated in DB (moved ${distance.toStringAsFixed(0)}m)');
          } else {
            setState(() {
              _dbStatus = '✅ Location: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)} (no significant movement)';
            });
          }
        }
      } catch (e) {
        debugPrint('Error updating location: $e');
      }
    });
  }

  Future<void> _loadResponderProfile() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final profileData = await supabase
          .from('profiles')
          .select('name')
          .eq('id', userId)
          .maybeSingle();

      if (mounted && profileData != null) {
        setState(() {
          _responderName = profileData['name'] ?? 'Responder';
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
  }

  Future<void> _loadRequests() async {
    if (!_onDuty) {
      setState(() {
        _requests = [];
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final requestsData = await supabase
          .from('emergency_requests')
          .select()
          .eq('status', 'pending')
          .order('created_at', ascending: false);
      debugPrint('📋 Loaded ${requestsData.length} pending requests');

      List<Map<String, dynamic>> enrichedRequests = [];

      for (var request in requestsData) {
        final userId = request['user_id'] as String?;
        String userName = 'Anonymous User';
        String? userPhone;
        String? userEmail;

        if (userId != null && userId.isNotEmpty) {
          try {
            // Try to fetch profile data
            final profileData = await supabase
                .from('profiles')
                .select('name, phone, email')
                .eq('id', userId)
                .maybeSingle();

            if (profileData != null) {
              // Priority: name > email username > partial ID
              final nameValue = profileData['name'];
              final emailValue = profileData['email'];
              userEmail = emailValue?.toString();

              if (nameValue != null && nameValue.toString().trim().isNotEmpty) {
                userName = nameValue.toString().trim();
              } else if (emailValue != null && emailValue.toString().trim().isNotEmpty) {
                // Use email username part (before @)
                final email = emailValue.toString().trim();
                userName = email.split('@').first;
              } else {
                userName = 'User ${userId.substring(0, 8)}';
              }

              // Get phone
              final phoneValue = profileData['phone'];
              if (phoneValue != null && phoneValue.toString().trim().isNotEmpty) {
                userPhone = phoneValue.toString().trim();
              }
            } else {
              userName = 'User ${userId.substring(0, 8)}';
            }
          } catch (e) {
            userName = 'User ${userId.substring(0, 8)}';
          }
        }

        enrichedRequests.add({
          ...request,
          'user_name': userName,
          'user_phone': userPhone,
          'user_email': userEmail,
        });
      }

      if (mounted) {
        setState(() {
          _requests = enrichedRequests;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Error loading requests: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _requests = [];
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading requests: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _setupRealtimeSubscription() {
    _realtimeSubscription?.cancel();

    if (!_onDuty) return;

    _realtimeSubscription = supabase
        .from('emergency_requests')
        .stream(primaryKey: ['id'])
        .eq('status', 'pending')
        .order('created_at')
        .listen((data) {
      if (_onDuty && mounted) {
        _loadRequests();
      }
    });
  }

  void _toggleDutyStatus(bool value) async {
    setState(() {
      _onDuty = value;
    });

    if (_onDuty) {
      await _getCurrentLocation();
      _loadRequests();
      _setupRealtimeSubscription();
      _startLocationUpdates();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('You are now ON DUTY at ${_responderLocation.latitude.toStringAsFixed(4)}, ${_responderLocation.longitude.toStringAsFixed(4)}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      _realtimeSubscription?.cancel();
      _locationUpdateTimer?.cancel();

      // Update database to show off duty
      await _updateResponderLocationInDB(isOnDuty: false);

      setState(() {
        _requests = [];
        _dbStatus = 'Off duty - removed from active rescuers';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You are now OFF DUTY.'),
            backgroundColor: Colors.grey,
          ),
        );
      }
    }
  }

  Future<void> _acceptRequest(Map<String, dynamic> requestData) async {
    try {
      final String requestId = requestData['id'];
      final String victimId = requestData['user_id'];
      final double lat = (requestData['latitude'] as num).toDouble();
      final double lng = (requestData['longitude'] as num).toDouble();
      final String myId = supabase.auth.currentUser!.id;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: primary),
        ),
      );

      // Update request with responder info AND current location
      await supabase.from('emergency_requests').update({
        'status': 'accepted',
        'responder_id': myId,
        'responder_lat': _responderLocation.latitude,
        'responder_long': _responderLocation.longitude,
      }).eq('id', requestId);

      // Also ensure responder_locations table is updated
      await _updateResponderLocationInDB();

      debugPrint('✅ Accepted request: $requestId');

      if (!mounted) return;
      Navigator.pop(context);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResponderNavigationScreen(
            targetLocation: LatLng(lat, lng),
            victimId: victimId,
            requestId: requestId,
          ),
        ),
      ).then((_) {
        _loadRequests();
        // Update location when returning from navigation
        _updateResponderLocationInDB();
      });
    } catch (e) {
      if (mounted) Navigator.pop(context);
      debugPrint('Error: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  IconData _getIcon(String? type) {
    switch (type) {
      case 'Medical':
        return Icons.medical_services;
      case 'Fire':
        return Icons.local_fire_department;
      case 'Crime':
        return Icons.local_police;
      case 'Accident':
        return Icons.car_crash;
      default:
        return Icons.warning;
    }
  }

  String _formatTime(String? timestamp) {
    if (timestamp == null) return '';
    try {
      final dt = DateTime.parse(timestamp);
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            // Custom App Bar
            _buildAppBar(),

            // Location Status
            if (_locationError != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_off, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _locationError!,
                        style: const TextStyle(color: Colors.orange),
                      ),
                    ),
                    TextButton(
                      onPressed: _getCurrentLocation,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),

            // Current Location Display (when on duty and no error)
            if (_onDuty && _locationError == null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.my_location, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your Location (Synced)',
                            style: TextStyle(color: Colors.green.shade300, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        await _getCurrentLocation();
                      },
                      icon: const Icon(Icons.refresh, color: Colors.green, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),

            // Off Duty Message or Request List
            Expanded(
              child: _onDuty ? _buildOnDutyContent() : _buildOffDutyContent(),
            ),
          ],
        ),
      ),
    );
  }

  // In ResponderDashboardScreen.dart

// Add this import at the top

// Update the _buildAppBar method to include history button
  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: cardDark, // Use the card color for better contrast against background
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(
        children: [
          // 1. Profile Avatar
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _onDuty ? Colors.green : Colors.grey,
                width: 2,
              ),
            ),
            child: CircleAvatar(
              radius: 22,
              backgroundColor: primary.withOpacity(0.2),
              child: Text(
                _responderName.isNotEmpty ? _responderName[0].toUpperCase() : 'R',
                style: const TextStyle(
                  color: primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),

          // 2. Name & Status (Moved Status text here to save space)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _responderName,
                  style: const TextStyle(
                    color: textPrimaryDark,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _onDuty ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                        boxShadow: [
                          if (_onDuty)
                            BoxShadow(
                                color: Colors.green.withOpacity(0.5),
                                blurRadius: 6,
                                spreadRadius: 1)
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _onDuty ? 'Active Now' : 'Off Duty',
                      style: TextStyle(
                        color: _onDuty ? Colors.green : Colors.grey,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 3. Actions Row
          Row(
            children: [
              // Duty Toggle Switch
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.scale(
                    scale: 0.8,
                    child: Switch(
                      value: _onDuty,
                      activeColor: Colors.black, // Knob color when active
                      activeTrackColor: Colors.green, // Track color when active
                      inactiveThumbColor: Colors.grey.shade400,
                      inactiveTrackColor: Colors.grey.withOpacity(0.3),
                      trackOutlineColor: MaterialStateProperty.all(Colors.transparent),
                      onChanged: _toggleDutyStatus,
                    ),
                  ),
                ],
              ),

              const SizedBox(width: 8),

              // Action Buttons Container (History | Logout)
              Container(
                decoration: BoxDecoration(
                  color: backgroundDark,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Row(
                  children: [
                    // History Button
                    IconButton(
                      icon: const Icon(Icons.history_rounded, size: 22),
                      color: Colors.amber,
                      tooltip: 'Rescue History',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const RescuerHistoryScreen()),
                        );
                      },
                    ),

                    // Small Divider
                    Container(
                        height: 20,
                        width: 1,
                        color: Colors.white.withOpacity(0.1)
                    ),

                    // Logout Button
                    IconButton(
                      icon: const Icon(Icons.logout_rounded, size: 22),
                      color: Colors.grey.shade400,
                      tooltip: 'Logout',
                      visualDensity: VisualDensity.compact,
                      onPressed: _handleLogout,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }  Widget _buildOffDutyContent() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: const BoxDecoration(
                color: cardDark,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.bedtime_outlined,
                size: 80,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'You\'re Off Duty',
              style: TextStyle(
                color: textPrimaryDark,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'You won\'t receive any emergency requests while off duty.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => _toggleDutyStatus(true),
                icon: const Icon(Icons.play_arrow, color: Colors.white),
                label: const Text(
                  'GO ON DUTY',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOnDutyContent() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: primary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber, size: 16, color: primary),
                    const SizedBox(width: 4),
                    Text(
                      '${_requests.length} Active',
                      style: const TextStyle(
                        color: primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _loadRequests,
                icon: const Icon(Icons.refresh, color: textPrimaryDark),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: primary))
              : _requests.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
            onRefresh: _loadRequests,
            color: primary,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _requests.length,
              itemBuilder: (context, index) {
                final req = _requests[index];
                final double lat = (req['latitude'] as num?)?.toDouble() ?? 0.0;
                final double lng = (req['longitude'] as num?)?.toDouble() ?? 0.0;

                final double distanceKm = _distanceCalculator.as(
                  LengthUnit.Kilometer,
                  _responderLocation,
                  LatLng(lat, lng),
                );

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _RequestCard(
                    icon: _getIcon(req['emergency_type']),
                    title: req['emergency_type'] ?? 'Emergency',
                    userName: req['user_name'] ?? 'Unknown User',
                    userPhone: req['user_phone'],
                    distance: '${distanceKm.toStringAsFixed(1)} km',
                    address: 'Lat: ${lat.toStringAsFixed(4)}, Lng: ${lng.toStringAsFixed(4)}',
                    details: req['description'] ?? 'No additional details',
                    createdAt: _formatTime(req['created_at']),
                    onAccept: () => _acceptRequest(req),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, size: 80, color: Colors.grey[700]),
          const SizedBox(height: 16),
          const Text(
            'No Active Requests',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'All emergencies have been handled',
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: _loadRequests,
            icon: const Icon(Icons.refresh, color: Colors.white),
            label: const Text('Refresh', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class ResponderHistoryScreen {
  const ResponderHistoryScreen();
}

// Request Card Widget (unchanged)
// Replace the _RequestCard class in ResponderDashboardScreen.dart

class _RequestCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String userName;
  final String? userPhone;
  final String distance;
  final String address;
  final String details;
  final String createdAt;
  final VoidCallback onAccept;

  const _RequestCard({
    required this.icon,
    required this.title,
    required this.userName,
    this.userPhone,
    required this.distance,
    required this.address,
    required this.details,
    required this.createdAt,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFFD93434);
    const cardDark = Color(0xFF1E1E1E);

    // Responsive sizing
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;
    final horizontalPadding = isSmallScreen ? 12.0 : 16.0;
    final titleFontSize = isSmallScreen ? 14.0 : 16.0;
    final iconSize = isSmallScreen ? 20.0 : 24.0;

    return Container(
      decoration: BoxDecoration(
        color: cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primary.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          // Header Section
          Container(
            padding: EdgeInsets.all(horizontalPadding),
            decoration: BoxDecoration(
              color: primary.withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(isSmallScreen ? 8 : 10),
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: primary, size: iconSize),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.bold,
                          fontSize: titleFontSize,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        createdAt,
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: isSmallScreen ? 11 : 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isSmallScreen ? 8 : 12,
                      vertical: isSmallScreen ? 4 : 6,
                    ),
                    decoration: BoxDecoration(
                      color: primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      distance,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: isSmallScreen ? 12 : 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Details Section
          Padding(
            padding: EdgeInsets.all(horizontalPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // User Info Row
                Row(
                  children: [
                    CircleAvatar(
                      radius: isSmallScreen ? 18 : 20,
                      backgroundColor: Colors.grey[800],
                      child: Text(
                        userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: isSmallScreen ? 14 : 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userName,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: isSmallScreen ? 14 : 16,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (userPhone != null && userPhone!.isNotEmpty)
                            Row(
                              children: [
                                Icon(Icons.phone, size: 12, color: Colors.grey[500]),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    userPhone!,
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: isSmallScreen ? 11 : 12,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                const Divider(color: Colors.grey, height: 1),
                const SizedBox(height: 12),

                // Location Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.location_on, size: 16, color: Colors.grey[500]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        address,
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: isSmallScreen ? 12 : 13,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                // Details Row
                if (details.isNotEmpty && details != 'No additional details')
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.notes, size: 16, color: Colors.grey[500]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            details,
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: isSmallScreen ? 12 : 13,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 16),

                // Accept Button
                SizedBox(
                  width: double.infinity,
                  height: isSmallScreen ? 44 : 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: onAccept,
                    icon: Icon(
                      Icons.check_circle,
                      color: Colors.white,
                      size: isSmallScreen ? 18 : 20,
                    ),
                    label: Text(
                      'ACCEPT & RESPOND',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                        fontSize: isSmallScreen ? 13 : 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}