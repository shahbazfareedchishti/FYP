import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

// A standalone widget that visualizes SNR data over time.
class SNRTimeChart extends StatelessWidget {
  final List<double> snrValues;
  final List<double> timeBins;

  const SNRTimeChart({
    Key? key,
    required this.snrValues,
    required this.timeBins,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    bool hasData = snrValues.isNotEmpty && 
                   timeBins.isNotEmpty && 
                   snrValues.length == timeBins.length;

    return Container(
      height: 300,
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "Signal-to-Noise Ratio Over Time",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: hasData
                ? CustomPaint(
                    painter: _SNRTimePlotPainter(
                      snrValues: snrValues,
                      timeBins: timeBins,
                    ),
                  )
                : const Center(
                    child: Text(
                      'No time-series data available.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// CustomPainter to draw the SNR vs. Time plot.
class _SNRTimePlotPainter extends CustomPainter {
  final List<double> snrValues;
  final List<double> timeBins;

  _SNRTimePlotPainter({required this.snrValues, required this.timeBins});

  @override
  void paint(Canvas canvas, Size size) {
    if (snrValues.length < 2) {
      _drawNoDataMessage(canvas, size);
      return;
    }

    final gridPaint = Paint()..color = Colors.white.withOpacity(0.2)..style = PaintingStyle.stroke..strokeWidth = 0.5;
    final axisPaint = Paint()..color = Colors.white.withOpacity(0.7)..style = PaintingStyle.stroke..strokeWidth = 1.0;
    final linePaint = Paint()..color = Colors.amber..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeCap = StrokeCap.round;
    final pointPaint = Paint()..color = Colors.amber.withOpacity(0.8)..style = PaintingStyle.fill;
    final maxLinePaint = Paint()..color = Colors.red.withOpacity(0.6)..style = PaintingStyle.stroke..strokeWidth = 1.0;
    final fillPaint = Paint()..color = Colors.amber.withOpacity(0.15)..style = PaintingStyle.fill;

    const double leftPadding = 45, bottomPadding = 30, topPadding = 20, rightPadding = 10;
    final double graphWidth = size.width - leftPadding - rightPadding;
    final double graphHeight = size.height - bottomPadding - topPadding;

    // **FIX 1: Dynamic Y-axis range based on actual data**
    final double minSnr = _calculateMinSnr();
    final double maxSnr = _calculateMaxSnr();
    final double snrRange = maxSnr - minSnr;
    
    // **FIX 2: Handle edge case where all values are the same**
    final double effectiveRange = snrRange == 0 ? 10.0 : snrRange;

    // **FIX 3: Use actual time range from data**
    final double maxTime = timeBins.isNotEmpty ? timeBins.last : 1.0;
    final double minTime = timeBins.isNotEmpty ? timeBins.first : 0.0;
    final double timeRange = maxTime - minTime;

    // Draw axes
    canvas.drawLine(Offset(leftPadding, topPadding), Offset(leftPadding, topPadding + graphHeight), axisPaint);
    canvas.drawLine(Offset(leftPadding, topPadding + graphHeight), Offset(leftPadding + graphWidth, topPadding + graphHeight), axisPaint);

    // **FIX 4: Dynamic Y-axis labels based on data range**
    const int yLabelCount = 5;
    for (int i = 0; i <= yLabelCount; i++) {
      double y = topPadding + graphHeight - (i / yLabelCount.toDouble()) * graphHeight;
      double snrVal = minSnr + (i / yLabelCount.toDouble()) * effectiveRange;
      _drawText(canvas, snrVal.toStringAsFixed(snrVal < 10 ? 1 : 0), 
                Offset(leftPadding - 42, y - 8), Colors.white70, 10, TextAlign.right);
      if (i > 0) canvas.drawLine(Offset(leftPadding, y), Offset(leftPadding + graphWidth, y), gridPaint);
    }
    _drawText(canvas, "SNR (dB)", Offset(leftPadding - 35, topPadding - 20), Colors.white.withOpacity(0.9), 10, TextAlign.center);

    // **FIX 5: Dynamic X-axis labels based on actual time range**
    const int xLabelCount = 4;
    for (int i = 0; i <= xLabelCount; i++) {
      double timeValue = minTime + (timeRange * (i / xLabelCount.toDouble()));
      double x = leftPadding + (i / xLabelCount.toDouble()) * graphWidth;
      _drawText(canvas, '${timeValue.toStringAsFixed(1)}s', 
                Offset(x - 10, topPadding + graphHeight + 8), Colors.white70, 10, TextAlign.center);
    }
    _drawText(canvas, "Time (s)", Offset(leftPadding + graphWidth / 2 - 15, topPadding + graphHeight + 20), 
              Colors.white.withOpacity(0.9), 10, TextAlign.center);

    // **FIX 6: Draw API's actual max measurable SNR (60dB from Python code)**
    final double apiMaxSnr = 60.0;
    if (apiMaxSnr <= maxSnr) {
      double maxValY = topPadding + graphHeight - ((apiMaxSnr - minSnr) / effectiveRange) * graphHeight;
      maxValY = maxValY.clamp(topPadding, topPadding + graphHeight);
      _drawDashedLine(canvas, Offset(leftPadding, maxValY), Offset(leftPadding + graphWidth, maxValY), maxLinePaint);
      _drawText(canvas, "Max Reading (60dB)", Offset(leftPadding + 5, maxValY - 18), Colors.red.withOpacity(0.8), 10, TextAlign.left);
    }

    final path = Path();
    final fillPath = Path();
    final List<Offset> points = [];

    // **FIX 7: Handle irregular time data and create smooth path**
    for (int i = 0; i < snrValues.length; i++) {
      // Clamp SNR to reasonable range but preserve original for display
      final clampedSnr = snrValues[i].clamp(minSnr, math.min(maxSnr, apiMaxSnr));
      
      // Calculate position based on actual time values
      double x = leftPadding + ((timeBins[i] - minTime) / timeRange) * graphWidth;
      double y = topPadding + graphHeight - ((clampedSnr - minSnr) / effectiveRange) * graphHeight;
      y = y.clamp(topPadding, topPadding + graphHeight);

      final point = Offset(x, y);
      points.add(point);
      
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
        fillPath.moveTo(point.dx, topPadding + graphHeight);
        fillPath.lineTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
        fillPath.lineTo(point.dx, point.dy);
      }
    }

    // **FIX 8: Close the fill path**
    if (points.isNotEmpty) {
      fillPath.lineTo(points.last.dx, topPadding + graphHeight);
      fillPath.close();
    }

    // Draw filled area under curve
    canvas.drawPath(fillPath, fillPaint);
    // Draw main line
    canvas.drawPath(path, linePaint);

    // **FIX 9: Draw circles at each data point (but not too many if data is dense)**
    final bool showPoints = points.length <= 20; // Only show points for sparse data
    if (showPoints) {
      for (final point in points) {
        canvas.drawCircle(point, 3.0, pointPaint);
      }
    }

    // **FIX 10: Display data statistics**
    _drawDataStats(canvas, size, minSnr, maxSnr, points.length);
  }

  double _calculateMinSnr() {
    if (snrValues.isEmpty) return 0.0;
    double min = snrValues.reduce(math.min);
    // Ensure some padding for visual clarity
    return math.max(0.0, min - 5.0);
  }

  double _calculateMaxSnr() {
    if (snrValues.isEmpty) return 55.0;
    double max = snrValues.reduce(math.max);
    // Add padding and cap at API maximum
    return math.min(65.0, max + 5.0);
  }

  void _drawDataStats(Canvas canvas, Size size, double minSnr, double maxSnr, int pointCount) {
    final stats = [
      "Points: $pointCount",
      "Range: ${minSnr.toStringAsFixed(1)} - ${maxSnr.toStringAsFixed(1)} dB",
      "Avg: ${_calculateAverage().toStringAsFixed(1)} dB"
    ];
    
    double yPos = 25;
    for (final stat in stats) {
      _drawText(canvas, stat, Offset(size.width - 120, yPos), Colors.white70, 10, TextAlign.left);
      yPos += 15;
    }
  }

  double _calculateAverage() {
    if (snrValues.isEmpty) return 0.0;
    return snrValues.reduce((a, b) => a + b) / snrValues.length;
  }

  void _drawNoDataMessage(Canvas canvas, Size size) {
    _drawText(canvas, "Insufficient data points", 
              Offset(size.width / 2 - 60, size.height / 2 - 10), 
              Colors.white70, 12, TextAlign.center);
  }

  // Helper to draw a dashed line
  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const double dashWidth = 4.0, dashSpace = 4.0;
    double startX = start.dx;
    final double endX = end.dx;

    while (startX < endX) {
      canvas.drawLine(Offset(startX, start.dy), Offset(math.min(startX + dashWidth, endX), start.dy), paint);
      startX += dashWidth + dashSpace;
    }
  }

  void _drawText(Canvas canvas, String text, Offset offset, Color color, double fontSize, TextAlign align) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: fontSize)),
      textAlign: align,
      textDirection: ui.TextDirection.ltr
    )..layout(minWidth: 0, maxWidth: 200);
    textPainter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _SNRTimePlotPainter oldDelegate) {
    return oldDelegate.snrValues != snrValues || oldDelegate.timeBins != timeBins;
  }
}