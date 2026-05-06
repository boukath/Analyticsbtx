// lib/widgets/trend_badge.dart
import 'package:flutter/material.dart';

class TrendBadge extends StatelessWidget {
  final num current;
  final num previous;
  final bool isCompareMode;

  const TrendBadge({
    Key? key,
    required this.current,
    required this.previous,
    required this.isCompareMode,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!isCompareMode) return const SizedBox.shrink();
    if (previous == 0) return const SizedBox.shrink();

    double change = ((current - previous) / previous) * 100;
    bool isPositive = change >= 0;

    return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: isPositive ? Colors.greenAccent.withOpacity(0.15) : Colors.redAccent.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isPositive ? Colors.greenAccent.withOpacity(0.3) : Colors.redAccent.withOpacity(0.3))
        ),
        child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isPositive ? Icons.trending_up : Icons.trending_down, size: 14, color: isPositive ? Colors.greenAccent : Colors.redAccent),
              const SizedBox(width: 6),
              Text(
                  '${change.abs().toStringAsFixed(1)}%',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: isPositive ? Colors.greenAccent : Colors.redAccent)
              ),
            ]
        )
    );
  }
}