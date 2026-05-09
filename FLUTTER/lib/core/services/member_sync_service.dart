import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'database_helper.dart';

class MemberSyncService {
  static final MemberSyncService instance = MemberSyncService._();
  MemberSyncService._();

  // Pull members từ AI server về SQLite local
  Future<void> syncFromServer() async {
    try {
      final res = await http
          .get(Uri.parse(AppConfig.membersUrl))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return;

      final List<dynamic> serverMembers = jsonDecode(res.body);
      for (final m in serverMembers) {
        final id = m['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        await DatabaseHelper.instance.insertMember({
          'id': id,
          'name': m['name'] ?? '',
          'role': m['role'] ?? 'Face ID',
          'avatar': m['avatar'] ?? '',
        });
      }
    } catch (_) {}
  }

  // Enroll 1 pose lên AI server
  // Returns: null on success, error message on failure
  Future<String?> enrollPose({
    required String id,
    required String name,
    required String role,
    required String imageBase64,
    required int pose, // 1, 2, 3
    String avatar = '',
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse(AppConfig.enrollUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'id': id,
              'name': name,
              'role': role,
              'avatar': avatar,
              'image_base64': imageBase64,
              'pose': pose,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) return null;
      final body = jsonDecode(res.body);
      return body['error'] ?? 'Server error ${res.statusCode}';
    } catch (e) {
      return 'Không kết nối được AI server';
    }
  }

  // Xóa member trên AI server
  Future<bool> deleteFromServer(String id, String name) async {
    try {
      final res = await http
          .post(
            Uri.parse(AppConfig.deleteUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'id': id, 'name': name}),
          )
          .timeout(const Duration(seconds: 6));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
