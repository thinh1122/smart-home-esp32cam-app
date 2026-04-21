import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

class Member {
  final String id;
  final String name;
  final String role;
  final String avatar;

  const Member({
    required this.id,
    required this.name,
    required this.role,
    required this.avatar,
  });

  factory Member.fromMap(Map<String, dynamic> map) => Member(
    id: map['id'] as String,
    name: map['name'] as String,
    role: map['role'] as String,
    avatar: map['avatar'] as String,
  );

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'role': role, 'avatar': avatar};

  bool get isNetworkAvatar => avatar.startsWith('http');

  // Returns Uint8List for MemoryImage, or null if network/invalid
  Uint8List? get avatarBytes {
    if (isNetworkAvatar) return null;
    try { return base64Decode(avatar); } catch (_) { return null; }
  }

  ImageProvider get imageProvider => isNetworkAvatar
      ? NetworkImage(avatar) as ImageProvider
      : MemoryImage(avatarBytes ?? Uint8List(0));
}
