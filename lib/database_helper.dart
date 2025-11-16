// database_helper.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'sound_detector.db');
    return await openDatabase(
      path,
      version: 3, // Incremented version
      onCreate: _createTables,
      onUpgrade: _upgradeDatabase,
    );
  }

  Future<void> _createTables(Database db, int version) async {
    // Users table
    await db.execute('''
      CREATE TABLE users(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        email TEXT UNIQUE NOT NULL,
        password TEXT NOT NULL,
        created_at TEXT NOT NULL,
        reset_token TEXT,
        reset_token_expiry TEXT
      )
    ''');

    // Sound detections table
    await db.execute('''
      CREATE TABLE sound_detections(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        sound_class TEXT NOT NULL,
        confidence REAL NOT NULL,
        timestamp TEXT NOT NULL,
        latitude REAL,
        longitude REAL,
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
      )
    ''');

    // Create indexes for better performance
    await db.execute('CREATE INDEX idx_user_id ON sound_detections(user_id)');
    await db
        .execute('CREATE INDEX idx_timestamp ON sound_detections(timestamp)');
  }

  Future<void> _upgradeDatabase(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS sound_detections(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id INTEGER NOT NULL,
          sound_class TEXT NOT NULL,
          confidence REAL NOT NULL,
          timestamp TEXT NOT NULL,
          latitude REAL,
          longitude REAL,
          FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE users ADD COLUMN reset_token TEXT');
      await db.execute('ALTER TABLE users ADD COLUMN reset_token_expiry TEXT');
    }
  }

  // User operations
  Future<int> registerUser(
      String username, String email, String password) async {
    final db = await database;

    // Check if user already exists
    final existingUser = await db.query(
      'users',
      where: 'username = ? OR email = ?',
      whereArgs: [username, email],
    );

    if (existingUser.isNotEmpty) {
      throw Exception('Username or email already exists');
    }

    // Insert new user
    return await db.insert('users', {
      'username': username,
      'email': email,
      'password': password, // In real app, hash this password!
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<Map<String, dynamic>?> loginUser(
      String username, String password) async {
    final db = await database;

    final user = await db.query(
      'users',
      where: 'username = ? AND password = ?',
      whereArgs: [username, password],
    );

    return user.isNotEmpty ? user.first : null;
  }

  Future<void> setPasswordResetToken(String email, String token) async {
    final db = await database;
    final expiry = DateTime.now().add(const Duration(hours: 1)).toIso8601String();
    await db.update(
      'users',
      {'reset_token': token, 'reset_token_expiry': expiry},
      where: 'email = ?',
      whereArgs: [email],
    );
  }

  Future<Map<String, dynamic>?> getUserByResetToken(String token) async {
    final db = await database;
    final user = await db.query(
      'users',
      where: 'reset_token = ?',
      whereArgs: [token],
    );

    if (user.isNotEmpty) {
      final expiry = DateTime.parse(user.first['reset_token_expiry'] as String);
      if (expiry.isAfter(DateTime.now())) {
        return user.first;
      }
    }

    return null;
  }

  Future<int> updateUserPassword(String email, String newPassword) async {
    final db = await database;
    return await db.update(
      'users',
      {'password': newPassword, 'reset_token': null, 'reset_token_expiry': null},
      where: 'email = ?',
      whereArgs: [email],
    );
  }

  // Sound detection operations
  Future<int> insertDetection(
      int userId, String soundClass, double confidence) async {
    final db = await database;

    return await db.insert('sound_detections', {
      'user_id': userId,
      'sound_class': soundClass,
      'confidence': confidence,
      'timestamp': DateTime.now().toIso8601String(),
      'latitude': null, // You can add GPS later
      'longitude': null,
    });
  }

  Future<List<Map<String, dynamic>>> getUserDetections(int userId) async {
    final db = await database;

    return await db.query(
      'sound_detections',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'timestamp DESC',
    );
  }

  Future<int> deleteUserDetection(int detectionId) async {
    final db = await database;
    return await db.delete(
      'sound_detections',
      where: 'id = ?',
      whereArgs: [detectionId],
    );
  }

  Future<void> clearUserDetections(int userId) async {
    final db = await database;
    await db.delete(
      'sound_detections',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }
}
