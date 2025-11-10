import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:async';
import 'login.dart';
import 'manage.dart';
import 'logs.dart';
import 'authentication.dart';
import 'sound_detection.dart';
import 'snr.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const SoundDetectApp();
  }
}

class SoundDetectApp extends StatelessWidget {
  const SoundDetectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sound Detector',
      theme: ThemeData(
        fontFamily: 'Sans',
        scaffoldBackgroundColor: const Color(0xFF001220),
        primaryColor: const Color(0xFF8C6EF2),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white70),
          titleLarge:
              TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      debugShowCheckedModeBanner: false,
      home: FutureBuilder<bool>(
        future: _checkAuthStatus(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SplashScreen();
          }
          return snapshot.data == true
              ? const MainScreen()
              : const LoginScreen();
        },
      ),
    );
  }

  Future<bool> _checkAuthStatus() async {
    await Future.delayed(const Duration(milliseconds: 500));
    return AuthService.isLoggedIn;
  }
}

Widget gradientButton({
  required String text,
  required VoidCallback onPressed,
  EdgeInsetsGeometry padding =
      const EdgeInsets.symmetric(horizontal: 60, vertical: 16),
  double borderRadius = 12,
  double fontSize = 16,
  bool isCircle = false,
}) {
  return InkWell(
    onTap: onPressed,
    borderRadius: BorderRadius.circular(borderRadius),
    child: Ink(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFDE0E6F), Color.fromARGB(255, 216, 221, 224)],
        ),
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : BorderRadius.circular(borderRadius),
      ),
      child: Container(
        padding: padding,
        alignment: Alignment.center,
        child: Text(
          text,
          style: TextStyle(color: Colors.white, fontSize: fontSize),
        ),
      ),
    ),
  );
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _navigateBasedOnAuth();
  }

  void _navigateBasedOnAuth() async {
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;

    if (AuthService.isLoggedIn) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF001220),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _animation,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF8C6EF2).withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                  ),
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFF8C6EF2), Color(0xFFDE0E6F)],
                    ).createShader(bounds),
                    child: const Icon(
                      Icons.anchor,
                      size: 60,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: 200,
              height: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  backgroundColor: Colors.white.withOpacity(0.2),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    const Color(0xFF8C6EF2).withOpacity(0.8),
                  ),
                  minHeight: 4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _waveController;
  bool _isDetecting = false;
  bool _isProcessing = false;
  final List<double> _baseWaveHeights = [10, 20, 30, 40, 30, 20, 10];
  late List<double> _currentWaveHeights;

  final SoundDetectionService _detectionService = SoundDetectionService();
  String? _lastDetection;
  double? _lastConfidence;
  Map<dynamic, dynamic>? _allPredictions;
  Map<String, dynamic>? _lastSNRMetrics; // SNR metrics instead of FFT

  @override
  void initState() {
    super.initState();
    _currentWaveHeights = List.from(_baseWaveHeights);
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
      lowerBound: 0.9,
      upperBound: 1.1,
    )..addStatusListener((status) {
        if (_isDetecting && status == AnimationStatus.completed) {
          _scaleController.reverse();
        } else if (_isDetecting && status == AnimationStatus.dismissed) {
          _scaleController.forward();
        }
      });

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..addListener(() {
        if (_isDetecting) {
          setState(() {
            _currentWaveHeights = _baseWaveHeights.map((h) {
              final progress = _waveController.value;
              final offset = math.sin(progress * 2 * math.pi) * 15;
              return (h + offset).clamp(10.0, 50.0);
            }).toList();
          });
        }
      });
  }

  Future<void> _toggleDetect() async {
    if (_isDetecting || _isProcessing) return;

    setState(() {
      _isDetecting = true;
      _isProcessing = true;
      _lastSNRMetrics = null;
    });

    _scaleController.forward();
    _waveController.repeat();

    final result = await _detectionService.detectSound();

    setState(() {
      _isDetecting = false;
      _isProcessing = false;

      if (result['success'] == true) {
        _lastDetection = result['predicted_class'];
        _lastConfidence = result['confidence'];
        _allPredictions = result['all_predictions'];
        _lastSNRMetrics = result['snr_metrics'];

        String message =
            'Detected: $_lastDetection (${_lastConfidence?.toStringAsFixed(1)}%)';

        if (_lastSNRMetrics != null) {
          double snrDb = (_lastSNRMetrics!['snr_db'] ?? 0.0).toDouble();
          String quality = _lastSNRMetrics!['quality'] ?? 'Unknown';
          message += '\nSNR: ${snrDb.toStringAsFixed(1)} dB ($quality)';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        _showSNRAnalysisDialog();
                      },
                      child: const Text('VIEW SIGNAL ANALYSIS',
                          style: TextStyle(color: Colors.blue)),
                    ),
                  ],
                ),
              ],
            ),
            backgroundColor: _getSnackbarColor(_lastDetection!),
            duration: const Duration(seconds: 6),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Detection failed: ${result['error']}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    });

    _scaleController.reset();
    _waveController.reset();
    _currentWaveHeights = List.from(_baseWaveHeights);
  }

  void _showSNRAnalysisDialog() {
    if (_lastDetection == null || _lastConfidence == null) return;

    SNRAnalysisDisplay(
      soundClass: _lastDetection!,
      confidence: _lastConfidence!,
      allPredictions: _allPredictions,
      snrMetrics: _lastSNRMetrics,
    ).show(context);
  }

  Color _getSnackbarColor(String soundClass) {
    switch (soundClass.toLowerCase()) {
      case 'speedboat':
        return const Color(0xFF4CAF50);
      case 'uuv':
        return const Color(0xFF2196F3);
      case 'kaiyuan':
        return const Color(0xFFFF9800);
      default:
        return const Color(0xFF9E9E9E);
    }
  }

  Color _getClassColor(String className) {
    switch (className.toLowerCase()) {
      case 'speedboat':
        return const Color(0xFF4CAF50);
      case 'uuv':
        return const Color(0xFF2196F3);
      case 'kaiyuan':
        return const Color(0xFFFF9800);
      default:
        return const Color(0xFF9E9E9E);
    }
  }

  Color _getSNRColor(double snrDb) {
    if (snrDb >= 25.0) return Colors.green;
    if (snrDb >= 20.0) return Colors.lightGreen;
    if (snrDb >= 15.0) return Colors.orange;
    if (snrDb >= 10.0) return Colors.red;
    return Colors.deepOrange;
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _waveController.dispose();
    _detectionService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Sound Detector'),
        actions: [
          // SNR analysis indicator
          if (_lastSNRMetrics != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                children: [
                  Icon(Icons.auto_graph,
                      color: _getSNRColor(
                          (_lastSNRMetrics!['snr_db'] ?? 0.0).toDouble()),
                      size: 18),
                  const SizedBox(width: 4),
                  Text(
                    'SIGNAL ANALYSIS',
                    style: TextStyle(
                      color: _getSNRColor(
                          (_lastSNRMetrics!['snr_db'] ?? 0.0).toDouble()),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          if (_lastDetection != null)
            IconButton(
              icon: const Icon(Icons.auto_graph, color: Colors.white),
              onPressed: _showSNRAnalysisDialog,
              tooltip: 'Show Signal Analysis',
            ),
        ],
      ),
      body: Stack(
        children: [
          SizedBox.expand(
            child: Image.asset(
              'assets/images/main_waves.png',
              fit: BoxFit.cover,
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_lastDetection != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: GestureDetector(
                      onTap: _showSNRAnalysisDialog,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: _getClassColor(_lastDetection!)
                                  .withOpacity(0.5)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getClassIcon(_lastDetection!),
                                  color: Colors.white.withOpacity(0.8),
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '$_lastDetection (${_lastConfidence?.toStringAsFixed(1)}%)',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 16),
                                ),
                              ],
                            ),
                            if (_lastSNRMetrics != null) ...[
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.auto_graph,
                                      color: _getSNRColor(
                                          (_lastSNRMetrics!['snr_db'] ?? 0.0)
                                              .toDouble()),
                                      size: 12),
                                  const SizedBox(width: 4),
                                  Text(
                                    'SNR: ${(_lastSNRMetrics!['snr_db'] ?? 0.0).toStringAsFixed(1)} dB',
                                    style: TextStyle(
                                      color: _getSNRColor(
                                          (_lastSNRMetrics!['snr_db'] ?? 0.0)
                                              .toDouble()),
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(Icons.high_quality,
                                      color: _getSNRColor(
                                          (_lastSNRMetrics!['snr_db'] ?? 0.0)
                                              .toDouble()),
                                      size: 12),
                                  const SizedBox(width: 4),
                                  Text(
                                    _lastSNRMetrics!['quality'] ?? 'Unknown',
                                    style: TextStyle(
                                      color: _getSNRColor(
                                          (_lastSNRMetrics!['snr_db'] ?? 0.0)
                                              .toDouble()),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_isDetecting)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 30),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: _currentWaveHeights.map((height) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 8,
                            height: height,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ScaleTransition(
                  scale: _scaleController,
                  child: GestureDetector(
                    onTap: _isProcessing ? null : _toggleDetect,
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color.fromARGB(255, 169, 76, 91),
                            Color.fromARGB(255, 184, 179, 179)
                          ],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: _isDetecting
                            ? [
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.3),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                )
                              ]
                            : null,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_isProcessing)
                              const SizedBox(
                                height: 40,
                                width: 40,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            else
                              Icon(
                                _isDetecting ? Icons.mic : Icons.mic_none,
                                color: Colors.white,
                                size: 48,
                              ),
                            const SizedBox(height: 10),
                            Text(
                              _isProcessing
                                  ? "Processing..."
                                  : _isDetecting
                                      ? "Listening..."
                                      : "Tap to Detect",
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold),
                            ),
                            if (_lastSNRMetrics != null)
                              const SizedBox(height: 8),
                            if (_lastSNRMetrics != null)
                              Text(
                                'Signal Analysis Available',
                                style: TextStyle(
                                  color: _getSNRColor(
                                          (_lastSNRMetrics!['snr_db'] ?? 0.0)
                                              .toDouble())
                                      .withOpacity(0.8),
                                  fontSize: 10,
                                ),
                                textAlign: TextAlign.center,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (_isDetecting)
                  Padding(
                    padding: const EdgeInsets.only(top: 30),
                    child: Column(
                      children: [
                        Text(
                          "Recording audio...",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "Make noise near your microphone",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getClassIcon(String className) {
    switch (className.toLowerCase()) {
      case 'speedboat':
        return Icons.directions_boat;
      case 'uuv':
        return Icons.sensors;
      case 'kaiyuan':
        return Icons.directions_boat_outlined;
      default:
        return Icons.help_outline;
    }
  }
}

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF001220).withOpacity(0.9),
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          DrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFDA70D6), Color(0xFF8C6EF2)],
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Sound Detector',
                  style: TextStyle(color: Colors.white, fontSize: 24),
                ),
                const SizedBox(height: 8),
                Text(
                  AuthService.isLoggedIn
                      ? 'Welcome, ${AuthService.currentUsername}!'
                      : 'Welcome!',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
          ListTile(
            leading: Icon(Icons.history, color: Colors.white.withOpacity(0.7)),
            title: const Text('Logs', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.push(
                  context, MaterialPageRoute(builder: (_) => LogsScreen()));
            },
          ),
          ListTile(
            leading: Icon(Icons.settings, color: Colors.white.withOpacity(0.7)),
            title: const Text('Manage Account',
                style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ManageAccountScreen()));
            },
          ),
          ListTile(
            leading: Icon(Icons.logout, color: Colors.white.withOpacity(0.7)),
            title: const Text('Logout', style: TextStyle(color: Colors.white)),
            onTap: () {
              _showLogoutConfirmation(context);
            },
          ),
        ],
      ),
    );
  }

  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF001220),
        title: const Text('Logout', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to logout?',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              AuthService().logout();
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
