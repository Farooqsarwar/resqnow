// lib/screens/ResponderHistoryScreen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class RescuerHistoryScreen extends StatefulWidget {
  const RescuerHistoryScreen({super.key});

  @override
  State<RescuerHistoryScreen> createState() => _RescuerHistoryScreenState();
}

class _RescuerHistoryScreenState extends State<RescuerHistoryScreen> {
  static const Color primary = Color(0xFFD93434);
  static const Color backgroundDark = Color(0xFF121212);
  static const Color cardDark = Color(0xFF1E1E1E);
  static const Color textPrimary = Color(0xFFE0E0E0);
  static const Color textSecondary = Color(0xFF8E8E93);

  final SupabaseClient supabase = Supabase.instance.client;

  bool _isLoading = true;
  List<Map<String, dynamic>> _rescueHistory = [];
  Map<String, dynamic> _stats = {
    'totalRescues': 0,
    'averageRating': 0.0,
    'totalRatings': 0,
  };

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Fetch completed rescues
      final rescuesData = await supabase
          .from('emergency_requests')
          .select()
          .eq('responder_id', userId)
          .eq('status', 'completed')
          .order('created_at', ascending: false);

      // Fetch feedback/ratings
      final feedbackData = await supabase
          .from('feedback')
          .select()
          .eq('responder_id', userId);

      // Create a map of request_id to feedback
      Map<String, Map<String, dynamic>> feedbackMap = {};
      for (var feedback in feedbackData) {
        feedbackMap[feedback['request_id']] = feedback;
      }

      // Enrich rescue data with user info and feedback
      List<Map<String, dynamic>> enrichedRescues = [];
      for (var rescue in rescuesData) {
        final victimId = rescue['user_id'] as String?;
        String victimName = 'Unknown User';

        if (victimId != null) {
          try {
            final profileData = await supabase
                .from('profiles')
                .select('name, email')
                .eq('id', victimId)
                .maybeSingle();

            if (profileData != null) {
              victimName = profileData['name'] ??
                  profileData['email']?.toString().split('@').first ??
                  'User';
            }
          } catch (e) {
            debugPrint('Error fetching victim profile: $e');
          }
        }

        final feedback = feedbackMap[rescue['id']];

        enrichedRescues.add({
          ...rescue,
          'victim_name': victimName,
          'rating': feedback?['rating'],
          'feedback_comment': feedback?['comment'],
        });
      }

      // Calculate stats
      int totalRescues = enrichedRescues.length;
      int totalRatings = feedbackData.length;
      double averageRating = 0.0;

      if (totalRatings > 0) {
        int sumRatings = 0;
        for (var feedback in feedbackData) {
          sumRatings += (feedback['rating'] as int?) ?? 0;
        }
        averageRating = sumRatings / totalRatings;
      }

