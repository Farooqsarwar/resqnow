// lib/screens/ResponderNavigationScreen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:resqnow/rescue//ResponderDashboard.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '/screens/chatscreen.dart';
import '/services/routing_service.dart';

class ResponderNavigationScreen extends StatefulWidget {
  final LatLng targetLocation;
  final String victimId;
  final String requestId;
  const ResponderNavigationScreen({
    super.key,
    required this.targetLocation,
    required this.victimId,
    required this.requestId,
  });

  @override
  State<ResponderNavigationScreen> createState() =>
      _ResponderNavigationScreenState();
}

class _ResponderNavigationScreenState extends State<ResponderNavigationScreen>
    with TickerProviderStateMixin {
  // Colors
  static const Color primary = Color(0xFFE43A45);
  static const Color backgroundDark = Color(0xFF121212);
  static const Color cardDark = Color(0xFF1C1C1E);
  static const Color routeColor = Color(0xFF4285F4);

  final Distance _distanceCalculator = const Distance();
  final SupabaseClient supabase = Supabase.instance.client;
  final MapController _mapController = MapController();

  // State
  LatLng _currentLocation = const LatLng(37.7749, -122.4194);
  double _distanceToTarget = 0.0;
  bool _hasArrived = false;
  bool _isLoading = true;
  String? _victimPhone;
  String _victimName = "Victim";

  // New Message State
  bool _hasNewMessage = false;
  RealtimeChannel? _messageChannel;

  // Track completion/cancellation state to prevent dispose logic conflict
  bool _isHandled = false;

  // Route Data
  RouteInfo? _routeInfo;
  List<LatLng> _routePoints = [];
  int _currentStepIndex = 0;
  // Streams
  StreamSubscription<Position>? _positionStream;

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimation();
    _initialize();
  }

  void _initAnimation() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> _initialize() async {
    await _getCurrentLocation();
    await _fetchVictimDetails();
    await _calculateRoute();
    _startNavigation();
    _setupMessageSubscription(); // Start listening for messages
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  // UPDATED: Correct table name 'emergency_chat_messages'
  void _setupMessageSubscription() {
    debugPrint("🔌 Subscribing to chat for Request ID: ${widget.requestId}");

    _messageChannel = supabase
        .channel('public:emergency_chat_messages:${widget.requestId}')
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'emergency_chat_messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'request_id',
        value: widget.requestId,
      ),
      callback: (payload) {
        final newRecord = payload.newRecord;
        final currentUserId = supabase.auth.currentUser?.id;

        if (newRecord['sender_id'] != currentUserId) {
          if (mounted) {
            setState(() {
              _hasNewMessage = true;
            });
            debugPrint("🔔 New message received! Dot enabled.");
          }
        }
      },
    )
        .subscribe((status, error) {
      // FIXED: Changed SystemChannelStatus to RealtimeSubscribeStatus
      if (status == RealtimeSubscribeStatus.subscribed) {
        debugPrint("✅ Subscribed to chat channel!");
      }
    });
  }
  @override
  void dispose() {
    _positionStream?.cancel();
    _mapController.dispose();
    _pulseController.dispose();
    if (_messageChannel != null) supabase.removeChannel(_messageChannel!);

    // Only run the auto-release logic if the request hasn't been explicitly handled
    if (!_isHandled) {
      _releaseRequestBackToPending();
    }

    super.dispose();
  }

  // Fallback: If app crashes or forced closed without UI interaction
  void _releaseRequestBackToPending() {
    try {
      supabase.from('emergency_requests').update({
        'status': 'pending',
        'responder_id': null,
      }).eq('id', widget.requestId);
      debugPrint("Auto-released request back to pending on screen exit");
    } catch (e) {
      debugPrint("Error releasing request: $e");
    }
  }

  Future<void> _handleBackNavigation() async {
    final shouldSkip = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardDark,
        title: const Text("Skip Rescue?", style: TextStyle(color: Colors.white)),
        content: const Text(
          "Are you sure you want to stop navigation? This will cancel the request.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("No, Continue"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Yes, Skip & Cancel"),
          ),
        ],
      ),
    );

    if (shouldSkip == true) {
      setState(() => _isHandled = true);

      try {
        await supabase.from('emergency_requests').update({
          'status': 'cancelled',
          'responder_id': null,
        }).eq('id', widget.requestId);
      } catch (e) {
        debugPrint("Error cancelling request: $e");
      }

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const ResponderDashboardScreen()),
            (route) => false,
      );
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        _showPermissionDialog();
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
        });
      }
    } catch (e) {
      debugPrint("Location Error: $e");
    }
  }

  void _showPermissionDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardDark,
        title: const Text("Location Required",
            style: TextStyle(color: Colors.white)),
        content: const Text(
          "Please enable location permissions in settings to use navigation.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openAppSettings();
            },
            child: const Text("Open Settings"),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchVictimDetails() async {
    try {
      final data = await supabase
          .from('profiles')
          .select('name, phone')
          .eq('id', widget.victimId)
          .maybeSingle();

      if (data != null && mounted) {
        setState(() {
          _victimName = data['name'] ?? "Emergency Victim";
          _victimPhone = data['phone'];
        });
      }
    } catch (e) {
      debugPrint("Error fetching victim details: $e");
    }
  }

  Future<void> _calculateRoute() async {
    try {
      final routeInfo = await RoutingService.getRoute(
        _currentLocation,
        widget.targetLocation,
      );

      if (routeInfo != null && mounted) {
        setState(() {
          _routeInfo = routeInfo;
          _routePoints = routeInfo.routePoints;
          _distanceToTarget = routeInfo.distanceMeters;
        });
        _fitMapToRoute();
      }
    } catch (e) {
      debugPrint("Route calculation error: $e");
    }
  }

  void _fitMapToRoute() {
    if (_routePoints.isEmpty) return;
    try {
      double minLat = _routePoints.first.latitude;
      double maxLat = _routePoints.first.latitude;
      double minLng = _routePoints.first.longitude;
      double maxLng = _routePoints.first.longitude;

      for (var point in _routePoints) {
        if (point.latitude < minLat) minLat = point.latitude;
        if (point.latitude > maxLat) maxLat = point.latitude;
        if (point.longitude < minLng) minLng = point.longitude;
        if (point.longitude > maxLng) maxLng = point.longitude;
      }

      final bounds = LatLngBounds(
        LatLng(minLat, minLng),
        LatLng(maxLat, maxLng),
      );

      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(80)),
      );
    } catch (e) {
      debugPrint("Map fit error: $e");
    }
  }

  Future<void> _startNavigation() async {
    try {
      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      );

      _positionStream =
          Geolocator.getPositionStream(locationSettings: locationSettings)
              .listen((Position position) {
            _updatePosition(position);
          }, onError: (e) {
            debugPrint("Position stream error: $e");
          });
    } catch (e) {
      debugPrint("Start navigation error: $e");
    }
  }

  void _updatePosition(Position pos) {
    if (!mounted) return;

    final newLocation = LatLng(pos.latitude, pos.longitude);

    setState(() {
      _currentLocation = newLocation;
      _distanceToTarget = _distanceCalculator.as(
        LengthUnit.Meter,
        _currentLocation,
        widget.targetLocation,
      );

      _updateCurrentStep();

      if (_distanceToTarget < 50 && !_hasArrived) {
        _hasArrived = true;
        _showArrivalDialog();
      }
    });

    _checkRouteDeviation();
    _uploadLiveLocation(pos.latitude, pos.longitude);
  }

  void _updateCurrentStep() {
    if (_routeInfo == null || _routeInfo!.steps.isEmpty) return;

    for (int i = _currentStepIndex; i < _routeInfo!.steps.length; i++) {
      final step = _routeInfo!.steps[i];
      final distanceToStep = _distanceCalculator.as(
        LengthUnit.Meter,
        _currentLocation,
        step.location,
      );

      if (distanceToStep < 30) {
        setState(() => _currentStepIndex = i + 1);
        break;
      }
    }
  }

  void _checkRouteDeviation() async {
    if (_routePoints.isEmpty) return;
    double minDistance = double.infinity;
    for (var point in _routePoints) {
      final dist =
      _distanceCalculator.as(LengthUnit.Meter, _currentLocation, point);
      if (dist < minDistance) minDistance = dist;
    }

    if (minDistance > 100) {
      await _calculateRoute();
    }
  }

  Future<void> _uploadLiveLocation(double lat, double lng) async {
    try {
      await supabase.from('emergency_requests').update({
        'responder_lat': lat,
        'responder_long': lng,
      }).eq('id', widget.requestId);
    } catch (e) {
      debugPrint("DB Update Error: $e");
    }
  }

  Future<void> _completeRescue() async {
    try {
      _isHandled = true;

      await supabase
          .from('emergency_requests')
          .update({'status': 'completed'}).eq('id', widget.requestId);

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const ResponderDashboardScreen()),
              (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    }
  }

  Future<void> _makeCall() async {
    if (_victimPhone == null || _victimPhone!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Phone number not available")),
      );
      return;
    }
    final Uri launchUri = Uri(scheme: 'tel', path: _victimPhone);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    }
  }

  void _openInMaps() async {
    final url =
        'https://www.google.com/maps/dir/?api=1&destination=${widget.targetLocation.latitude},${widget.targetLocation.longitude}&travelmode=driving';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  void _showArrivalDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 12),
            Text("You've Arrived!", style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "You are within 50 meters of the victim's location.",
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: primary,
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_victimName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      if (_victimPhone != null && _victimPhone!.isNotEmpty)
                        Text(_victimPhone!,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Continue", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _completeRescue();
            },
            icon: const Icon(Icons.check, color: Colors.white),
            label: const Text("Complete Rescue",
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _recenterMap() {
    _mapController.move(_currentLocation, 17);
  }

  void _openChatScreen() {
    setState(() => _hasNewMessage = false);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          requestId: widget.requestId,
          senderRole: 'responder',
          chatTitle: _victimName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        await _handleBackNavigation();
      },
      child: Scaffold(
        backgroundColor: backgroundDark,
        body: _isLoading
            ? Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              CircularProgressIndicator(color: primary),
              SizedBox(height: 16),
              Text("Loading navigation...",
                  style: TextStyle(color: Colors.white70)),
            ],
          ),
        )
            : Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentLocation,
                initialZoom: 15,
                minZoom: 5,
                maxZoom: 18,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.resqnow',
                ),
                if (_routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePoints,
                        strokeWidth: 6,
                        color: routeColor,
                        borderColor: Colors.blue.shade900,
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: widget.targetLocation,
                      width: 60,
                      height: 60,
                      child: AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _pulseAnimation.value,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: primary.withOpacity(0.3),
                              ),
                              child: Center(
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: primary,
                                  ),
                                  child: const Icon(
                                    Icons.sos,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Marker(
                      point: _currentLocation,
                      width: 50,
                      height: 50,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: routeColor,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: routeColor.withOpacity(0.5),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.navigation,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (_routeInfo != null &&
                _routeInfo!.steps.isNotEmpty &&
                _currentStepIndex < _routeInfo!.steps.length)
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                left: 16,
                right: 16,
                child: _buildNavigationCard(),
              ),
            if (_routeInfo == null || _routeInfo!.steps.isEmpty)
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                left: 16,
                child: Container(
                  decoration: BoxDecoration(
                    color: cardDark,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    onPressed: _handleBackNavigation,
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                ),
              ),
            Positioned(
              right: 16,
              bottom: 280,
              child: Column(
                children: [
                  FloatingActionButton.small(
                    heroTag: "recenter",
                    backgroundColor: cardDark,
                    onPressed: _recenterMap,
                    child:
                    const Icon(Icons.my_location, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: "maps",
                    backgroundColor: cardDark,
                    onPressed: _openInMaps,
                    child: const Icon(Icons.map, color: Colors.white),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomPanel(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationCard() {
    final step = _routeInfo!.steps[_currentStepIndex];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: routeColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 5)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(step.icon, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.displayInstruction,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text('${step.distance.round()} m',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.8), fontSize: 14)),
              ],
            ),
          ),
          IconButton(
              onPressed: _handleBackNavigation,
              icon: const Icon(Icons.close, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      decoration: BoxDecoration(
        color: cardDark,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, -5)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), // Reduced padding
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle Bar
              Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[700],
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 12), // Reduced spacing

              // Stats Row (Compact)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildInfoItem(
                      icon: Icons.schedule,
                      label: 'ETA',
                      value: _routeInfo?.formattedDuration ?? '--'),
                  Container(width: 1, height: 30, color: Colors.grey[800]),
                  _buildInfoItem(
                      icon: Icons.straighten,
                      label: 'Dist', // Shortened label
                      value: _routeInfo?.formattedDistance ?? '--'),
                  Container(width: 1, height: 30, color: Colors.grey[800]),
                  _buildInfoItem(
                    icon: Icons.speed,
                    label: 'Status',
                    value: _hasArrived ? 'Arrived' : 'En Route',
                    valueColor: _hasArrived ? Colors.green : primary,
                  ),
                ],
              ),
              const SizedBox(height: 12), // Reduced spacing

              // Victim Info Card (Compact)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    CircleAvatar(
                        radius: 20, // Smaller avatar
                        backgroundColor: primary.withOpacity(0.2),
                        child:
                        const Icon(Icons.person, color: primary, size: 24)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_victimName,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis),
                          Text(_victimPhone ?? 'No phone',
                              style: TextStyle(
                                  color: Colors.grey[400], fontSize: 13)),
                        ],
                      ),
                    ),
                    // Actions Row
                    Row(
                      children: [
                        // Chat Button
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            IconButton(
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(8),
                              onPressed: _openChatScreen,
                              icon: const Icon(Icons.chat, color: Colors.blueAccent, size: 24),
                            ),
                            if (_hasNewMessage)
                              Positioned(
                                right: 6,
                                top: 6,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: cardDark, width: 1.5),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 8),
                        // Call Button
                        Container(
                          decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(8)),
                          child: IconButton(
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(8),
                              onPressed: _makeCall,
                              icon: const Icon(Icons.call, color: Colors.white, size: 20)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Action Button
              SizedBox(
                width: double.infinity,
                height: 48, // Reduced height
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _hasArrived ? Colors.green : primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  onPressed: _hasArrived ? _completeRescue : null,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                          _hasArrived ? Icons.check_circle : Icons.navigation,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        _hasArrived ? 'COMPLETE RESCUE' : 'NAVIGATING...',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper update for smaller text in stats
  Widget _buildInfoItem({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Column(
      children: [
        Icon(icon, color: Colors.grey[500], size: 16), // Smaller icon
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 10)), // Smaller label
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? Colors.white,
            fontSize: 14, // Smaller value text
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

}