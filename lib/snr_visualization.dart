// snr_visualization.dart - CLEANED VERSION
import 'package:flutter/material.dart';
import 'dart:math' as math;

class _SNRFrequencyPlotPainter extends CustomPainter {
  final List<double> signalData;
  final List<double> noiseData;
  final double snrDb;

  _SNRFrequencyPlotPainter({
    required this.signalData,
    required this.noiseData,
    required this.snrDb,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final snrLinePaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final axisPaint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final pointPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;

    // Use real SNR data to create frequency distribution
    List<double> snrValues = _calculateSNRValues();
    
    if (snrValues.isEmpty) return;

    _drawAxes(canvas, size, axisPaint);
    _drawGrid(canvas, size, gridPaint);
    _drawSNRPlot(canvas, size, snrValues, snrLinePaint, pointPaint);
    _drawLabels(canvas, size, snrValues);
  }

  List<double> _calculateSNRValues() {
    List<double> snrValues = [];
    
    // ✅ USE REAL SPECTRUM DATA to calculate SNR per frequency bin
    if (signalData.isEmpty || noiseData.isEmpty) {
      print("⚠️ No spectrum data available for SNR calculation");
      return [];
    }
    
    // Ensure both spectra have the same length
    int minLength = math.min(signalData.length, noiseData.length);
    
    for (int i = 0; i < minLength; i++) {
      double signalPower = signalData[i];
      double noisePower = noiseData[i];
      
      // Calculate SNR for this frequency bin
      // SNR = 10 * log10(signal_power / noise_power)
      // Use a minimum noise floor to avoid infinite SNR
      double minNoiseFloor = 1e-8; // Minimum noise floor to prevent division issues
      double effectiveNoise = math.max(noisePower, minNoiseFloor);
      
      if (signalPower > 1e-10 || noisePower > 1e-10) {
        double ratio = signalPower / effectiveNoise;
        double freqSNR = 10 * math.log(ratio) / math.ln10; // Convert to dB
        
        // Clamp to reasonable range (0-80 dB) but don't hardcode to 60
        freqSNR = freqSNR.clamp(0.0, 80.0);
        snrValues.add(freqSNR);
      } else {
        // Both are zero or very small - set to 0 dB (no signal, no noise)
        snrValues.add(0.0);
      }
    }
    
    print("✅ Calculated ${snrValues.length} real SNR values from spectrum data");
    if (snrValues.isNotEmpty) {
      double minSNR = snrValues.reduce((a, b) => a < b ? a : b);
      double maxSNR = snrValues.reduce((a, b) => a > b ? a : b);
      double avgSNR = snrValues.reduce((a, b) => a + b) / snrValues.length;
      print("   SNR range: ${minSNR.toStringAsFixed(1)} - ${maxSNR.toStringAsFixed(1)} dB, avg: ${avgSNR.toStringAsFixed(1)} dB");
    }
    
    return snrValues;
  }

  void _drawAxes(Canvas canvas, Size size, Paint paint) {
    canvas.drawLine(Offset(50, 30), Offset(50, size.height - 40), paint);
    canvas.drawLine(Offset(50, size.height - 40), Offset(size.width - 20, size.height - 40), paint);
    
    canvas.drawLine(Offset(50, 30), Offset(47, 35), paint);
    canvas.drawLine(Offset(50, 30), Offset(53, 35), paint);
    
    canvas.drawLine(Offset(size.width - 20, size.height - 40), Offset(size.width - 25, size.height - 37), paint);
    canvas.drawLine(Offset(size.width - 20, size.height - 40), Offset(size.width - 25, size.height - 43), paint);
  }

  void _drawGrid(Canvas canvas, Size size, Paint paint) {
    for (int i = 1; i <= 8; i++) {
      double x = 50 + (i / 8) * (size.width - 70);
      canvas.drawLine(Offset(x, 30), Offset(x, size.height - 40), paint);
    }
    
    for (int i = 1; i <= 5; i++) {
      double y = 30 + (i / 5) * (size.height - 70);
      canvas.drawLine(Offset(50, y), Offset(size.width - 20, y), paint);
    }
  }

  void _drawSNRPlot(Canvas canvas, Size size, List<double> snrValues, Paint linePaint, Paint pointPaint) {
    if (snrValues.isEmpty) return;
    
    final path = Path();
    
    // Find min/max SNR for proper scaling
    double minSNR = snrValues.reduce((a, b) => a < b ? a : b);
    double maxSNR = snrValues.reduce((a, b) => a > b ? a : b);
    double snrRange = maxSNR - minSNR;
    
    // ✅ FIXED: Don't force range to 60, use actual data range
    double snrMin, snrMax;
    
    // If range is too small, add reasonable padding
    if (snrRange < 5.0) {
      // Add padding to make visualization clearer
      double padding = math.max(5.0, (maxSNR + minSNR) / 2 * 0.2); // 20% padding
      snrMin = math.max(0.0, minSNR - padding);
      snrMax = maxSNR + padding;
    } else {
      // Use actual range with small padding
      snrMin = math.max(0.0, minSNR - 2.0);
      snrMax = maxSNR + 2.0;
    }
    
    double adjustedRange = snrMax - snrMin;
    
    print("📊 Graph Scaling: min=${snrMin.toStringAsFixed(1)} dB, max=${snrMax.toStringAsFixed(1)} dB, range=${adjustedRange.toStringAsFixed(1)} dB");
    print("   First SNR value: ${snrValues[0].toStringAsFixed(1)} dB, Last: ${snrValues[snrValues.length - 1].toStringAsFixed(1)} dB");
    
    for (int i = 0; i < snrValues.length; i++) {
      double x = 50 + (i / math.max(1, snrValues.length - 1)) * (size.width - 70);
      double snr = snrValues[i];
      
      // Scale SNR to Y position (inverted: higher SNR = higher on screen)
      double normalizedSNR = adjustedRange > 0 ? (snr - snrMin) / adjustedRange : 0.5;
      double y = 30 + (1.0 - normalizedSNR) * (size.height - 70);
      
      // Clamp Y to valid range
      y = y.clamp(30.0, size.height - 40.0);
      
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      
      // Only draw points for every Nth value to avoid clutter
      if (i % math.max(1, snrValues.length ~/ 50) == 0) {
        canvas.drawCircle(Offset(x, y), 2.0, pointPaint);
      }
    }
    
    canvas.drawPath(path, linePaint);
  }

  void _drawLabels(Canvas canvas, Size size, List<double> snrValues) {
    if (snrValues.isEmpty) return;
    
    // Calculate dynamic range for Y-axis labels (must match _drawSNRPlot scaling)
    double minSNR = snrValues.reduce((a, b) => a < b ? a : b);
    double maxSNR = snrValues.reduce((a, b) => a > b ? a : b);
    double snrRange = maxSNR - minSNR;
    
    double snrMin, snrMax;
    if (snrRange < 5.0) {
      double padding = math.max(5.0, (maxSNR + minSNR) / 2 * 0.2);
      snrMin = math.max(0.0, minSNR - padding);
      snrMax = maxSNR + padding;
    } else {
      snrMin = math.max(0.0, minSNR - 2.0);
      snrMax = maxSNR + 2.0;
    }
    double snrRangeForLabels = snrMax - snrMin;
    
    // Frequency labels (X-axis)
    _drawText(canvas, '0', Offset(45, size.height - 25), Colors.white, 12);
    _drawText(canvas, '1000', Offset(size.width / 2 - 20, size.height - 25), Colors.white, 12);
    _drawText(canvas, '2000', Offset(size.width - 50, size.height - 25), Colors.white, 12);
    _drawText(canvas, 'Hz', Offset(size.width / 2 - 8, size.height - 8), Colors.white, 12);
    
    // SNR labels (Y-axis) - dynamic based on actual data range
    int labelCount = 5;
    for (int i = 0; i <= labelCount; i++) {
      double labelSNR = snrMax - (i / labelCount) * snrRangeForLabels;
      double y = 30 + (i / labelCount) * (size.height - 70);
      _drawText(canvas, '${labelSNR.toStringAsFixed(0)}', Offset(25, y - 6), Colors.white, 12);
    }
    _drawText(canvas, 'dB', Offset(20, size.height / 2 - 25), Colors.white, 12);
    
    _drawText(canvas, 'SNR vs Frequency (Real Data)', Offset(size.width / 2 - 100, 12), Colors.white, 14);
    
    // Statistics
    double avgSNR = snrValues.reduce((a, b) => a + b) / snrValues.length;
    
    _drawText(canvas, 'Overall SNR: ${snrDb.toStringAsFixed(1)} dB', Offset(size.width - 150, 30), Colors.orange, 12);
    _drawText(canvas, 'Average: ${avgSNR.toStringAsFixed(1)} dB', Offset(size.width - 150, 50), Colors.blue, 12);
    _drawText(canvas, 'Max: ${maxSNR.toStringAsFixed(1)} dB', Offset(size.width - 150, 70), Colors.green, 12);
    _drawText(canvas, 'Min: ${minSNR.toStringAsFixed(1)} dB', Offset(size.width - 150, 90), Colors.red, 12);
  }

  void _drawText(Canvas canvas, String text, Offset offset, Color color, double fontSize) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.normal),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _DistributionPainter extends CustomPainter {
  final double signalPercentage;
  final double noisePercentage;

  _DistributionPainter({
    required this.signalPercentage,
    required this.noisePercentage,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double barHeight = 30;
    const double spacing = 10;
    final double totalWidth = size.width;

    final signalWidth = totalWidth * (signalPercentage / 100);
    final signalRect = Rect.fromLTWH(0, 0, signalWidth, barHeight);
    final signalPaint = Paint()..color = Colors.blue.withOpacity(0.7);
    canvas.drawRect(signalRect, signalPaint);

    final noiseWidth = totalWidth * (noisePercentage / 100);
    final noiseRect = Rect.fromLTWH(signalWidth + spacing, 0, noiseWidth, barHeight);
    final noisePaint = Paint()..color = Colors.red.withOpacity(0.7);
    canvas.drawRect(noiseRect, noisePaint);

    _drawText(canvas, 'Signal: ${signalPercentage.toStringAsFixed(1)}%', Offset(0, barHeight + 5), Colors.blue);
    _drawText(canvas, 'Noise: ${noisePercentage.toStringAsFixed(1)}%', Offset(signalWidth + spacing, barHeight + 5), Colors.red);
  }

  void _drawText(Canvas canvas, String text, Offset offset, Color color) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class SNRVisualization extends StatelessWidget {
  final double snrDb;
  final String quality;
  final double signalPercentage;
  final double noisePercentage;
  final List<double>? signalSpectrum;
  final List<double>? noiseSpectrum;

  const SNRVisualization({
    Key? key,
    required this.snrDb,
    required this.quality,
    required this.signalPercentage,
    required this.noisePercentage,
    required this.signalSpectrum,
    required this.noiseSpectrum,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSNRMeter(),
        const SizedBox(height: 20),
        _buildSpectrumVisualization(),
        const SizedBox(height: 20),
        _buildDistributionChart(),
      ],
    );
  }

  Widget _buildSNRMeter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Text(
            'SNR Meter',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Container(
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.red,
                  Colors.orange,
                  Colors.yellow,
                  Colors.lightGreen,
                  Colors.green,
                ],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: _calculateSNRPosition(snrDb),
                  child: Container(
                    width: 4,
                    height: 50,
                    color: Colors.white,
                    child: CustomPaint(
                      painter: _TrianglePainter(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0 dB', style: TextStyle(color: Colors.white.withOpacity(0.7))),
              Text('10 dB', style: TextStyle(color: Colors.white.withOpacity(0.7))),
              Text('20 dB', style: TextStyle(color: Colors.white.withOpacity(0.7))),
              Text('30 dB', style: TextStyle(color: Colors.white.withOpacity(0.7))),
              Text('40 dB', style: TextStyle(color: Colors.white.withOpacity(0.7))),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Current SNR: ${snrDb.toStringAsFixed(1)} dB - $quality',
            style: TextStyle(
              color: _getSNRColor(snrDb),
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpectrumVisualization() {
    bool hasRealData = signalSpectrum != null && 
                      signalSpectrum!.isNotEmpty && 
                      noiseSpectrum != null && 
                      noiseSpectrum!.isNotEmpty;
    
    if (!hasRealData) {
      return _buildNoSpectrumData();
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Text(
            'SNR vs Frequency',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Container(
            height: 300,
            width: double.infinity,
            child: CustomPaint(
              painter: _SNRFrequencyPlotPainter(
                signalData: signalSpectrum!,
                noiseData: noiseSpectrum!,
                snrDb: snrDb,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Frequency (Hz) →',
            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
          ),
          Text(
            '↑ SNR (dB)',
            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSpectrumData() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Text(
            'Frequency Spectrum',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Container(
            height: 150,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_graph, color: Colors.white.withOpacity(0.3), size: 40),
                  const SizedBox(height: 8),
                  Text(
                    'Spectrum data not available',
                    style: TextStyle(color: Colors.white.withOpacity(0.5)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDistributionChart() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Text(
            'Signal vs Noise Distribution',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Container(
            height: 120,
            child: CustomPaint(
              painter: _DistributionPainter(
                signalPercentage: signalPercentage,
                noisePercentage: noisePercentage,
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _calculateSNRPosition(double snrDb) {
    double normalized = snrDb.clamp(0.0, 40.0) / 40.0;
    return normalized * 300;
  }

  Color _getSNRColor(double snrDb) {
    if (snrDb >= 30) return Colors.green;
    if (snrDb >= 20) return Colors.lightGreen;
    if (snrDb >= 15) return Colors.yellow;
    if (snrDb >= 10) return Colors.orange;
    return Colors.red;
  }
}

class _TrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(-4, 0)
      ..lineTo(4, 0)
      ..lineTo(0, -8)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}