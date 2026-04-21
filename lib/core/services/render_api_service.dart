import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';

class RenderAPIService {
  static final RenderAPIService _instance = RenderAPIService._internal();
  factory RenderAPIService() => _instance;
  RenderAPIService._internal();

  final String _baseUrl = AppConfig.renderApiUrl;
  final Map<String, String> _headers = {
    'Content-Type': 'application/json',
    'X-API-Key': AppConfig.renderApiKey,
  };

  Future<List<Map<String, dynamic>>> getMembers() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/members'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) return List<Map<String, dynamic>>.from(data['data']);
      }
      return [];
    } catch (e) {
      debugPrint('RenderAPI getMembers error: $e');
      return [];
    }
  }

  Future<bool> enrollMember({
    required String userId,
    required String name,
    String role = 'Member',
    String? avatarUrl,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/members/enroll'),
            headers: _headers,
            body: jsonEncode({'user_id': userId, 'name': name, 'role': role, 'avatar_url': avatarUrl}),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['success'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('RenderAPI enrollMember error: $e');
      return false;
    }
  }

  Future<bool> deleteMember(String userId) async {
    try {
      final res = await http
          .delete(Uri.parse('$_baseUrl/members/$userId'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body)['success'] == true;
      return false;
    } catch (e) {
      debugPrint('RenderAPI deleteMember error: $e');
      return false;
    }
  }

  Future<bool> controlDevice({
    required String deviceType,
    required String deviceName,
    required String action,
    Map<String, dynamic>? payload,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/devices/control'),
            headers: _headers,
            body: jsonEncode({
              'device_type': deviceType,
              'device_name': deviceName,
              'action': action,
              'payload': payload ?? {},
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body)['success'] == true;
      return false;
    } catch (e) {
      debugPrint('RenderAPI controlDevice error: $e');
      return false;
    }
  }

  Future<bool> checkHealth() async {
    try {
      final res = await http
          .get(Uri.parse('${_baseUrl.replaceAll('/api', '')}/health'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) return jsonDecode(res.body)['status'] == 'ok';
      return false;
    } catch (e) {
      return false;
    }
  }
}
