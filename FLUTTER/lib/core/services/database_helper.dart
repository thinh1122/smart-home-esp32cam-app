import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  /// Fires whenever a device is inserted or deleted — listeners should reload
  static final deviceListNotifier = ValueNotifier<int>(0);

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('smarthome.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 2, onCreate: _createDB, onUpgrade: _onUpgrade);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE members (
        id TEXT PRIMARY KEY,
        name TEXT,
        role TEXT,
        avatar TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT,
        action TEXT,
        detail TEXT,
        imageUrl TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE devices (
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
  }

  Future<void> insertMember(Map<String, dynamic> member) async {
    final db = await instance.database;
    await db.insert('members', member, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getAllMembers() async {
    final db = await instance.database;
    return await db.query('members');
  }

  Future<void> deleteMember(String id) async {
    final db = await instance.database;
    await db.delete('members', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> addLog(String action, String detail, {String? imageUrl}) async {
    final db = await instance.database;
    await db.insert('logs', {
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
  Future<int> insertDevice(Map<String, dynamic> device) async {
    final db = await instance.database;
    final id = await db.insert('devices', {
      ...device,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    deviceListNotifier.value++;
    return id;
  }

  Future<List<Map<String, dynamic>>> getAllDevices() async {
    final db = await instance.database;
    return await db.query('devices', orderBy: 'room, light_type');
  }

  Future<List<Map<String, dynamic>>> getDevicesByRoom(String room) async {
    final db = await instance.database;
    return await db.query('devices', where: 'room = ?', whereArgs: [room]);
  }

  Future<void> deleteDevice(int id) async {
    final db = await instance.database;
    await db.delete('devices', where: 'id = ?', whereArgs: [id]);
    deviceListNotifier.value++;
  }
}
