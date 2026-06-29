// lib/services/routing_service.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RoutingService {
  // Using OSRM (Open Source Routing Machine) - Free routing API
  static const String _baseUrl = 'https://router.project-osrm.org/route/v1/driving';

  static Future<RouteInfo?> getRoute(LatLng origin, LatLng destination) async {
    try {
      final url = '$_baseUrl/${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}?overview=full&geometries=geojson&steps=true';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final geometry = route['geometry']['coordinates'] as List;

          // Convert coordinates to LatLng list
          final List<LatLng> routePoints = geometry.map<LatLng>((coord) {
            return LatLng(coord[1].toDouble(), coord[0].toDouble());
          }).toList();

          // Get duration and distance
          final double durationSeconds = route['duration'].toDouble();
          final double distanceMeters = route['distance'].toDouble();

          // Get turn-by-turn instructions
          final List<NavigationStep> steps = [];
          if (route['legs'] != null && route['legs'].isNotEmpty) {
            final leg = route['legs'][0];
            for (var step in leg['steps']) {
              steps.add(NavigationStep(
                instruction: step['maneuver']['type'] ?? '',
                modifier: step['maneuver']['modifier'] ?? '',
                distance: step['distance'].toDouble(),
                duration: step['duration'].toDouble(),
                name: step['name'] ?? '',
                location: LatLng(
                  step['maneuver']['location'][1].toDouble(),
                  step['maneuver']['location'][0].toDouble(),
                ),
              ));
            }
          }

          return RouteInfo(
            routePoints: routePoints,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            steps: steps,
          );
        }
      }
      return null;
    } catch (e) {
      print('Routing Error: $e');
      return null;
    }
  }
}

class RouteInfo {
  final List<LatLng> routePoints;
  final double durationSeconds;
  final double distanceMeters;
  final List<NavigationStep> steps;

  RouteInfo({
    required this.routePoints,
    required this.durationSeconds,
    required this.distanceMeters,
    required this.steps,
  });

  String get formattedDuration {
    final minutes = (durationSeconds / 60).round();
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return '${hours}h ${remainingMinutes}m';
  }

  String get formattedDistance {
    if (distanceMeters < 1000) {
      return '${distanceMeters.round()} m';
    }
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }
}

class NavigationStep {
  final String instruction;
  final String modifier;
  final double distance;
  final double duration;
  final String name;
  final LatLng location;

  NavigationStep({
    required this.instruction,
    required this.modifier,
    required this.distance,
    required this.duration,
    required this.name,
    required this.location,
  });

  IconData get icon {
    switch (instruction) {
      case 'turn':
        if (modifier.contains('left')) return Icons.turn_left;
        if (modifier.contains('right')) return Icons.turn_right;
        return Icons.straight;
      case 'merge':
        return Icons.merge_type;
      case 'arrive':
        return Icons.location_on;
      case 'depart':
        return Icons.my_location;
      default:
        return Icons.arrow_upward;
    }
  }

  String get displayInstruction {
    String action = '';
    switch (instruction) {
      case 'turn':
        action = modifier.contains('left') ? 'Turn left' :
        modifier.contains('right') ? 'Turn right' : 'Continue';
        break;
      case 'merge':
        action = 'Merge';
        break;
      case 'arrive':
        action = 'Arrive at destination';
        break;
      case 'depart':
        action = 'Start';
        break;
      default:
        action = 'Continue';
    }
    return name.isNotEmpty ? '$action onto $name' : action;
  }
}