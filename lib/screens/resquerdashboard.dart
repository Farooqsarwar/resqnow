// // lib/screens/ResponderDashboardScreen.dart
//
// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:supabase_flutter/supabase_flutter.dart';
// import 'package:latlong2/latlong.dart';
// import 'package:geolocator/geolocator.dart';
// import 'ResponderNavigationScreen.dart';
//
// class ResponderDashboardScreen extends StatefulWidget {
//   const ResponderDashboardScreen({super.key});
//
//   @override
//   State<ResponderDashboardScreen> createState() => _ResponderDashboardScreenState();
// }
//
// class _ResponderDashboardScreenState extends State<ResponderDashboardScreen> {
//   static const Color primary = Color(0xFFD93434);
//   static const Color backgroundDark = Color(0xFF121212);
//   static const Color textPrimaryDark = Color(0xFFE0E0E0);
//   static const Color cardDark = Color(0xFF1E1E1E);
//
//   bool _onDuty = false; // Start as OFF duty
//   String _responderName = 'Responder';
//
//   LatLng _responderLocation = const LatLng(37.7749, -122.4194);
//   final Distance _distanceCalculator = const Distance();
//   final SupabaseClient supabase = Supabase.instance.client;
//
//   List<Map<String, dynamic>> _requests = [];
//   bool _isLoading = true;
//   String? _locationStatus;
//   String? _dbStatus;
//
//   StreamSubscription? _realtimeSubscription;
//   Timer? _locationUpdateTimer;
//
//   @override
//   void initState() {
//     super.initState();
//     _initializeResponder();
//   }
//
//   Future<void> _initializeResponder() async {
//     await _loadResponderProfile();
//     await _getCurrentLocation();
//     await _loadRequests();
//     _setupRealtimeSubscription();
//   }
//
//   @override
//   void dispose() {
//     _realtimeSubscription?.cancel();
//     _locationUpdateTimer?.cancel();
//     _setOffDuty();
//     super.dispose();
//   }
//
//   Future<void> _setOffDuty() async {
//     try {
//       final userId = supabase.auth.currentUser?.id;
//       if (userId != null) {
//         await supabase.from('responder_locations').upsert({
//           'responder_id': userId,
//           'name': _responderName,
//           'latitude': _responderLocation.latitude,
//           'longitude': _responderLocation.longitude,
//           'is_on_duty': false,
//           'updated_at': DateTime.now().toIso8601String(),
//         }, onConflict: 'responder_id');
//         debugPrint('✅ Set off duty successfully');
//       }
//     } catch (e) {
//       debugPrint('❌ Error setting off duty: $e');
//     }
//   }
//
//   Future<void> _getCurrentLocation() async {
//     try {
//       setState(() => _locationStatus = 'Getting location...');
//
//       bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
//       if (!serviceEnabled) {
//         setState(() => _locationStatus = '❌ Location services disabled');
//         return;
//       }
//
//       LocationPermission permission = await Geolocator.checkPermission();
//       if (permission == LocationPermission.denied) {
//         permission = await Geolocator.requestPermission();
//         if (permission == LocationPermission.denied) {
//           setState(() => _locationStatus = '❌ Location permission denied');
//           return;
//         }
//       }
//
//       if (permission == LocationPermission.deniedForever) {
//         setState(() => _locationStatus = '❌ Location permission permanently denied');
//         return;
//       }
//
//       final position = await Geolocator.getCurrentPosition(
//         desiredAccuracy: LocationAccuracy.high,
//         timeLimit: const Duration(seconds: 10),
//       );
//
//       setState(() {
//         _responderLocation = LatLng(position.latitude, position.longitude);
//         _locationStatus = '✅ ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
//       });
//
//       debugPrint('📍 Location: ${position.latitude}, ${position.longitude}');
//
//       if (_onDuty) {
//         await _updateLocationInDatabase();
//       }
//
//       _startLocationUpdates();
//     } catch (e) {
//       debugPrint('❌ Location error: $e');
//       setState(() => _locationStatus = '❌ Error: $e');
//     }
//   }
//
//   void _startLocationUpdates() {
//     _locationUpdateTimer?.cancel();
//
//     if (!_onDuty) return;
//
//     _locationUpdateTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
//       if (!_onDuty || !mounted) return;
//
//       try {
//         final position = await Geolocator.getCurrentPosition(
//           desiredAccuracy: LocationAccuracy.high,
//           timeLimit: const Duration(seconds: 5),
//         );
//
//         if (mounted) {
//           setState(() {
//             _responderLocation = LatLng(position.latitude, position.longitude);
//             _locationStatus = '✅ ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
//           });
//           await _updateLocationInDatabase();
//         }
//       } catch (e) {
//         debugPrint('Location update error: $e');
//       }
//     });
//   }
//
//   Future<void> _updateLocationInDatabase() async {
//     try {
//       final userId = supabase.auth.currentUser?.id;
//       if (userId == null) {
//         setState(() => _dbStatus = '❌ No user ID');
//         debugPrint('❌ No user ID found');
//         return;
//       }
//
//       debugPrint('📤 Attempting to save to responder_locations...');
//       debugPrint('📤 User ID: $userId');
//       debugPrint('📤 Location: ${_responderLocation.latitude}, ${_responderLocation.longitude}');
//       debugPrint('📤 On Duty: $_onDuty');
//
//       final dataToSave = {
//         'responder_id': userId,
//         'name': _responderName,
//         'latitude': _responderLocation.latitude,
//         'longitude': _responderLocation.longitude,
//         'is_on_duty': _onDuty,
//         'updated_at': DateTime.now().toIso8601String(),
//       };
//
//       debugPrint('📤 Data to save: $dataToSave');
//
//       await supabase.from('responder_locations').upsert(
//         dataToSave,
//         onConflict: 'responder_id',
//       );
//
//       setState(() => _dbStatus = '✅ Saved to DB');
//       debugPrint('✅ Location saved to database');
//
//       // Verify it was saved
//       final check = await supabase
//           .from('responder_locations')
//           .select()
//           .eq('responder_id', userId)
//           .maybeSingle();
//
//       if (check != null) {
//         debugPrint('✅ Verified in DB: is_on_duty=${check['is_on_duty']} at ${check['latitude']}, ${check['longitude']}');
//       } else {
//         debugPrint('⚠️ Could not verify - no data found after save!');
//       }
//
//     } catch (e, stackTrace) {
//       setState(() => _dbStatus = '❌ DB Error: $e');
//       debugPrint('❌ Database error: $e');
//       debugPrint('❌ Stack trace: $stackTrace');
//     }
//   }
//   Future<void> _loadResponderProfile() async {
//     try {
//       final userId = supabase.auth.currentUser?.id;
//       if (userId == null) return;
//
//       final profileData = await supabase
//           .from('profiles')
//           .select('name')
//           .eq('id', userId)
//           .maybeSingle();
//
//       if (mounted && profileData != null) {
//         setState(() {
//           _responderName = profileData['name'] ?? 'Responder';
//         });
//       }
//     } catch (e) {
//       debugPrint('Error loading profile: $e');
//     }
//   }
//
//   Future<void> _loadRequests() async {
//     if (!_onDuty) {
//       setState(() {
//         _requests = [];
//         _isLoading = false;
//       });
//       return;
//     }
//
//     setState(() => _isLoading = true);
//
//     try {
//       final requestsData = await supabase
//           .from('emergency_requests')
//           .select()
//           .eq('status', 'pending')
//           .order('created_at', ascending: false);
//
//       List<Map<String, dynamic>> enrichedRequests = [];
//
//       for (var request in requestsData) {
//         final userId = request['user_id'] as String?;
//         String userName = 'Unknown User';
//         String? userPhone;
//
//         if (userId != null) {
//           try {
//             final profileData = await supabase
//                 .from('profiles')
//                 .select('name, phone')
//                 .eq('id', userId)
//                 .maybeSingle();
//
//             if (profileData != null) {
//               userName = profileData['name']?.toString().isNotEmpty == true
//                   ? profileData['name']
//                   : 'User';
//               userPhone = profileData['phone'];
//             }
//           } catch (e) {
//             debugPrint('Error fetching profile: $e');
//           }
//         }
//
//         enrichedRequests.add({
//           ...request,
//           'user_name': userName,
//           'user_phone': userPhone,
//         });
//       }
//
//       if (mounted) {
//         setState(() {
//           _requests = enrichedRequests;
//           _isLoading = false;
//         });
//       }
//     } catch (e) {
//       debugPrint("Error loading requests: $e");
//       if (mounted) {
//         setState(() => _isLoading = false);
//       }
//     }
//   }
//
//   void _setupRealtimeSubscription() {
//     _realtimeSubscription?.cancel();
//
//     if (!_onDuty) return;
//
//     _realtimeSubscription = supabase
//         .from('emergency_requests')
//         .stream(primaryKey: ['id'])
//         .eq('status', 'pending')
//         .order('created_at')
//         .listen((data) {
//       if (_onDuty && mounted) {
//         _loadRequests();
//       }
//     });
//   }
//
//   void _toggleDutyStatus(bool value) async {
//     setState(() {
//       _onDuty = value;
//     });
//
//     if (_onDuty) {
//       // Going ON duty
//       await _getCurrentLocation();
//       await _updateLocationInDatabase();
//       _loadRequests();
//       _setupRealtimeSubscription();
//       _startLocationUpdates();
//
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('You are now ON DUTY at ${_responderLocation.latitude.toStringAsFixed(4)}, ${_responderLocation.longitude.toStringAsFixed(4)}'),
//             backgroundColor: Colors.green,
//             duration: const Duration(seconds: 3),
//           ),
//         );
//       }
//     } else {
//       // Going OFF duty
//       _realtimeSubscription?.cancel();
//       _locationUpdateTimer?.cancel();
//       await _setOffDuty();
//
//       setState(() {
//         _requests = [];
//       });
//
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text('You are now OFF DUTY'),
//             backgroundColor: Colors.grey,
//           ),
//         );
//       }
//     }
//   }
//
//   Future<void> _acceptRequest(Map<String, dynamic> requestData) async {
//     try {
//       final String requestId = requestData['id'];
//       final String victimId = requestData['user_id'];
//       final double lat = (requestData['latitude'] as num).toDouble();
//       final double lng = (requestData['longitude'] as num).toDouble();
//       final String myId = supabase.auth.currentUser!.id;
//
//       showDialog(
//         context: context,
//         barrierDismissible: false,
//         builder: (_) => const Center(child: CircularProgressIndicator(color: primary)),
//       );
//
//       await supabase.from('emergency_requests').update({
//         'status': 'accepted',
//         'responder_id': myId,
//         'responder_lat': _responderLocation.latitude,
//         'responder_long': _responderLocation.longitude,
//       }).eq('id', requestId);
//
//       if (!mounted) return;
//       Navigator.pop(context);
//
//       Navigator.push(
//         context,
//         MaterialPageRoute(
//           builder: (_) => ResponderNavigationScreen(
//             targetLocation: LatLng(lat, lng),
//             victimId: victimId,
//             requestId: requestId,
//           ),
//         ),
//       ).then((_) => _loadRequests());
//     } catch (e) {
//       if (mounted) Navigator.pop(context);
//       debugPrint('Error: $e');
//
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
//         );
//       }
//     }
//   }
//
//   IconData _getIcon(String? type) {
//     switch (type) {
//       case 'Medical':
//         return Icons.medical_services;
//       case 'Fire':
//         return Icons.local_fire_department;
//       case 'Crime':
//         return Icons.local_police;
//       case 'Accident':
//         return Icons.car_crash;
//       default:
//         return Icons.warning;
//     }
//   }
//
//   String _formatTime(String? timestamp) {
//     if (timestamp == null) return '';
//     try {
//       final dt = DateTime.parse(timestamp);
//       final now = DateTime.now();
//       final diff = now.difference(dt);
//
//       if (diff.inMinutes < 1) return 'Just now';
//       if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
//       if (diff.inHours < 24) return '${diff.inHours}h ago';
//       return '${diff.inDays}d ago';
//     } catch (e) {
//       return '';
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: backgroundDark,
//       body: SafeArea(
//         child: Column(
//           children: [
//             // App Bar
//             _buildAppBar(),
//
//             // Status Cards (Debug Info)
//             _buildDebugInfo(),
//
//             // Main Content
//             Expanded(
//               child: _onDuty ? _buildOnDutyContent() : _buildOffDutyContent(),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   Widget _buildDebugInfo() {
//     return Container(
//       margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//       padding: const EdgeInsets.all(12),
//       decoration: BoxDecoration(
//         color: cardDark,
//         borderRadius: BorderRadius.circular(12),
//         border: Border.all(color: Colors.grey.shade800),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             children: [
//               const Icon(Icons.bug_report, color: Colors.amber, size: 16),
//               const SizedBox(width: 8),
//               const Text(
//                 'Debug Info',
//                 style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold),
//               ),
//               const Spacer(),
//               IconButton(
//                 onPressed: () async {
//                   await _getCurrentLocation();
//                   if (_onDuty) await _updateLocationInDatabase();
//                 },
//                 icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
//                 padding: EdgeInsets.zero,
//                 constraints: const BoxConstraints(),
//               ),
//             ],
//           ),
//           const SizedBox(height: 8),
//           Text(
//             'Location: ${_locationStatus ?? "Unknown"}',
//             style: const TextStyle(color: Colors.white70, fontSize: 11),
//           ),
//           Text(
//             'Database: ${_dbStatus ?? "Not updated yet"}',
//             style: const TextStyle(color: Colors.white70, fontSize: 11),
//           ),
//           Text(
//             'User ID: ${supabase.auth.currentUser?.id?.substring(0, 8) ?? "N/A"}...',
//             style: const TextStyle(color: Colors.white70, fontSize: 11),
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildAppBar() {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
//       color: backgroundDark,
//       child: Row(
//         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//         children: [
//           Row(
//             children: [
//               CircleAvatar(
//                 radius: 20,
//                 backgroundColor: primary.withOpacity(0.2),
//                 child: Text(
//                   _responderName.isNotEmpty ? _responderName[0].toUpperCase() : 'R',
//                   style: const TextStyle(color: primary, fontWeight: FontWeight.bold, fontSize: 18),
//                 ),
//               ),
//               const SizedBox(width: 12),
//               Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     _responderName,
//                     style: const TextStyle(color: textPrimaryDark, fontSize: 16, fontWeight: FontWeight.bold),
//                   ),
//                   const Text(
//                     'Emergency Responder',
//                     style: TextStyle(color: Colors.grey, fontSize: 12),
//                   ),
//                 ],
//               ),
//             ],
//           ),
//           Row(
//             children: [
//               Container(
//                 padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//                 decoration: BoxDecoration(
//                   color: _onDuty ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//                 child: Row(
//                   children: [
//                     Container(
//                       width: 8,
//                       height: 8,
//                       decoration: BoxDecoration(
//                         color: _onDuty ? Colors.green : Colors.grey,
//                         shape: BoxShape.circle,
//                       ),
//                     ),
//                     const SizedBox(width: 4),
//                     Text(
//                       _onDuty ? 'On Duty' : 'Off Duty',
//                       style: TextStyle(
//                         color: _onDuty ? Colors.green : Colors.grey,
//                         fontSize: 12,
//                         fontWeight: FontWeight.w600,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//               Switch(
//                 value: _onDuty,
//                 activeColor: Colors.green,
//                 onChanged: _toggleDutyStatus,
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildOffDutyContent() {
//     return Center(
//       child: Padding(
//         padding: const EdgeInsets.all(32),
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             Container(
//               padding: const EdgeInsets.all(32),
//               decoration: BoxDecoration(color: cardDark, shape: BoxShape.circle),
//               child: Icon(Icons.bedtime_outlined, size: 80, color: Colors.grey[600]),
//             ),
//             const SizedBox(height: 32),
//             const Text(
//               'You\'re Off Duty',
//               style: TextStyle(color: textPrimaryDark, fontSize: 28, fontWeight: FontWeight.bold),
//             ),
//             const SizedBox(height: 12),
//             Text(
//               'Toggle the switch above to go on duty.\nYour location will be shared with users in need.',
//               textAlign: TextAlign.center,
//               style: TextStyle(color: Colors.grey[500], fontSize: 16),
//             ),
//             const SizedBox(height: 48),
//             SizedBox(
//               width: double.infinity,
//               child: ElevatedButton.icon(
//                 style: ElevatedButton.styleFrom(
//                   backgroundColor: Colors.green,
//                   padding: const EdgeInsets.symmetric(vertical: 16),
//                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//                 ),
//                 onPressed: () => _toggleDutyStatus(true),
//                 icon: const Icon(Icons.play_arrow, color: Colors.white),
//                 label: const Text('GO ON DUTY', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   Widget _buildOnDutyContent() {
//     return Column(
//       children: [
//         Padding(
//           padding: const EdgeInsets.symmetric(horizontal: 16),
//           child: Row(
//             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//             children: [
//               Container(
//                 padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
//                 decoration: BoxDecoration(
//                   color: primary.withOpacity(0.2),
//                   borderRadius: BorderRadius.circular(20),
//                 ),
//                 child: Row(
//                   children: [
//                     const Icon(Icons.warning_amber, size: 16, color: primary),
//                     const SizedBox(width: 4),
//                     Text(
//                       '${_requests.length} Active',
//                       style: const TextStyle(color: primary, fontWeight: FontWeight.bold),
//                     ),
//                   ],
//                 ),
//               ),
//               IconButton(
//                 onPressed: _loadRequests,
//                 icon: const Icon(Icons.refresh, color: textPrimaryDark),
//               ),
//             ],
//           ),
//         ),
//         Expanded(
//           child: _isLoading
//               ? const Center(child: CircularProgressIndicator(color: primary))
//               : _requests.isEmpty
//               ? _buildEmptyState()
//               : RefreshIndicator(
//             onRefresh: _loadRequests,
//             color: primary,
//             child: ListView.builder(
//               padding: const EdgeInsets.all(16),
//               itemCount: _requests.length,
//               itemBuilder: (context, index) {
//                 final req = _requests[index];
//                 final double lat = (req['latitude'] as num?)?.toDouble() ?? 0.0;
//                 final double lng = (req['longitude'] as num?)?.toDouble() ?? 0.0;
//
//                 final double distanceKm = _distanceCalculator.as(
//                   LengthUnit.Kilometer,
//                   _responderLocation,
//                   LatLng(lat, lng),
//                 );
//
//                 return Padding(
//                   padding: const EdgeInsets.only(bottom: 12),
//                   child: _RequestCard(
//                     icon: _getIcon(req['emergency_type']),
//                     title: req['emergency_type'] ?? 'Emergency',
//                     userName: req['user_name'] ?? 'Unknown User',
//                     userPhone: req['user_phone'],
//                     distance: '${distanceKm.toStringAsFixed(1)} km',
//                     address: 'Lat: ${lat.toStringAsFixed(4)}, Lng: ${lng.toStringAsFixed(4)}',
//                     details: req['description'] ?? 'No additional details',
//                     createdAt: _formatTime(req['created_at']),
//                     onAccept: () => _acceptRequest(req),
//                   ),
//                 );
//               },
//             ),
//           ),
//         ),
//       ],
//     );
//   }
//
//   Widget _buildEmptyState() {
//     return Center(
//       child: Column(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           Icon(Icons.check_circle_outline, size: 80, color: Colors.grey[700]),
//           const SizedBox(height: 16),
//           const Text('No Active Requests', style: TextStyle(color: Colors.grey, fontSize: 20, fontWeight: FontWeight.bold)),
//           const SizedBox(height: 8),
//           Text('All emergencies have been handled', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
//           const SizedBox(height: 24),
//           ElevatedButton.icon(
//             style: ElevatedButton.styleFrom(backgroundColor: primary, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
//             onPressed: _loadRequests,
//             icon: const Icon(Icons.refresh, color: Colors.white),
//             label: const Text('Refresh', style: TextStyle(color: Colors.white)),
//           ),
//         ],
//       ),
//     );
//   }
// }
//
// // Request Card Widget
// class _RequestCard extends StatelessWidget {
//   final IconData icon;
//   final String title;
//   final String userName;
//   final String? userPhone;
//   final String distance;
//   final String address;
//   final String details;
//   final String createdAt;
//   final VoidCallback onAccept;
//
//   const _RequestCard({
//     required this.icon,
//     required this.title,
//     required this.userName,
//     this.userPhone,
//     required this.distance,
//     required this.address,
//     required this.details,
//     required this.createdAt,
//     required this.onAccept,
//   });
//
//   @override
//   Widget build(BuildContext context) {
//     const primary = Color(0xFFD93434);
//     const cardDark = Color(0xFF1E1E1E);
//
//     return Container(
//       decoration: BoxDecoration(
//         color: cardDark,
//         borderRadius: BorderRadius.circular(16),
//         border: Border.all(color: primary.withOpacity(0.3)),
//       ),
//       child: Column(
//         children: [
//           Container(
//             padding: const EdgeInsets.all(16),
//             decoration: BoxDecoration(
//               color: primary.withOpacity(0.1),
//               borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
//             ),
//             child: Row(
//               children: [
//                 Container(
//                   padding: const EdgeInsets.all(10),
//                   decoration: BoxDecoration(color: primary.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
//                   child: Icon(icon, color: primary, size: 24),
//                 ),
//                 const SizedBox(width: 12),
//                 Expanded(
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Text(title, style: const TextStyle(color: primary, fontWeight: FontWeight.bold, fontSize: 16)),
//                       Text(createdAt, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
//                     ],
//                   ),
//                 ),
//                 Container(
//                   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
//                   decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(20)),
//                   child: Text(distance, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
//                 ),
//               ],
//             ),
//           ),
//           Padding(
//             padding: const EdgeInsets.all(16),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Row(
//                   children: [
//                     CircleAvatar(
//                       radius: 20,
//                       backgroundColor: Colors.grey[800],
//                       child: Text(userName.isNotEmpty ? userName[0].toUpperCase() : 'U', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
//                     ),
//                     const SizedBox(width: 12),
//                     Expanded(
//                       child: Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           Text(userName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
//                           if (userPhone != null && userPhone!.isNotEmpty)
//                             Row(
//                               children: [
//                                 Icon(Icons.phone, size: 12, color: Colors.grey[500]),
//                                 const SizedBox(width: 4),
//                                 Text(userPhone!, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
//                               ],
//                             ),
//                         ],
//                       ),
//                     ),
//                   ],
//                 ),
//                 const SizedBox(height: 12),
//                 const Divider(color: Colors.grey, height: 1),
//                 const SizedBox(height: 12),
//                 Row(
//                   children: [
//                     Icon(Icons.location_on, size: 16, color: Colors.grey[500]),
//                     const SizedBox(width: 8),
//                     Expanded(child: Text(address, style: TextStyle(color: Colors.grey[400], fontSize: 13))),
//                   ],
//                 ),
//                 const SizedBox(height: 16),
//                 SizedBox(
//                   width: double.infinity,
//                   height: 48,
//                   child: ElevatedButton.icon(
//                     style: ElevatedButton.styleFrom(backgroundColor: primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
//                     onPressed: onAccept,
//                     icon: const Icon(Icons.check_circle, color: Colors.white),
//                     label: const Text('ACCEPT & RESPOND', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1)),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }