// lib/widgets/dashboard_header.dart

import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import 'glass_container.dart';

class DashboardHeader extends StatelessWidget {
  final bool isFrench;
  final String? selectedFolderPath;
  final bool isFtpRunning;
  final bool isHttpRunning;
  final bool isCompareMode;
  final bool isFilterActive;
  final String formattedDateString;
  final bool hasData;

  // Callbacks
  final ValueChanged<bool> onCompareModeChanged;
  final VoidCallback onRefreshTap;
  final VoidCallback onPickDateRange;
  final ValueChanged<int> onShiftDate;
  final VoidCallback onShowWorkingHoursDialog;

  const DashboardHeader({
    Key? key,
    required this.isFrench,
    this.selectedFolderPath,
    required this.isFtpRunning,
    required this.isHttpRunning,
    required this.isCompareMode,
    required this.isFilterActive,
    required this.formattedDateString,
    required this.hasData,
    required this.onCompareModeChanged,
    required this.onRefreshTap,
    required this.onPickDateRange,
    required this.onShiftDate,
    required this.onShowWorkingHoursDialog,
  }) : super(key: key);

  Widget _buildServerStatusBadge() {
    bool anyRunning = isFtpRunning || isHttpRunning;
    Color statusColor = anyRunning ? Colors.greenAccent : Colors.redAccent;

    String activeServers = "";
    if (isFtpRunning && isHttpRunning) {
      activeServers = "FTP & HTTP";
    } else if (isFtpRunning) {
      activeServers = "FTP";
    } else if (isHttpRunning) {
      activeServers = "HTTP";
    }

    String statusText;
    if (anyRunning) {
      statusText = isFrench ? 'RÉCEPTION ACTIVE ($activeServers)' : '$activeServers ONLINE';
    } else {
      statusText = isFrench ? 'SERVEURS ARRÊTÉS' : 'SERVERS OFFLINE';
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        border: Border.all(color: statusColor.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: statusColor, blurRadius: 4)]
              )
          ),
          const SizedBox(width: 8),
          Text(statusText, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 16,
      runSpacing: 16,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                isFrench ? 'Vue d\'Ensemble' : 'Command Center',
                style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: AppTheme.textPrimary(context), letterSpacing: -2.0)
            ),
            if (selectedFolderPath != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text('Source: $selectedFolderPath', style: TextStyle(color: AppTheme.textSecondary(context), fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 8),
            _buildServerStatusBadge(),
          ],
        ),

        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasData) ...[
              FilterChip(
                selected: isCompareMode,
                onSelected: onCompareModeChanged,
                label: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(isFrench ? 'Comparer au Préc.' : 'Compare vs Prev', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: isCompareMode ? AppTheme.bgDeep(context) : AppTheme.textPrimary(context))),
                ),
                selectedColor: AppTheme.cyan,
                checkmarkColor: AppTheme.bgDeep(context),
                backgroundColor: AppTheme.glassTintStart(context).withOpacity(0.05),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: isCompareMode ? AppTheme.cyan : AppTheme.glassBorder(context), width: 1.5)),
              ),
              const SizedBox(width: 20),
            ],

            GlassContainer(
              borderRadius: 20,
              isInteractive: true,
              child: IconButton(
                padding: const EdgeInsets.all(12),
                icon: const Icon(Icons.refresh_rounded, color: AppTheme.cyan),
                onPressed: onRefreshTap,
                tooltip: isFrench ? "Actualiser les données" : "Refresh Data",
              ),
            ),
            const SizedBox(width: 16),

            GlassContainer(
              padding: const EdgeInsets.all(6),
              borderRadius: 20,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: Icon(Icons.chevron_left_rounded, color: AppTheme.textSecondary(context)), onPressed: () => onShiftDate(-1)),
                  GestureDetector(
                    onTap: onPickDateRange,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(formattedDateString, style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textPrimary(context), fontSize: 16, letterSpacing: 0.5)),
                    ),
                  ),
                  IconButton(icon: Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary(context)), onPressed: () => onShiftDate(1)),
                ],
              ),
            ),
            const SizedBox(width: 20),

            GlassContainer(
              borderRadius: 20,
              isInteractive: isFilterActive,
              child: IconButton(
                padding: const EdgeInsets.all(12),
                icon: Icon(Icons.tune_rounded, color: isFilterActive ? AppTheme.cyan : AppTheme.textSecondary(context)),
                onPressed: onShowWorkingHoursDialog,
                tooltip: isFrench ? "Heures d'Ouverture" : "Operating Hours",
              ),
            ),
          ],
        )
      ],
    );
  }
}