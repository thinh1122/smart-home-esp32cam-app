import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  /// Fires whenever a device is inserted or deleted — listeners should reload
  static final deviceListNotifier = ValueNotifier<int>(0);

  /// Fires whenever a device's ON/OFF state changes — listeners reload state map
  static final deviceStateNotifier = ValueNotifier<int>(0);

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('smarthome.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 8, onCreate: _createDB, onUpgrade: _onUpgrade);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        password TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE members (
        id TEXT PRIMARY KEY,
        user_id INTEGER NOT NULL DEFAULT 0,
        name TEXT,
        role TEXT,
        avatar TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL DEFAULT 0,
        timestamp TEXT,
        action TEXT,
        detail TEXT,
        imageUrl TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE devices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL DEFAULT 0,
        name TEXT NOT NULL,
        device_type TEXT NOT NULL,
        room TEXT NOT NULL,
        light_type TEXT,
        mqtt_topic TEXT,
        ble_mac TEXT,
        state TEXT NOT NULL DEFAULT 'OFF',
        watt REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS devices (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          device_type TEXT NOT NULL,
          room TEXT NOT NULL,
          light_type TEXT,
          mqtt_topic TEXT,
          ble_mac TEXT,
          created_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          email TEXT NOT NULL UNIQUE,
          password TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE devices ADD COLUMN user_id INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE members ADD COLUMN user_id INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 7) {
      await db.execute('ALTER TABLE logs ADD COLUMN user_id INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 8) {
      await db.execute("ALTER TABLE devices ADD COLUMN state TEXT NOT NULL DEFAULT 'OFF'");
      await db.execute('ALTER TABLE devices ADD COLUMN watt REAL NOT NULL DEFAULT 0');
    }
  }

  Future<void> insertMember(Map<String, dynamic> member, {required int userId}) async {
    final db = await instance.database;
    await db.insert('members', {...member, 'user_id': userId},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getAllMembers({required int userId}) async {
    final db = await instance.database;
    return await db.query('members', where: 'user_id = ?', whereArgs: [userId]);
  }

  Future<void> deleteMember(String id) async {
    final db = await instance.database;
    await db.delete('members', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> addLog(String action, String detail, {String? imageUrl, int userId = 0}) async {
    final db = await instance.database;
    await db.insert('logs', {
      'user_id': userId,
      'timestamp': DateTime.now().toIso8601String(),
      'action': action,
      'detail': detail,
      'imageUrl': imageUrl ?? '',
    });
  }

  Future<List<Map<String, dynamic>>> getLogs({int limit = 50}) async {
    final db = await instance.database;
    return await db.query('logs', orderBy: 'timestamp DESC', limit: limit);
  }

  Future<void> clearOldLogs(int keepCount) async {
    final db = await instance.database;
    await db.rawDelete('''
      DELETE FROM logs WHERE id NOT IN (
        SELECT id FROM logs ORDER BY timestamp DESC LIMIT ?
      )
    ''', [keepCount]);
  }

  // ── Devices ──────────────────────────────────────────────
  Future<int> insertDevice(Map<String, dynamic> device, {required int userId}) async {
    final db = await instance.database;
    final id = await db.insert('devices', {
      ...device,
      'user_id': userId,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    deviceListNotifier.value++;
    return id;
  }

  Future<List<Map<String, dynamic>>> getAllDevices({required int userId}) async {
    final db = await instance.database;
    return await db.query('devices',
        where: 'user_id = ?', whereArgs: [userId], orderBy: 'room, light_type');
  }

  Future<List<Map<String, dynamic>>> getDevicesByRoom(String room, {required int userId}) async {
    final db = await instance.database;
    return await db.query('devices',
        where: 'room = ? AND user_id = ?', whereArgs: [room, userId]);
  }

  Future<void> deleteDevice(int id) async {
    final db = await instance.database;
    await db.delete('devices', where: 'id = ?', whereArgs: [id]);
    deviceListNotifier.value++;
  }

  Future<void> updateDeviceState(String room, String state, {required int userId}) async {
    final db = await instance.database;
    await db.update('devices', {'state': state},
        where: 'room = ? AND user_id = ?', whereArgs: [room, userId]);
    deviceStateNotifier.value++;
  }

  Future<void> updateDeviceWatt(String room, double watt, {required int userId}) async {
    final db = await instance.database;
    await db.update('devices', {'watt': watt},
        where: 'room = ? AND user_id = ?', whereArgs: [room, userId]);
  }

  // ── Users ─────────────────────────────────────────────────
  /// Gán lại user_id cho logs và members cũ có user_id = 0
  Future<void> repairOrphanData() async {
    final db = await instance.database;
    final users = await db.query('users');

    // Fix logs: detail có dạng "Tên (email)"
    for (final user in users) {
      final email = user['email'] as String;
      final id    = user['id'] as int;
      await db.rawUpdate('''
        UPDATE logs SET user_id = ?
        WHERE user_id = 0 AND detail LIKE ?
      ''', [id, '%$email%']);
    }

    // Fix members: nếu chỉ có 1 user thật (không phải admin), gán orphan cho họ
    final realUsers = users.where(
        (u) => (u['email'] as String).toLowerCase() != 'admin@gmail.com').toList();
    if (realUsers.length == 1) {
      final onlyUserId = realUsers.first['id'] as int;
      await db.rawUpdate('''
        UPDATE members SET user_id = ?
        WHERE user_id = 0
      ''', [onlyUserId]);
    }
  }

  Future<void> ensureAdminAccount() async {
    final db = await instance.database;
    final existing = await db.query('users',
        where: 'email = ?', whereArgs: ['admin@gmail.com'], limit: 1);
    if (existing.isEmpty) {
      await db.insert('users', {
        'name': 'Admin',
        'email': 'admin@gmail.com',
        'password': 'ADMIN123',
        'created_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      // Đảm bảo password luôn đúng
      await db.update('users', {'password': 'ADMIN123'},
          where: 'email = ?', whereArgs: ['admin@gmail.com']);
    }
  }

  Future<int> insertUser(String name, String email, String password) async {
    final db = await instance.database;
    return await db.insert('users', {
      'name': name,
      'email': email.toLowerCase().trim(),
      'password': password,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    final db = await instance.database;
    final result = await db.query('users',
        where: 'email = ?', whereArgs: [email.toLowerCase().trim()], limit: 1);
    return result.isEmpty ? null : result.first;
  }

  Future<bool> emailExists(String email) async {
    final user = await getUserByEmail(email);
    return user != null;
  }

  Future<Map<String, dynamic>?> login(String email, String password) async {
    final db = await instance.database;
    final result = await db.query('users',
        where: 'email = ? AND password = ?',
        whereArgs: [email.toLowerCase().trim(), password],
        limit: 1);
    return result.isEmpty ? null : result.first;
  }

  Future<void> updateUserName(int id, String name) async {
    final db = await instance.database;
    await db.update('users', {'name': name}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateUserPassword(int id, String newPassword) async {
    final db = await instance.database;
    await db.update('users', {'password': newPassword},
        where: 'id = ?', whereArgs: [id]);
  }

  // ── Admin ─────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final db = await instance.database;
    return await db.query('users', orderBy: 'created_at DESC');
  }

  Future<List<Map<String, dynamic>>> getDevicesByUserId(int userId) async {
    final db = await instance.database;
    return await db.query('devices',
        where: 'user_id = ?', whereArgs: [userId], orderBy: 'created_at DESC');
  }

  Future<List<Map<String, dynamic>>> getMembersByUserId(int userId) async {
    final db = await instance.database;
    return await db.query('members',
        where: 'user_id = ?', whereArgs: [userId]);
  }

  Future<List<Map<String, dynamic>>> getAllLogs({int limit = 100}) async {
    final db = await instance.database;
    return await db.query('logs', orderBy: 'timestamp DESC', limit: limit);
  }

  Future<List<Map<String, dynamic>>> getLogsByUserId(int userId, {int limit = 100}) async {
    final db = await instance.database;
    return await db.query('logs',
        where: 'user_id = ?', whereArgs: [userId],
        orderBy: 'timestamp DESC', limit: limit);
  }

  Future<void> deleteUser(int id) async {
    final db = await instance.database;
    await db.delete('devices', where: 'user_id = ?', whereArgs: [id]);
    await db.delete('members', where: 'user_id = ?', whereArgs: [id]);
    await db.delete('users', where: 'id = ?', whereArgs: [id]);
  }
}
