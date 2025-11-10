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
}