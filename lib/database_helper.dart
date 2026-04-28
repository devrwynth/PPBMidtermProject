import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'images_database.db');
    return await openDatabase(
      path,
      version: 3, // Incremented version to support userId
      onCreate: _onCreate,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE images ADD COLUMN uploaded INTEGER DEFAULT 0');
          await db.execute('ALTER TABLE images ADD COLUMN firestore_id TEXT');
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE images ADD COLUMN userId TEXT');
        }
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE images (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        path TEXT,
        timestamp TEXT,
        uploaded INTEGER DEFAULT 0,
        firestore_id TEXT,
        userId TEXT
      )
    ''');
  }

  Future<int> insertImage(String imagePath, String userId) async {
    Database db = await database;
    return await db.insert(
      'images',
      {
        'path': imagePath,
        'timestamp': DateTime.now().toIso8601String(),
        'uploaded': 0,
        'userId': userId,
      },
    );
  }

  Future<int> updateUploadStatus(int id, int status, String? firestoreId) async {
    Database db = await database;
    return await db.update(
      'images',
      {'uploaded': status, 'firestore_id': firestoreId},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteImage(int id, String userId) async {
    Database db = await database;
    return await db.delete(
      'images',
      where: 'id = ? AND userId = ?',
      whereArgs: [id, userId],
    );
  }

  Future<List<Map<String, dynamic>>> getImages(String userId) async {
    Database db = await database;
    return await db.query(
      'images',
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'id DESC',
    );
  }
}
