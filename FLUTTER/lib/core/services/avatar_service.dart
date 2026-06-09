import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AvatarService extends ValueNotifier<String?> {
  static final AvatarService instance = AvatarService._();
  AvatarService._() : super(null) {
    _load();
  }

  static const _key = 'user_avatar_path';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_key);
    if (path != null && File(path).existsSync()) {
      value = path;
    }
  }

  // Mở thư viện ảnh, trả về true nếu đổi thành công
  Future<bool> pickFromGallery() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null) return false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, picked.path);
    value = picked.path;
    return true;
  }

  // Widget hiển thị avatar (dùng chung ở home + profile)
  ImageProvider? get imageProvider {
    if (value != null && File(value!).existsSync()) {
      return FileImage(File(value!));
    }
    return null;
  }
}
