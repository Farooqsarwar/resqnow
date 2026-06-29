// ignore_for_file: avoid_print

import 'package:url_launcher/url_launcher.dart';

class CallService {
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  /// Make a phone call to the given phone number
  /// Opens phone dialer with number pre-filled (ACTION_DIAL)
  Future<bool> makeCall(String phoneNumber) async {
    try {
      // Remove all non-numeric characters except + and spaces
      String formattedNumber = phoneNumber
          .replaceAll(RegExp(r'[^\d+\s]'), '')
          .replaceAll(' ', '');

      print('📞 Attempting to call: $formattedNumber');

      // Use tel: scheme - opens phone dialer (ACTION_DIAL)
      final Uri telUri = Uri(scheme: 'tel', path: formattedNumber);

      // Launch with external application mode to open phone dialer
      final bool launched = await launchUrl(
        telUri,
        mode: LaunchMode.externalApplication,
      );

      if (launched) {
        print('✅ Phone dialer opened with $formattedNumber');
        return true;
      } else {
        // Fallback: Show SMS dialog with emergency message
        print('⚠️  Tel scheme not supported, opening SMS instead');
        return await sendSMS(
          formattedNumber,
          'Emergency: Need immediate assistance. My location is available.',
        );
      }
    } catch (e) {
      print('❌ Error making call: $e');
      return false;
    }
  }

  /// Send SMS to the given phone number
  Future<bool> sendSMS(String phoneNumber, String message) async {
    try {
      // Remove all non-numeric characters except + and spaces
      String formattedNumber = phoneNumber
          .replaceAll(RegExp(r'[^\d+\s]'), '')
          .replaceAll(' ', '');

      final Uri uri = Uri(
        scheme: 'sms',
        path: formattedNumber,
        queryParameters: {'body': message},
      );

      print('💬 Attempting to send SMS to: $formattedNumber');

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        print('✅ SMS prompt opened for $formattedNumber');
        return true;
      } else {
        print('❌ Cannot launch sms: on this device');
        return false;
      }
    } catch (e) {
      print('❌ Error sending SMS: $e');
      return false;
    }
  }

  /// Call emergency number (911, 999, 112, etc depending on region)
  Future<bool> callEmergency() async {
    // Pakistan emergency number
    return makeCall('1122');
  }

  /// Send location via SMS for SOS
  Future<bool> sendSOSLocation(
    String phoneNumber,
    double latitude,
    double longitude,
    String address,
  ) async {
    final message =
        '''
EMERGENCY SOS
Location: $address
Coordinates: $latitude, $longitude
Google Maps: https://maps.google.com/?q=$latitude,$longitude
''';
    return sendSMS(phoneNumber, message);
  }
}
