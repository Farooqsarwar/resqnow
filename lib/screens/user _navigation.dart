// lib/screens/UserNavigationScreen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/routing_service.dart';
import 'chatscreen.dart';
import 'userdashboard.dart';

class UserNavigationScreen extends StatefulWidget {
  final String requestId;

  const UserNavigationScreen({super.key, required this.requestId});

  @override
  State<UserNavigationScreen> createState() => _UserNavigationScreenState();
}

class _UserNavigationScreenState extends State<UserNavigationScreen>
    with TickerProviderStateMixin {
  // --- Constants ---
  static const Color primary = Color(0xFFE43A45);
  static const Color cardDark = Color(0xFF1C1C1E);
  static const Color backgroundDark = Color(0xFF121212);
  static const Color routeColor = Color(0xFF4285F4);
  static const Color textPrimary = Color(0xFFEAEAEA);
  static const Color textSecondary = Color(0xFF8E8E93);

  // --- Services ---
  final SupabaseClient supabase = Supabase.instance.client;
  final MapController _mapController = MapController();
  final Distance _distanceCalculator = const Distance();

  // --- State Variables ---
  LatLng _myLocation = const LatLng(37.7749, -122.4194);
  LatLng? _rescuerLocation;
  String? _rescuerPhone;
  String _rescuerName = "Finding Responder...";
  String? _responderId;
  String _status = "pending";
  bool _isLoading = true;
  String? _errorMessage;

  // --- Chat State ---
  bool _hasNewMessage = false;
  RealtimeChannel? _messageChannel;

  // --- Navigation State ---
  bool _rescuerHasArrived = false;
  double _distanceToRescuer = 0.0;
  RouteInfo? _routeInfo;
  List<LatLng> _routePoints = [];

  // --- Rescuers List State ---
  List<Map<String, dynamic>> _activeRescuers = [];
  bool _showRescuersList = false;

  // --- Animations & Timers ---
  AnimationController? _pulseController;
  Animation<double>? _pulseAnimation;
  Timer? _pollingTimer;
  Timer? _rescuersRefreshTimer;

  bool _isDisposing = false;
  bool _isExplicitlyCancelled = false;
  bool _feedbackSubmitted = false;

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
      CurvedAnimation(parent: _pulseController!, curve: Curves.easeInOut),
    );
  }

  void _recenterMap() {
    _mapController.move(_myLocation, 15);
  }

  Future<void> _initialize() async {
    try {
      await _fetchInitialData();
      await _loadActiveRescuers();
      _setupMessageSubscription();
      _startPolling();
      _startRescuersRefresh();
    } catch (e) {
      debugPrint('Initialization error: $e');
      if (mounted) {
        setState(() => _errorMessage = 'Failed to initialize: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _setupMessageSubscription() {
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
          if (mounted) setState(() => _hasNewMessage = true);
        }
      },
    )
        .subscribe();
  }

  @override
  void dispose() {
    _isDisposing = true;
    _pollingTimer?.cancel();
    _rescuersRefreshTimer?.cancel();
    _mapController.dispose();
    _pulseController?.dispose();
    if (_messageChannel != null) supabase.removeChannel(_messageChannel!);

    if (_status != 'completed' && _status != 'cancelled' && !_isExplicitlyCancelled) {
      _forceCancelRequest();
    }
    super.dispose();
  }

  void _forceCancelRequest() {
    try {
      supabase.from('emergency_requests')
          .update({'status': 'cancelled'}).eq('id', widget.requestId);
    } catch (e) {
      debugPrint("Error auto-cancelling: $e");
    }
  }

  Future<void> _handleBackScope() async {
    if (_status == 'completed' || _status == 'cancelled') {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const UserDashboard()),
            (route) => false,
      );
      return;
    }
    await _cancelRequest();
  }

  Future<void> _loadActiveRescuers() async {
    try {
      final rescuersData = await supabase
          .from('responder_locations')
          .select()
          .eq('is_on_duty', true);

      if (mounted) {
        List<Map<String, dynamic>> rescuersWithDistance = [];
        for (var rescuer in rescuersData) {
          final lat = (rescuer['latitude'] as num?)?.toDouble() ?? 0;
          final lng = (rescuer['longitude'] as num?)?.toDouble() ?? 0;
          final distance = _distanceCalculator.as(LengthUnit.Kilometer, _myLocation, LatLng(lat, lng));

          rescuersWithDistance.add({
            ...rescuer,
            'distance': distance,
          });
        }
        rescuersWithDistance.sort((a, b) =>
            (a['distance'] as double).compareTo(b['distance'] as double));

        setState(() => _activeRescuers = rescuersWithDistance);
      }
    } catch (e) {
      debugPrint('❌ Error loading rescuers: $e');
    }
  }

  void _startRescuersRefresh() {
    _rescuersRefreshTimer?.cancel();
    _rescuersRefreshTimer = Timer.periodic(
      const Duration(seconds: 15),
          (_) => _loadActiveRescuers(),
    );
  }

  Future<void> _fetchInitialData() async {
    try {
      final data = await supabase
          .from('emergency_requests')
          .select()
          .eq('id', widget.requestId)
          .maybeSingle();

      if (data != null && mounted) {
        await _processRequestData(data);
      } else {
        setState(() => _errorMessage = 'Request not found');
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = "Failed to load request data");
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchLatestData());
  }

  Future<void> _fetchLatestData() async {
    if (!mounted || _isDisposing) return;
    try {
      final data = await supabase
          .from('emergency_requests')
          .select()
          .eq('id', widget.requestId)
          .maybeSingle();

      if (data != null && mounted) await _processRequestData(data);
    } catch (e) {
      debugPrint("Polling error: $e");
    }
  }

  Future<void> _processRequestData(Map<String, dynamic> request) async {
    final newStatus = request['status'] as String? ?? 'pending';
    final lat = (request['latitude'] as num?)?.toDouble();
    final lng = (request['longitude'] as num?)?.toDouble();
    final responderId = request['responder_id'] as String?;

    if (!mounted) return;

    setState(() {
      _status = newStatus;
      _responderId = responderId;
      _errorMessage = null;
      if (lat != null && lng != null) _myLocation = LatLng(lat, lng);
    });

    if (responderId != null) {
      await _fetchRescuerLocation(responderId);
      if (_rescuerName == "Finding Responder...") {
        await _fetchRescuerProfile(responderId);
      }
    }

    if (newStatus == 'completed' && mounted && !_feedbackSubmitted) {
      _pollingTimer?.cancel();
      _rescuersRefreshTimer?.cancel();
      _showFeedbackDialog();
    }
  }

  Future<void> _fetchRescuerLocation(String responderId) async {
    try {
      final locationData = await supabase
          .from('responder_locations')
          .select('latitude, longitude, is_on_duty')
          .eq('responder_id', responderId)
          .maybeSingle();

      if (locationData != null && mounted) {
        final responderLat = (locationData['latitude'] as num?)?.toDouble();
        final responderLng = (locationData['longitude'] as num?)?.toDouble();

        if (responderLat != null && responderLng != null) {
          final newRescuerLocation = LatLng(responderLat, responderLng);

          _distanceToRescuer = _distanceCalculator.as(LengthUnit.Meter, _myLocation, newRescuerLocation);

          if (_distanceToRescuer <= 100 && !_rescuerHasArrived && _status == 'accepted') {
            _rescuerHasArrived = true;
            _showRescuerArrivedDialog();
          }

          if (_rescuerLocation == null || _distanceCalculator.as(LengthUnit.Meter, _rescuerLocation!, newRescuerLocation) > 50) {
            setState(() => _rescuerLocation = newRescuerLocation);
            await _calculateRoute();
          } else {
            setState(() => _rescuerLocation = newRescuerLocation);
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error fetching responder location: $e');
    }
  }

  void _showRescuerArrivedDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.celebration, color: Colors.green, size: 32),
            SizedBox(width: 12),
            Expanded(child: Text("Help Has Arrived!", style: TextStyle(color: Colors.white, fontSize: 20))),
          ],
        ),
        content: Text("$_rescuerName is nearby!", style: const TextStyle(color: Colors.white70)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Got It!", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _calculateRoute() async {
    if (_rescuerLocation == null) return;
    try {
      final routeInfo = await RoutingService.getRoute(_rescuerLocation!, _myLocation);
      if (routeInfo != null && mounted) {
        setState(() {
          _routeInfo = routeInfo;
          _routePoints = routeInfo.routePoints;
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

      final bounds = LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
      _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(80)));
    } catch (e) {
      debugPrint("Map fit error: $e");
    }
  }

  Future<void> _fetchRescuerProfile(String responderId) async {
    try {
      final data = await supabase.from('profiles').select('name, phone').eq('id', responderId).maybeSingle();
      if (data != null && mounted) {
        setState(() {
          _rescuerName = data['name'] ?? 'Emergency Responder';
          _rescuerPhone = data['phone'];
        });
      }
    } catch (e) {
      debugPrint("Error fetching rescuer profile: $e");
    }
  }

  Future<void> _makeCall(String phoneNumber) async {
    if (phoneNumber.isEmpty) return;
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) await launchUrl(launchUri);
  }

  Future<void> _cancelRequest() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardDark,
        title: const Text("Cancel Request?", style: TextStyle(color: Colors.white)),
        content: const Text("Are you sure?", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("No")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isExplicitlyCancelled = true);
              try {
                await supabase.from('emergency_requests').update({'status': 'cancelled'}).eq('id', widget.requestId);
                if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const UserDashboard()), (r) => false);
              } catch (e) {
                // Handle error
              }
            },
            child: const Text("Yes, Cancel", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showFeedbackDialog() {
    if (!mounted || _feedbackSubmitted) return;
    int selectedRating = 5;
    final TextEditingController commentController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: cardDark,
            title: const Text("Rescue Complete!", style: TextStyle(color: Colors.white)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("How was your experience?", style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) => GestureDetector(
                      onTap: () => setDialogState(() => selectedRating = index + 1),
                      child: Icon(index < selectedRating ? Icons.star : Icons.star_border, color: Colors.amber, size: 32),
                    )),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: commentController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(hintText: "Add comment...", filled: true, fillColor: Colors.white10),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () { Navigator.pop(ctx); _navigateToDashboard(); }, child: const Text("Skip")),
              ElevatedButton(
                onPressed: isSubmitting ? null : () async {
                  setDialogState(() => isSubmitting = true);
                  await _submitFeedback(selectedRating, commentController.text);
                  Navigator.pop(ctx);
                  _navigateToDashboard();
                },
                child: const Text("Submit"),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _submitFeedback(int rating, String comment) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null || _responderId == null) return;
    await supabase.from('feedback').insert({
      'request_id': widget.requestId,
      'responder_id': _responderId,
      'user_id': userId,
      'rating': rating,
      'comment': comment.isNotEmpty ? comment : null,
    });
    _feedbackSubmitted = true;
  }

  void _navigateToDashboard() {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const UserDashboard()), (r) => false);
  }

  void _openChatScreen() {
    setState(() => _hasNewMessage = false);
    Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(requestId: widget.requestId, senderRole: 'victim', chatTitle: _rescuerName)));
  }

  String _getDistanceText() {
    return _distanceToRescuer < 1000 ? "${_distanceToRescuer.round()} m away" : "${(_distanceToRescuer / 1000).toStringAsFixed(1)} km away";
  }

  String _formatDistance(double distanceKm) {
    return distanceKm < 1 ? "${(distanceKm * 1000).round()} m" : "${distanceKm.toStringAsFixed(1)} km";
  }

  // --- UI Building ---
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: backgroundDark,
        body: Center(child: CircularProgressIndicator(color: primary)),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (!didPop) await _handleBackScope();
      },
      child: Scaffold(
        backgroundColor: backgroundDark,
        body: SafeArea(
          child: Stack(
            children: [
              // 1. Map Layer
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _myLocation,
                  initialZoom: 14,
                  minZoom: 5,
                  maxZoom: 18,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.resqnow',
                  ),
                  if (_routePoints.isNotEmpty)
                    PolylineLayer(polylines: [Polyline(points: _routePoints, strokeWidth: 5, color: routeColor)]),
                  MarkerLayer(
                    markers: [
                      Marker(point: _myLocation, width: 80, height: 80, child: _buildUserMarker()),
                      if (_rescuerLocation != null)
                        Marker(point: _rescuerLocation!, width: 80, height: 80, child: _buildAssignedRescuerMarker()),
                      ..._activeRescuers.map((rescuer) {
                        final lat = (rescuer['latitude'] as num?)?.toDouble() ?? 0;
                        final lng = (rescuer['longitude'] as num?)?.toDouble() ?? 0;
                        return Marker(point: LatLng(lat, lng), width: 50, height: 50, child: _buildOtherRescuerMarker(rescuer['name'] ?? 'R'));
                      }),
                    ],
                  ),
                ],
              ),

              // 2. Error Message
              if (_errorMessage != null)
                Positioned(
                  top: 16, left: 16, right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.red.shade800, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        const Icon(Icons.error, color: Colors.white),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.white))),
                        IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _fetchLatestData),
                      ],
                    ),
                  ),
                )
              else
                Positioned(top: 16, left: 16, right: 16, child: _buildStatusCard()),

              // 3. Rescuers Toggle (Pending state)
              if (_status == 'pending')
                Positioned(top: 100, right: 16, child: _buildRescuersToggle()),

              // 4. Rescuers List (Overlay)
              if (_showRescuersList && _status == 'pending')
                Positioned.fill(child: _buildRescuersListPanel()),

              // 5. Recenter Button (ONLY ONE REFRESH ICON)
              if (!_showRescuersList)
                Positioned(
                  right: 16,
                  bottom: 220, // Positioned above the bottom panel
                  child: FloatingActionButton(
                    heroTag: "recenter_btn",
                    backgroundColor: cardDark,
                    onPressed: _recenterMap,
                    child: const Icon(Icons.my_location, color: primary),
                  ),
                ),

              // 6. Bottom Panel
              if (!_showRescuersList)
                Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomPanel()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserMarker() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(12)),
          child: const Text("YOU", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 4),
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(shape: BoxShape.circle, color: primary, border: Border.all(color: Colors.white, width: 3)),
          child: const Icon(Icons.person, color: Colors.white, size: 20),
        ),
      ],
    );
  }

  Widget _buildAssignedRescuerMarker() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: _rescuerHasArrived ? Colors.green : routeColor, borderRadius: BorderRadius.circular(12)),
          child: Text(_rescuerHasArrived ? "ARRIVED" : "RESCUER", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 4),
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(shape: BoxShape.circle, color: _rescuerHasArrived ? Colors.green : routeColor, border: Border.all(color: Colors.white, width: 3)),
          child: const Icon(Icons.medical_services, color: Colors.white, size: 24),
        ),
      ],
    );
  }

  Widget _buildOtherRescuerMarker(String name) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(8)),
          child: Text(name.length > 6 ? '${name.substring(0, 6)}...' : name, style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 2),
        Container(width: 28, height: 28, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.green.withOpacity(0.8)), child: const Icon(Icons.medical_services, color: Colors.white, size: 14)),
      ],
    );
  }

  Widget _buildRescuersToggle() {
    return GestureDetector(
      onTap: () => setState(() => _showRescuersList = !_showRescuersList),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: cardDark, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.green.withOpacity(0.5))),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text('${_activeRescuers.length} Rescuers', style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
            Icon(_showRescuersList ? Icons.expand_less : Icons.expand_more, color: Colors.green, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildRescuersListPanel() {
    return Container(
      color: backgroundDark,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: cardDark, border: Border(bottom: BorderSide(color: Colors.grey.shade800))),
              child: Row(
                children: [
                  IconButton(onPressed: () => setState(() => _showRescuersList = false), icon: const Icon(Icons.close, color: textPrimary)),
                  const SizedBox(width: 8),
                  const Text('Available Rescuers', style: TextStyle(color: textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(onPressed: _loadActiveRescuers, icon: const Icon(Icons.refresh, color: textPrimary)),
                ],
              ),
            ),
            Expanded(
              child: _activeRescuers.isEmpty
                  ? const Center(child: Text('No Rescuers Available', style: TextStyle(color: textPrimary)))
                  : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _activeRescuers.length,
                itemBuilder: (context, index) {
                  final rescuer = _activeRescuers[index];
                  return ListTile(
                    title: Text(rescuer['name'] ?? 'Responder', style: const TextStyle(color: Colors.white)),
                    subtitle: Text(_formatDistance(rescuer['distance'] ?? 0.0), style: const TextStyle(color: Colors.grey)),
                    leading: const CircleAvatar(backgroundColor: Colors.grey, child: Icon(Icons.person)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    Color statusColor = Colors.grey;
    String statusText = 'Processing...';
    IconData statusIcon = Icons.hourglass_empty;

    if (_status == 'pending') {
      statusColor = Colors.orange;
      statusText = 'Finding Responder...';
      statusIcon = Icons.search;
    } else if (_status == 'accepted') {
      statusColor = _rescuerHasArrived ? Colors.green : routeColor;
      statusText = _rescuerHasArrived ? 'Rescuer Has Arrived!' : 'Help is on the way!';
      statusIcon = _rescuerHasArrived ? Icons.celebration : Icons.directions_car;
    } else if (_status == 'completed') {
      statusColor = Colors.green;
      statusText = 'Rescue Complete';
      statusIcon = Icons.check_circle;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: statusColor.withOpacity(0.4), blurRadius: 15)]),
      child: Row(
        children: [
          Icon(statusIcon, color: Colors.white, size: 28),
          const SizedBox(width: 16),
          Expanded(child: Text(statusText, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      decoration: BoxDecoration(
        color: cardDark,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 15)],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),

            // Info Card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _rescuerHasArrived ? Colors.green.withOpacity(0.5) : Colors.white10),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: _rescuerLocation != null
                        ? (_rescuerHasArrived ? Colors.green.withOpacity(0.2) : routeColor.withOpacity(0.2))
                        : Colors.grey.withOpacity(0.2),
                    child: Icon(Icons.medical_services, color: _rescuerLocation != null ? (_rescuerHasArrived ? Colors.green : routeColor) : Colors.grey, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_rescuerName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        Text(_rescuerLocation != null ? _getDistanceText() : 'Searching...', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                      ],
                    ),
                  ),
                  // Actions
                  if (_status != 'pending')
                    Row(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            IconButton(padding: const EdgeInsets.all(8), constraints: const BoxConstraints(), onPressed: _openChatScreen, icon: const Icon(Icons.chat, color: Colors.blue, size: 24)),
                            if (_hasNewMessage)
                              Positioned(right: 6, top: 6, child: Container(width: 8, height: 8, decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle, border: Border.all(color: cardDark, width: 1.5)))),
                          ],
                        ),
                        if (_rescuerPhone != null && _rescuerPhone!.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(8)),
                            child: IconButton(padding: const EdgeInsets.all(8), constraints: const BoxConstraints(), onPressed: () => _makeCall(_rescuerPhone!), icon: const Icon(Icons.call, color: Colors.white, size: 20)),
                          ),
                      ],
                    ),
                ],
              ),
            ),

            // Rescuers Button
            if (_activeRescuers.isNotEmpty && _status == 'pending')
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SizedBox(
                  width: double.infinity, height: 40,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.green), padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: () => setState(() => _showRescuersList = true),
                    icon: const Icon(Icons.list, color: Colors.green, size: 18),
                    label: Text('View ${_activeRescuers.length} Rescuers', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
              ),

            // Cancel Button
            if (_status != 'completed') ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity, height: 44,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: _cancelRequest,
                  child: const Text('CANCEL REQUEST', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ),
            ],
            SizedBox(height: MediaQuery.of(context).padding.bottom > 0 ? 0 : 8),
          ],
        ),
      ),
    );
  }
}