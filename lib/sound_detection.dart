import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sound_app/permission.dart';
import 'authentication.dart';
import 'database_helper.dart';

class SoundDetectionService {
  static const String apiUrl =
      'https://shahbazfareedchishti-sound-detection.hf.space/stream';

  final AudioRecorder _audioRecorder = AudioRecorder();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<Map<String, dynamic>> detectSound() async {
    try {
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/detection_${DateTime.now().millisecondsSinceEpoch}.wav';

      if (await requestMicPermission()) {
        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
          path: filePath,
        );
      } else {
        throw Exception("Microphone permission not granted");
      }

      await Future.delayed(const Duration(seconds: 3));
      await _audioRecorder.stop();
      final audioFile = File(filePath);

      var apiResult = await _sendToAPI(audioFile);

      // Clean up the temporary file
      try {
        if (await audioFile.exists()) {
          await audioFile.delete();
        }
      } catch (e) {
        print("⚠️ Could not delete temp file: $e");
      }

      // **IMPROVED: Comprehensive API response validation**
      if (apiResult['success'] != true) {
        print("❌ API returned failure: ${apiResult['error']}");
        return _createErrorResponse(apiResult['error'] ?? 'API request failed');
      }

      // **IMPROVED: Validate and parse SNR analysis with better error handling**
      Map<String, dynamic> snrMetrics = _parseSnrAnalysis(apiResult);
      
      // **IMPROVED: Validate main prediction fields**
      final predictedClass = apiResult['predicted_class']?.toString() ?? 'Unknown';
      final confidence = _parseConfidence(apiResult['confidence']);

      // **NEW: Parse additional fields that should be in the API response**
      final allPredictions = _parseAllPredictions(apiResult['all_predictions']);
      final noiseSegments = _parseNoiseSegments(apiResult['noise_segments']);
      final spectrogramPlot = apiResult['spectrogram_plot']?.toString();

      // Save detection event to the database.
      if (predictedClass != 'Unknown' && AuthService.isLoggedIn) {
        await _dbHelper.insertDetection(
          AuthService.currentUserId!,
          predictedClass,
          confidence,
        );
      }

      return {
        'success': true,
        'predicted_class': predictedClass,
        'confidence': confidence,
        'snr_metrics': snrMetrics,
        'all_predictions': allPredictions,
        'noise_segments': noiseSegments,
        'spectrogram_plot': spectrogramPlot,
        'raw_api_response': apiResult, // Keep original for debugging
      };
    } catch (e) {
      print("❌ Top-level error in sound detection: $e");
      return _createErrorResponse(e.toString());
    }
  }

  Map<String, dynamic> _parseSnrAnalysis(Map<String, dynamic> apiResult) {
    try {
      if (!apiResult.containsKey('snr_analysis') || apiResult['snr_analysis'] is! Map) {
        print("❌ 'snr_analysis' block missing from API response");
        return _createFallbackSnrMetrics();
      }

      final apiAnalysis = apiResult['snr_analysis'] as Map<String, dynamic>;
      
      // **IMPROVED: Safe parsing with type checking**
      final snrValues = _safeCastList<double>(apiAnalysis['snr_values_over_time']);
      final timeBins = _safeCastList<double>(apiAnalysis['time_bins']);
      final frequencyBins = _safeCastList<double>(apiAnalysis['frequency_bins']);
      final powerSpectrum = _safeCastList<double>(apiAnalysis['power_spectrum']);
      
      final snrDb = _parseDouble(apiAnalysis['snr_db']);
      final quality = apiAnalysis['quality']?.toString() ?? 'Unknown';
      final signalPercentage = _parseDouble(apiAnalysis['signal_percentage']);
      final noisePercentage = _parseDouble(apiAnalysis['noise_percentage']);
      final totalDuration = _parseDouble(apiAnalysis['total_duration']);
      
      // **NEW: Parse spectral features**
      final spectralFeatures = _parseSpectralFeatures(apiAnalysis['spectral_features']);

      print("✅ Successfully parsed 'snr_analysis' from API: ${snrDb.toStringAsFixed(1)} dB, $quality");

      return {
        'snr_over_time': snrValues,
        'time_bins': timeBins,
        'frequency_bins': frequencyBins,
        'power_spectrum': powerSpectrum,
        'snr_db': snrDb,
        'quality': quality,
        'signal_percentage': signalPercentage,
        'noise_percentage': noisePercentage,
        'total_duration': totalDuration,
        'spectral_features': spectralFeatures,
      };
    } catch (e) {
      print("❌ Error parsing SNR analysis: $e");
      return _createFallbackSnrMetrics();
    }
  }

  Map<String, dynamic> _parseSpectralFeatures(dynamic features) {
    if (features is! Map<String, dynamic>) {
      return {};
    }
    
    return {
      'spectral_centroid': _parseDouble(features['spectral_centroid']),
      'spectral_rolloff': _parseDouble(features['spectral_rolloff']),
      'zero_crossing_rate': _parseDouble(features['zero_crossing_rate']),
      'rms_energy': _parseDouble(features['rms_energy']),
    };
  }

  List<double> _safeCastList<T>(dynamic list) {
    if (list is List) {
      try {
        return list.map((e) => (e as num).toDouble()).toList();
      } catch (e) {
        print("⚠️ List casting error: $e");
      }
    }
    return <double>[];
  }

  double _parseDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  double _parseConfidence(dynamic confidence) {
    final conf = _parseDouble(confidence);
    // Confidence should be between 0-100, normalize if needed
    if (conf > 1.0 && conf <= 100.0) {
      return conf;
    } else if (conf <= 1.0) {
      return conf * 100.0; // Convert from decimal to percentage
    }
    return 0.0;
  }

  Map<String, double> _parseAllPredictions(dynamic predictions) {
    if (predictions is Map<String, dynamic>) {
      final result = <String, double>{};
      predictions.forEach((key, value) {
        result[key] = _parseDouble(value);
      });
      return result;
    }
    return {};
  }

  List<List<double>> _parseNoiseSegments(dynamic segments) {
    if (segments is List) {
      return segments.whereType<List>().map((segment) {
        return segment.whereType<num>().map((e) => e.toDouble()).toList();
      }).toList();
    }
    return [];
  }

  Map<String, dynamic> _createErrorResponse(String error) {
    return {
      'success': false,
      'error': error,
      'predicted_class': 'Unknown',
      'confidence': 0.0,
      'snr_metrics': _createFallbackSnrMetrics(),
      'all_predictions': {},
      'noise_segments': [],
    };
  }

  Map<String, dynamic> _createFallbackSnrMetrics() {
    return {
      'snr_over_time': <double>[],
      'time_bins': <double>[],
      'frequency_bins': <double>[],
      'power_spectrum': <double>[],
      'snr_db': 0.0,
      'quality': 'Error',
      'signal_percentage': 0.0,
      'noise_percentage': 0.0,
      'total_duration': 0.0,
      'spectral_features': {},
    };
  }

  Future<Map<String, dynamic>> _sendToAPI(File audioFile) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse(apiUrl))
        ..files.add(await http.MultipartFile.fromPath('chunk', audioFile.path));

      var response = await request.send();
      
      if (response.statusCode != 200) {
        return {
          'success': false,
          'error': 'HTTP ${response.statusCode}: ${response.reasonPhrase}'
        };
      }

      var responseData = await response.stream.bytesToString();
      final decodedResponse = json.decode(responseData);

      if (decodedResponse is Map<String, dynamic>) {
        return decodedResponse;
      } else {
        return {
          'success': false,
          'error': 'Invalid JSON format from API',
        };
      }
    } catch (e) {
      print("❌ API connection error: $e");
      return {
        'success': false,
        'error': 'API connection failed: $e',
      };
    }
  }

  void dispose() {
    _audioRecorder.dispose();
  }
}