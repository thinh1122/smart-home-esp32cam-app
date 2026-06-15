import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_helper.dart';
import 'avatar_service.dart';

class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  static const _keyUserId    = 'auth_user_id';
  static const _keyUserName  = 'auth_user_name';
  static const _keyUserEmail = 'auth_user_email';
  static const _keyLoggedIn  = 'auth_logged_in';

  final ValueNotifier<bool> isLoggedIn = ValueNotifier(false);
  Map<String, dynamic>? _currentUser;

  Map<String, dynamic>? get currentUser => _currentUser;
  String get userName  => _currentUser?['name'] ?? '';
  String get userEmail => _currentUser?['email'] ?? '';
  int    get userId    => _currentUser?['id'] ?? 0;
  bool   get isAdmin   => userEmail.toLowerCase() == 'admin@gmail.com';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.getBool(_keyLoggedIn) ?? false;
    if (loggedIn) {
      final email = prefs.getString(_keyUserEmail) ?? '';
      final user = await DatabaseHelper.instance.getUserByEmail(email);
      if (user != null) {
        _currentUser = user;
        await AvatarService.instance.loadForUser(user['id']);
        isLoggedIn.value = true;
      } else {
        await _clearPrefs(prefs);
      }
    }
  }

  /// Trả về null nếu thành công, hoặc thông báo lỗi
  Future<String?> register(String name, String email, String password) async {
    if (name.trim().isEmpty) return 'Vui lòng nhập họ tên';
    if (!_validEmail(email)) return 'Email không hợp lệ';
    if (password.length < 6) return 'Mật khẩu ít nhất 6 ký tự';

    final exists = await DatabaseHelper.instance.emailExists(email);
    if (exists) return 'Email này đã được đăng ký';

    try {
      final id = await DatabaseHelper.instance.insertUser(
          name.trim(), email.trim(), password);
      _currentUser = {
        'id': id,
        'name': name.trim(),
        'email': email.toLowerCase().trim(),
        'password': password,
      };
      await _savePrefs();
      await AvatarService.instance.loadForUser(id);
      isLoggedIn.value = true;
      return null;
    } catch (e) {
      debugPrint('Register error: $e');
      return 'Đăng ký thất bại: $e';
    }
  }

  /// Trả về null nếu thành công, hoặc thông báo lỗi
  Future<String?> login(String email, String password) async {
    if (!_validEmail(email)) return 'Email không hợp lệ';
    if (password.isEmpty) return 'Vui lòng nhập mật khẩu';

    final user = await DatabaseHelper.instance.login(email, password);
    if (user == null) return 'Email hoặc mật khẩu không đúng';

    _currentUser = user;
    await _savePrefs();
    await AvatarService.instance.loadForUser(user['id']);
    isLoggedIn.value = true;
    return null;
  }

  Future<void> logout() async {
    _currentUser = null;
    isLoggedIn.value = false;
    await AvatarService.instance.clear();
    final prefs = await SharedPreferences.getInstance();
    await _clearPrefs(prefs);
  }

  Future<String?> changePassword(String oldPass, String newPass) async {
    if (_currentUser == null) return 'Chưa đăng nhập';
    if (_currentUser!['password'] != oldPass) return 'Mật khẩu cũ không đúng';
    if (newPass.length < 6) return 'Mật khẩu mới ít nhất 6 ký tự';
    await DatabaseHelper.instance.updateUserPassword(userId, newPass);
    _currentUser = {..._currentUser!, 'password': newPass};
    return null;
  }

  Future<String?> changeName(String newName) async {
    if (_currentUser == null) return 'Chưa đăng nhập';
    if (newName.trim().isEmpty) return 'Tên không được để trống';
    await DatabaseHelper.instance.updateUserName(userId, newName.trim());
    _currentUser = {..._currentUser!, 'name': newName.trim()};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserName, newName.trim());
    return null;
  }

  // ── Private helpers ──────────────────────────────────────
  bool _validEmail(String e) =>
      RegExp(r'^[\w\.-]+@[\w\.-]+\.\w{2,}$').hasMatch(e.trim());

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyLoggedIn, true);
    await prefs.setInt(_keyUserId, _currentUser!['id']);
    await prefs.setString(_keyUserName, _currentUser!['name']);
    await prefs.setString(_keyUserEmail, _currentUser!['email']);
  }

  Future<void> _clearPrefs(SharedPreferences prefs) async {
    await prefs.remove(_keyLoggedIn);
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyUserName);
    await prefs.remove(_keyUserEmail);
  }
}
