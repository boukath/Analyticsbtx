// lib/widgets/dashboard_bento_grid.dart

import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import 'glass_container.dart';
import 'trend_badge.dart';

class DashboardBentoGrid extends StatelessWidget {
  final bool isDesktop;
  final bool enablePosFeatures;
  final bool isFrench;

  // Metrics
  final int totalIn;
  final int totalOut;
  final int estimatedDwellTimeMins;
  final String peakHour;
  final int occupancy;
  final double currentCa;
  final double compareCa;
  final double conversionRate;
  final double compareConv;
  final double avgBasket;
  final double compareBasket;
  final double upt;
  final double compareUpt;
  final bool isCompareMode;

  const DashboardBentoGrid({
    Key? key,
    required this.isDesktop,
    required this.enablePosFeatures,
    required this.isFrench,
    required this.totalIn,
    required this.totalOut,
    required this.estimatedDwellTimeMins,
    required this.peakHour,
    required this.occupancy,
    required this.currentCa,
    required this.compareCa,
    required this.conversionRate,
    required this.compareConv,
    required this.avgBasket,
    required this.compareBasket,
    required this.upt,
    required this.compareUpt,
    required this.isCompareMode,
  }) : super(key: key);

  Widget _buildBentoCard(BuildContext context, {required String title, required String value, required String unit, required IconData icon, required Color color, Widget? trendWidget}) {
    return GlassContainer(
      padding: const EdgeInsets.all(24),
      borderRadius: 40,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 180),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withOpacity(0.4), width: 1.5),
                    boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 20)],
                  ),
                  child: Icon(icon, color: color, size: 32),
                ),
                if (trendWidget != null) trendWidget,
              ],
            ),
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 13, color: AppTheme.textSecondary(context), fontWeight: FontWeight.w900, letterSpacing: 2.5)),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(value, style: TextStyle(fontSize: 52, fontWeight: FontWeight.w900, color: AppTheme.textPrimary(context), letterSpacing: -2.0)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(unit, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color.withOpacity(0.9))),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> gridItems = [];

    if (!enablePosFeatures) {
      gridItems = [
        _buildBentoCard(context, title: isFrench ? 'TOTAL ENTRÉES' : 'TOTAL IN', value: '$totalIn', unit: isFrench ? 'PERS' : 'PAX', icon: Icons.login_rounded, color: const Color(0xFF38EF7D)),
        _buildBentoCard(context, title: isFrench ? 'TEMPS MOYEN' : 'DWELL TIME', value: '$estimatedDwellTimeMins', unit: 'MIN', icon: Icons.timer_rounded, color: const Color(0xFFFF512F)),
        _buildBentoCard(context, title: isFrench ? 'HEURE DE POINTE' : 'PEAK HOUR', value: peakHour, unit: 'TIME', icon: Icons.access_time_filled_rounded, color: AppTheme.cyan),
        _buildBentoCard(context, title: isFrench ? 'OCCUPATION' : 'OCCUPANCY', value: '$occupancy', unit: isFrench ? 'ACTUEL' : 'NOW', icon: Icons.people_alt_rounded, color: AppTheme.purple),
      ];
    } else {
      gridItems = [
        _buildBentoCard(context, title: isFrench ? 'CHIFFRE D\'AFFAIRES' : 'REVENUE', value: currentCa.toStringAsFixed(0), unit: 'DZD', icon: Icons.account_balance_wallet_rounded, color: const Color(0xFF38EF7D), trendWidget: TrendBadge(current: currentCa, previous: compareCa, isCompareMode: isCompareMode)),
        _buildBentoCard(context, title: isFrench ? 'TAUX DE CONV.' : 'CONV. RATE', value: conversionRate.toStringAsFixed(1), unit: '%', icon: Icons.track_changes_rounded, color: const Color(0xFFFF512F), trendWidget: TrendBadge(current: conversionRate, previous: compareConv, isCompareMode: isCompareMode)),
        _buildBentoCard(context, title: isFrench ? 'PANIER MOYEN' : 'AVG BASKET', value: avgBasket.toStringAsFixed(0), unit: 'DZD', icon: Icons.shopping_bag_rounded, color: AppTheme.cyan, trendWidget: TrendBadge(current: avgBasket, previous: compareBasket, isCompareMode: isCompareMode)),
        _buildBentoCard(context, title: isFrench ? 'INDICE DE VENTE' : 'U.P.T', value: upt.toStringAsFixed(2), unit: 'ART', icon: Icons.layers_rounded, color: AppTheme.purple, trendWidget: TrendBadge(current: upt, previous: compareUpt, isCompareMode: isCompareMode)),
        _buildBentoCard(context, title: isFrench ? 'TEMPS MOYEN' : 'DWELL TIME', value: '$estimatedDwellTimeMins', unit: 'MIN', icon: Icons.timer_rounded, color: const Color(0xFFFF512F)),
      ];
    }

    if (isDesktop) {
      if (gridItems.length == 5) {
        return Row(
          children: [
            Expanded(flex: 2, child: gridItems[0]), const SizedBox(width: 16),
            Expanded(flex: 1, child: gridItems[1]), const SizedBox(width: 16),
            Expanded(flex: 1, child: gridItems[2]), const SizedBox(width: 16),
            Expanded(flex: 1, child: gridItems[3]), const SizedBox(width: 16),
            Expanded(flex: 1, child: gridItems[4]),
          ],
        );
      } else {
        return Row(
          children: [
            Expanded(flex: 2, child: gridItems[0]), const SizedBox(width: 32),
            Expanded(flex: 1, child: gridItems[1]), const SizedBox(width: 32),
            Expanded(flex: 1, child: gridItems[2]), const SizedBox(width: 32),
            Expanded(flex: 1, child: gridItems[3]),
          ],
        );
      }
    } else {
      if (gridItems.length == 5) {
        return Column(
          children: [
            gridItems[0], const SizedBox(height: 24),
            Row(children: [Expanded(child: gridItems[1]), const SizedBox(width: 16), Expanded(child: gridItems[2])]), const SizedBox(height: 24),
            Row(children: [Expanded(child: gridItems[3]), const SizedBox(width: 16), Expanded(child: gridItems[4])]),
          ],
        );
      } else {
        return Column(
          children: [
            gridItems[0], const SizedBox(height: 24),
            Row(children: [Expanded(child: gridItems[1]), const SizedBox(width: 24), Expanded(child: gridItems[2])]), const SizedBox(height: 24),
            gridItems[3],
          ],
        );
      }
    }
  }
}