      if (mounted) {
        setState(() {
          _rescueHistory = enrichedRescues;
          _stats = {
            'totalRescues': totalRescues,
            'averageRating': averageRating,
            'totalRatings': totalRatings,
          };
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading history: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading history: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  IconData _getEmergencyIcon(String? type) {
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

  Color _getEmergencyColor(String? type) {
    switch (type) {
      case 'Medical':
        return Colors.red;
      case 'Fire':
        return Colors.orange;
      case 'Crime':
        return Colors.blue;
      case 'Accident':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(String? timestamp) {
    if (timestamp == null) return '';
    try {
      final dt = DateTime.parse(timestamp);
      return DateFormat('MMM dd, yyyy • hh:mm a').format(dt);
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundDark,
      appBar: AppBar(
        backgroundColor: backgroundDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Rescue History',
          style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: textPrimary),
            onPressed: _loadHistory,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: primary))
          : RefreshIndicator(
        onRefresh: _loadHistory,
        color: primary,
        child: CustomScrollView(
          slivers: [
            // Stats Section
            SliverToBoxAdapter(
              child: _buildStatsSection(),
            ),

            // History List Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                child: Row(
                  children: [
                    const Icon(Icons.history, color: textSecondary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Completed Rescues (${_rescueHistory.length})',
                      style: const TextStyle(
                        color: textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // History List or Empty State
            _rescueHistory.isEmpty
                ? SliverFillRemaining(child: _buildEmptyState())
                : SliverList(
              delegate: SliverChildBuilderDelegate(
                    (context, index) {
                  final rescue = _rescueHistory[index];
                  return _buildRescueCard(rescue);
                },
                childCount: _rescueHistory.length,
              ),
            ),

            // Bottom Padding
            const SliverToBoxAdapter(
              child: SizedBox(height: 24),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSection() {
    final totalRescues = _stats['totalRescues'] as int;
    final averageRating = _stats['averageRating'] as double;
    final totalRatings = _stats['totalRatings'] as int;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primary.withOpacity(0.8),
            primary.withOpacity(0.6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: primary.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          // Title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.emoji_events, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your Impact',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Lives saved through your service',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Stats Row
          Row(
            children: [
              // Total Rescues
              Expanded(
                child: _buildStatItem(
                  icon: Icons.check_circle,
                  value: totalRescues.toString(),
                  label: 'Rescues',
                ),
              ),
              Container(
                width: 1,
                height: 50,
                color: Colors.white.withOpacity(0.3),
              ),
              // Average Rating
              Expanded(
                child: _buildStatItem(
                  icon: Icons.star,
                  value: averageRating > 0 ? averageRating.toStringAsFixed(1) : '-',
                  label: 'Avg Rating',
                ),
              ),
              Container(
                width: 1,
                height: 50,
                color: Colors.white.withOpacity(0.3),
              ),
              // Total Ratings
              Expanded(
                child: _buildStatItem(
                  icon: Icons.rate_review,
                  value: totalRatings.toString(),
                  label: 'Reviews',
                ),
              ),
            ],
          ),

          // Rating Stars
          if (averageRating > 0)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  if (index < averageRating.floor()) {
                    return const Icon(Icons.star, color: Colors.amber, size: 24);
                  } else if (index < averageRating) {
                    return const Icon(Icons.star_half, color: Colors.amber, size: 24);
                  } else {
                    return Icon(Icons.star_border, color: Colors.amber.withOpacity(0.5), size: 24);
                  }
                }),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildRescueCard(Map<String, dynamic> rescue) {
    final emergencyType = rescue['emergency_type'] as String?;
    final victimName = rescue['victim_name'] as String? ?? 'Unknown';
    final createdAt = rescue['created_at'] as String?;
    final rating = rescue['rating'] as int?;
    final comment = rescue['feedback_comment'] as String?;
    final description = rescue['description'] as String?;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _getEmergencyColor(emergencyType).withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _getEmergencyColor(emergencyType).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getEmergencyIcon(emergencyType),
                    color: _getEmergencyColor(emergencyType),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        emergencyType ?? 'Emergency',
                        style: TextStyle(
                          color: _getEmergencyColor(emergencyType),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _formatDate(createdAt),
                        style: const TextStyle(
                          color: textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, color: Colors.green, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'Completed',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Victim Info
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.grey.withOpacity(0.2),
                      child: Text(
                        victimName.isNotEmpty ? victimName[0].toUpperCase() : 'U',
                        style: const TextStyle(
                          color: textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Rescued Person',
                            style: TextStyle(color: textSecondary, fontSize: 10),
                          ),
                          Text(
                            victimName,
                            style: const TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Rating
                    if (rating != null)
                      Row(
                        children: List.generate(5, (index) {
                          return Icon(
                            index < rating ? Icons.star : Icons.star_border,
                            color: Colors.amber,
                            size: 18,
                          );
                        }),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'No Rating',
                          style: TextStyle(color: textSecondary, fontSize: 10),
                        ),
                      ),
                  ],
                ),

                // Description
                if (description != null && description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.notes, size: 16, color: textSecondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            description,
                            style: const TextStyle(color: textSecondary, fontSize: 13),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Feedback Comment
                if (comment != null && comment.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.withOpacity(0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.format_quote, size: 16, color: Colors.amber),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '"$comment"',
                            style: TextStyle(
                              color: Colors.amber.shade200,
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history_toggle_off,
            size: 80,
            color: Colors.grey.shade700,
          ),
          const SizedBox(height: 16),
          const Text(
            'No Rescue History Yet',
            style: TextStyle(
              color: textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your completed rescues will appear here',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
        ],
      ),
    );
  }
}