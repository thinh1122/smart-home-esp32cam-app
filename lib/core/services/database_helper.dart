import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('smarthome.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
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
}
