import 'package:flutter/material.dart';
import 'dart:math' as math;

class MelSpectrogramDisplay extends StatelessWidget {
  final String soundClass;
  final double confidence;
  final Map<dynamic, dynamic>? allPredictions;
  final List<double>? audioSamples;
  final List<dynamic>? noiseSegments; // NEW: Noise segments from API
  final String? spectrogramPlotUrl; // NEW: Spectrogram plot URL

  const MelSpectrogramDisplay({
    required this.soundClass,
    required this.confidence,
    required this.allPredictions,
    required this.audioSamples,
    this.noiseSegments,
    this.spectrogramPlotUrl,
    super.key,
  });

  void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF001220),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => this,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Advanced Sound Analysis',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Detection Info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    Text(
                      'Detected',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      soundClass,
                      style: TextStyle(
                        color: _getClassColor(soundClass),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Column(
                  children: [
                    Text(
                      'Confidence',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '${confidence.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: _getConfidenceColor(confidence),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Noise Segments Information
          if (noiseSegments != null && noiseSegments!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.5)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.warning, color: Colors.orange, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Noise Detected in ${noiseSegments!.length} Segment(s)',
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatNoiseSegments(noiseSegments!),
                    style: TextStyle(
                      color: Colors.orange.withOpacity(0.8),
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Waveform Title
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.graphic_eq, color: Colors.white.withOpacity(0.8), size: 20),
              const SizedBox(width: 8),
              Text(
                'Audio Waveform - $soundClass',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // REAL AUDIO WAVEFORM WITH NOISE ANNOTATIONS
          Container(
            width: double.infinity,
            height: 200,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: _buildEnhancedWaveform(),
          ),

          const SizedBox(height: 16),

          // Sound Characteristics
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                const Text(
                  'Analysis Details',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _getEnhancedDescription(soundClass, noiseSegments),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          // All Predictions
          if (allPredictions != null && allPredictions!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  const Text(
                    'Frame-by-Frame Predictions',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildPredictionItem('SpeedBoat', allPredictions!['SpeedBoat'] ?? 0),
                      _buildPredictionItem('UUV', allPredictions!['UUV'] ?? 0),
                      _buildPredictionItem('KaiYuan', allPredictions!['KaiYuan'] ?? 0),
                    ],
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Close Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8C6EF2),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Close Analysis',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ENHANCED WAVEFORM WITH NOISE ANNOTATIONS
  Widget _buildEnhancedWaveform() {
    if (audioSamples == null || audioSamples!.isEmpty) {
      return _buildNoDataPlaceholder();
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: _getClassColor(soundClass).withOpacity(0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                children: [
                  // Background grid
                  _buildDetailedGrid(),
                  // Waveform
                  Container(
                    width: double.infinity,
                    height: double.infinity,
                    child: CustomPaint(
                      painter: _EnhancedWaveformPainter(
                        samples: audioSamples!,
                        color: _getClassColor(soundClass),
                        noiseSegments: noiseSegments,
                        totalDuration: 3.0, // 3-second recording
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (noiseSegments != null && noiseSegments!.isNotEmpty)
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              if (noiseSegments != null && noiseSegments!.isNotEmpty)
                const SizedBox(width: 4),
              if (noiseSegments != null && noiseSegments!.isNotEmpty)
                Text(
                  'Noise Segments',
                  style: TextStyle(
                    color: Colors.orange.withOpacity(0.8),
                    fontSize: 10,
                  ),
                ),
              if (noiseSegments != null && noiseSegments!.isNotEmpty)
                const SizedBox(width: 12),
              Text(
                'Real Audio (${audioSamples!.length} samples)',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatNoiseSegments(List<dynamic> segments) {
    if (segments.isEmpty) return '';
    
    List<String> formatted = [];
    for (var segment in segments) {
      if (segment is Map && segment.containsKey('start') && segment.containsKey('end')) {
        formatted.add('${segment['start']}s-${segment['end']}s');
      } else if (segment is List && segment.length == 2) {
        formatted.add('${segment[0]}s-${segment[1]}s');
      }
    }
    return formatted.join(', ');
  }

  String _getEnhancedDescription(String soundClass, List<dynamic>? noiseSegments) {
    String baseDescription = _getWaveformDescription(soundClass);
    
    if (noiseSegments != null && noiseSegments.isNotEmpty) {
      baseDescription += '\n\n⚠️ ${noiseSegments.length} noise segment(s) detected. '
                       'This may affect detection accuracy.';
    } else {
      baseDescription += '\n\n✅ Clean audio with minimal noise interference.';
    }
    
    return baseDescription;
  }

  // ... keep existing helper methods (_buildNoDataPlaceholder, _buildDetailedGrid, etc.)
  Widget _buildNoDataPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.audio_file,
            color: _getClassColor(soundClass).withOpacity(0.5),
            size: 50,
          ),
          const SizedBox(height: 8),
          Text(
            'No audio data available',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedGrid() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      child: Column(
        children: [
          Expanded(
            child: Container(
              child: Column(
                children: List.generate(5, (index) => Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: index == 2 
                            ? Colors.white.withOpacity(0.3) 
                            : Colors.white.withOpacity(0.1),
                          width: index == 2 ? 1.0 : 0.5,
                        ),
                      ),
                    ),
                  ),
                )),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPredictionItem(String className, dynamic confidence) {
    final conf = confidence is double ? confidence : double.tryParse(confidence.toString()) ?? 0.0;
    return Column(
      children: [
        Text(
          className,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${conf.toStringAsFixed(1)}%',
          style: TextStyle(
            color: _getClassColor(className),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Color _getClassColor(String className) {
    switch (className.toLowerCase()) {
      case 'speedboat': return const Color(0xFF4CAF50);
      case 'uuv': return const Color(0xFF2196F3);
      case 'kaiyuan': return const Color(0xFFFF9800);
      default: return const Color(0xFF9E9E9E);
    }
  }

  Color _getConfidenceColor(double confidence) {
    if (confidence >= 80) return const Color(0xFF4CAF50);
    if (confidence >= 65) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }

  String _getWaveformDescription(String soundClass) {
    switch (soundClass.toLowerCase()) {
      case 'speedboat':
        return 'Regular high-frequency oscillations with engine harmonics. Clear periodic pattern with consistent amplitude.';
      case 'uuv':
        return 'Complex modulated waveform with varying frequency. Electronic motor signature with noise components.';
      case 'kaiyuan':
        return 'High-amplitude low-frequency dominant waveform. Powerful engine rumble with broad noise spectrum.';
      default:
        return 'Irregular noise pattern with no clear periodicity. Random amplitude variations characteristic of background noise.';
    }
  }
}

class _EnhancedWaveformPainter extends CustomPainter {
  final List<double> samples;
  final Color color;
  final List<dynamic>? noiseSegments;
  final double totalDuration;

  _EnhancedWaveformPainter({
    required this.samples,
    required this.color,
    this.noiseSegments,
    required this.totalDuration,
  });

  @override
  void paint(Canvas canvas, Size size) {
    try {
      if (samples.isEmpty) return;

      // Draw noise segments background first
      _drawNoiseSegments(canvas, size);
      
      // Draw the main waveform
      _drawWaveform(canvas, size);
      
      // Draw timeline markers
      _drawTimeline(canvas, size);

    } catch (e) {
      print("Waveform painting error: $e");
    }
  }

  void _drawNoiseSegments(Canvas canvas, Size size) {
    if (noiseSegments == null || noiseSegments!.isEmpty) return;

    final noisePaint = Paint()
      ..color = Colors.orange.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    for (var segment in noiseSegments!) {
      double startTime = 0.0;
      double endTime = 0.0;
      
      if (segment is Map && segment.containsKey('start') && segment.containsKey('end')) {
        startTime = (segment['start'] as num).toDouble();
        endTime = (segment['end'] as num).toDouble();
      } else if (segment is List && segment.length == 2) {
        startTime = (segment[0] as num).toDouble();
        endTime = (segment[1] as num).toDouble();
      }
      
      if (startTime >= 0 && endTime <= totalDuration && startTime < endTime) {
        double startX = (startTime / totalDuration) * size.width;
        double endX = (endTime / totalDuration) * size.width;
        double width = endX - startX;
        
        // Only draw if segment is wide enough to be visible
        if (width >= 2.0) {
          canvas.drawRect(
            Rect.fromLTRB(startX, 0, endX, size.height),
            noisePaint,
          );
          
          // Draw noise segment border
          final borderPaint = Paint()
            ..color = Colors.orange.withOpacity(0.5)
            ..strokeWidth = 1.0
            ..style = PaintingStyle.stroke;
            
          canvas.drawRect(
            Rect.fromLTRB(startX, 0, endX, size.height),
            borderPaint,
          );
        }
      }
    }
  }

  void _drawWaveform(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = color.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    final centerY = size.height / 2;
    final List<Offset> upperPoints = [];
    final List<Offset> lowerPoints = [];

    // Calculate appropriate step size for smooth rendering
    int step = (samples.length / size.width).ceil().clamp(1, 8);
    
    for (int i = 0; i < samples.length; i += step) {
      double x = (i / samples.length) * size.width;
      double amplitude = samples[i] * size.height / 2;
      double upperY = centerY - amplitude;
      double lowerY = centerY + amplitude;
      
      if (x.isFinite && upperY.isFinite && lowerY.isFinite) {
        upperPoints.add(Offset(x, upperY));
        lowerPoints.add(Offset(x, lowerY));
      }
    }

    // Create a path for filled waveform
    if (upperPoints.isNotEmpty && lowerPoints.isNotEmpty) {
      final path = Path();
      
      // Draw upper half
      path.moveTo(upperPoints.first.dx, upperPoints.first.dy);
      for (int i = 1; i < upperPoints.length; i++) {
        path.lineTo(upperPoints[i].dx, upperPoints[i].dy);
      }
      
      // Draw lower half in reverse
      for (int i = lowerPoints.length - 1; i >= 0; i--) {
        path.lineTo(lowerPoints[i].dx, lowerPoints[i].dy);
      }
      
      path.close();
      
      // Fill the waveform
      canvas.drawPath(path, fillPaint);
      
      // Draw the outline
      for (int i = 0; i < upperPoints.length - 1; i++) {
        if (_isValidOffset(upperPoints[i]) && _isValidOffset(upperPoints[i + 1])) {
          canvas.drawLine(upperPoints[i], upperPoints[i + 1], paint);
        }
      }
    }
  }

  void _drawTimeline(Canvas canvas, Size size) {
    final timelinePaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..strokeWidth = 0.5;

    // Draw center line
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      timelinePaint,
    );

    // Draw time markers (every second)
    for (int i = 1; i < totalDuration.toInt(); i++) {
      double x = (i / totalDuration) * size.width;
      canvas.drawLine(
        Offset(x, size.height / 2 - 5),
        Offset(x, size.height / 2 + 5),
        timelinePaint,
      );
    }
  }

  bool _isValidOffset(Offset offset) {
    return offset.dx.isFinite && offset.dy.isFinite;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}