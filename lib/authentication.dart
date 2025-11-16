import 'dart:math';

import 'database_helper.dart';

class AuthService {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  
  static int? _currentUserId;
  static String? _currentUsername;
  
  static int? get currentUserId => _currentUserId;
  static String? get currentUsername => _currentUsername;
  static bool get isLoggedIn => _currentUserId != null;
  
  Future<bool> register(String username, String email, String password) async {
    try {
      await _dbHelper.registerUser(username, email, password);
      return true;
    } catch (e) {
      throw Exception(e.toString());
    }
  }
  
  Future<bool> login(String username, String password) async {
    final user = await _dbHelper.loginUser(username, password);
    
    if (user != null) {
      _currentUserId = user['id'] as int;
      _currentUsername = user['username'] as String;
      return true;
    }
    
    return false;
  }
  
  void logout() {
    _currentUserId = null;
    _currentUsername = null;
  }

  Future<String> requestPasswordReset(String email) async {
    final token = _generateRandomToken();
    await _dbHelper.setPasswordResetToken(email, token);
    // In a real app, you would send an email with a link like:
    // https://your-app.com/reset-password?token=$token
    final resetLink = 'https://your-app.com/reset-password?token=$token';
    print('Password reset link: $resetLink'); // Simulate sending email
    return resetLink;
  }

  Future<bool> resetPassword(String token, String newPassword) async {
    final user = await _dbHelper.getUserByResetToken(token);
    if (user != null) {
      final email = user['email'] as String;
      final result = await _dbHelper.updateUserPassword(email, newPassword);
      return result > 0;
    }
    return false;
  }

  String _generateRandomToken() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return values.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  }
}