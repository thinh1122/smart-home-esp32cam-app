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
    // Bảng Thành Viên (Members)
    await db.execute('''
      CREATE TABLE members (
        id TEXT PRIMARY KEY,
        name TEXT,
        role TEXT,
        avatar TEXT
      )
    ''');

    // Bảng Lịch sử (Logs)
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

  // ===== CÁC HÀM XỬ LÝ (CRUD) CHO MEMBERS =====
  
  // Thêm thành viên mới
  Future<void> insertMember(Map<String, dynamic> member) async {
    final db = await instance.database;
    await db.insert('members', member, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Lấy danh sách thành viên
  Future<List<Map<String, dynamic>>> getAllMembers() async {
    final db = await instance.database;
    return await db.query('members');
  }

  // Xoá thành viên
  Future<void> deleteMember(String id) async {
    final db = await instance.database;
    await db.delete('members', where: 'id = ?', whereArgs: [id]);
  }

  // ===== CÁC HÀM XỬ LÝ (CRUD) CHO LOGS =====

  // Ghi lại lịch sử hoạt động
  Future<void> addLog(String action, String detail, {String? imageUrl}) async {
    final db = await instance.database;
    await db.insert('logs', {
      'timestamp': DateTime.now().toIso8601String(),
      'action': action,
      'detail': detail,
      'imageUrl': imageUrl ?? '',
    });
  }

  // Lấy lịch sử hoạt động
  Future<List<Map<String, dynamic>>> getLogs() async {
    final db = await instance.database;
    return await db.query('logs', orderBy: 'timestamp DESC'); // Sắp xếp giờ mới nhất lên đầu
  }
}
