import 'package:flutter/material.dart';
import 'authentication.dart';
import 'database_helper.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  _LogsScreenState createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _detections = [];

  @override
  void initState() {
    super.initState();
    _loadDetections();
  }

  Future<void> _loadDetections() async {
    if (AuthService.isLoggedIn) {
      final detections =
          await _dbHelper.getUserDetections(AuthService.currentUserId!);
      setState(() => _detections = detections.reversed.toList()); // Newest first
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detection Logs')),
      body: _detections.isEmpty
          ? const Center(
              child: Text(
                'No detections yet\nStart detecting sounds!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            )
          : ListView.builder(
              itemCount: _detections.length,
              itemBuilder: (context, index) {
                final detection = _detections[index];
                final timestamp = DateTime.parse(detection['timestamp']);
                final soundClass = detection['sound_class'];

                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  color: const Color(0xFF001220),
                  child: ListTile(
                    leading: Icon(Icons.hearing,
                        color: _getColorForSound(soundClass)),
                    title: Text(
                      soundClass,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: soundClass == 'Noise'
                            ? FontWeight.normal
                            : FontWeight.bold,
                        fontStyle: soundClass == 'Noise'
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                    subtitle: Text(
                      '${_formatDate(timestamp)} at ${_formatTime(timestamp)}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    trailing: Text(
                      '${detection['confidence']}%',
                      style: TextStyle(
                        color: soundClass == 'Noise'
                            ? Colors.grey
                            : Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Color _getColorForSound(String soundClass) {
    switch (soundClass) {
      case 'SpeedBoat':
        return Colors.blue;
      case 'UUV':
        return Colors.green;
      case 'KaiYuan':
        return Colors.orange;
      case 'Noise':
        return Colors.grey;
      default:
        return Colors.purple;
    }
  }

  String _formatTime(DateTime timestamp) {
    return '${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime timestamp) {
    return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
  }
}
