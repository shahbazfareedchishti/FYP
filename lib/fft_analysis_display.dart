import 'package:flutter/material.dart';

class FFTAnalysisDisplay extends StatefulWidget {
  final Map<String, dynamic>? fftAnalysis;

  const FFTAnalysisDisplay({Key? key, this.fftAnalysis}) : super(key: key);

  @override
  State<FFTAnalysisDisplay> createState() => _FFTAnalysisDisplayState();
}

class _FFTAnalysisDisplayState extends State<FFTAnalysisDisplay> {
  Map<String, dynamic>? get fftAnalysis => widget.fftAnalysis;

  @override
  Widget build(BuildContext context) {
    return _buildPowerSpectrum();
  }

  Widget _buildPowerSpectrum() {
    String? spectrogramImagePath = fftAnalysis?['spectrogram_image_path'];
    bool isApiGenerated = fftAnalysis?['api_generated'] == true;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Power Spectrum',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              if (isApiGenerated) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'API GENERATED',
                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isApiGenerated 
              ? 'Real FFT analysis from server with noise detection'
              : 'Frequency domain representation',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: spectrogramImagePath != null && spectrogramImagePath.isNotEmpty
                ? _buildSpectrogramImage(spectrogramImagePath)
                : _buildFallbackSpectrum(),
          ),
          const SizedBox(height: 8),
          if (isApiGenerated && fftAnalysis?['noise_segments'] != null)
            _buildNoiseSegmentsInfo(),
        ],
      ),
    );
  }

  Widget _buildSpectrogramImage(String imagePath) {
    // If it's a network URL, use Image.network
    if (imagePath.startsWith('http')) {
      return Image.network(
        imagePath,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                  : null,
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return _buildFallbackSpectrum();
        },
      );
    } else {
      // If it's a local file path (unlikely for API), use Image.file
      return _buildFallbackSpectrum();
    }
  }

  Widget _buildNoiseSegmentsInfo() {
    List<dynamic> noiseSegments = fftAnalysis?['noise_segments'] ?? [];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.warning, color: Colors.orange, size: 14),
            const SizedBox(width: 4),
            Text(
              'Noise Detection:',
              style: TextStyle(
                color: Colors.orange,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        if (noiseSegments.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '${noiseSegments.length} noise segment(s) detected',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 11,
            ),
          ),
          // Show first few noise segments
          ...noiseSegments.take(3).map((segment) {
            String text = segment is List && segment.length == 2 
                ? '${segment[0]}s - ${segment[1]}s'
                : segment.toString();
            return Text(
              '• $text',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 10,
              ),
            );
          }).toList(),
        ] else ...[
          Text(
            'No significant noise detected',
            style: TextStyle(
              color: Colors.green,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFallbackSpectrum() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.analytics,
            color: Colors.white.withOpacity(0.5),
            size: 48,
          ),
          const SizedBox(height: 8),
          Text(
            'Spectrogram Preview',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            fftAnalysis?['api_generated'] == true 
                ? 'Loading server analysis...'
                : 'No spectrum data available',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // Additional helper methods for FFT analysis display
  Widget _buildFrequencyPeaks() {
    List<dynamic> peaks = fftAnalysis?['frequency_peaks'] ?? [];
    
    if (peaks.isEmpty) {
      return Container();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Frequency Peaks',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: peaks.take(10).map((peak) {
              String frequency = peak is Map 
                  ? '${peak['frequency']?.toStringAsFixed(1) ?? '0.0'} Hz'
                  : peak.toString();
              return Chip(
                label: Text(
                  frequency,
                  style: const TextStyle(fontSize: 12),
                ),
                backgroundColor: Colors.blue.withOpacity(0.3),
                labelStyle: const TextStyle(color: Colors.white),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Analysis Summary',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _buildSummaryItem('Sampling Rate', '${fftAnalysis?['sampling_rate'] ?? 'N/A'} Hz'),
          _buildSummaryItem('FFT Size', '${fftAnalysis?['fft_size'] ?? 'N/A'}'),
          _buildSummaryItem('Frequency Range', '${fftAnalysis?['frequency_range'] ?? 'N/A'}'),
          if (fftAnalysis?['dominant_frequency'] != null)
            _buildSummaryItem('Dominant Frequency', '${fftAnalysis?['dominant_frequency']} Hz'),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}