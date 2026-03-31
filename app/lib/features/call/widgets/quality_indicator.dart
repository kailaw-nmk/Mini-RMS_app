import 'package:flutter/material.dart';
import '../../metrics/media_metrics.dart';

/// Visual quality indicator bar with level text
class QualityIndicator extends StatelessWidget {
  final MediaMetrics metrics;

  const QualityIndicator({super.key, required this.metrics});

  Color _qualityColor(QualityLevel level) {
    switch (level) {
      case QualityLevel.excellent:
        return const Color(0xFF4CAF50);
      case QualityLevel.good:
        return const Color(0xFF2196F3);
      case QualityLevel.fair:
        return const Color(0xFFFFEB3B);
      case QualityLevel.poor:
        return const Color(0xFFFF9800);
      case QualityLevel.critical:
        return const Color(0xFFF44336);
    }
  }

  @override
  Widget build(BuildContext context) {
    final level = metrics.qualityLevel;
    final color = _qualityColor(level);
    final value = metrics.qualityNormalized;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 6,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '品質: ${metrics.qualityDisplayName}',
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
