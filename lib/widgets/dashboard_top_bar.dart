// lib/widgets/dashboard_top_bar.dart

import 'dart:io';
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import 'glass_container.dart';

class DashboardTopBar extends StatelessWidget {
  final bool isFrench;
  final VoidCallback onToggleLanguage;
  final String storeName;
  final String storeLocation;
  final String? storeLogoPath;

  const DashboardTopBar({
    Key? key,
    required this.isFrench,
    required this.onToggleLanguage,
    required this.storeName,
    required this.storeLocation,
    this.storeLogoPath,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      height: 100,
      borderRadius: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Row(
          children: [
            // 🕒 1. Real-Time Clock & Date Stream
            StreamBuilder(
              stream: Stream.periodic(const Duration(seconds: 1)),
              builder: (context, snapshot) {
                final now = DateTime.now();
                const List<String> weekdaysEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
                const List<String> monthsEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                const List<String> weekdaysFr = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];
                const List<String> monthsFr = ['Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'];

                String dayName = isFrench ? weekdaysFr[now.weekday - 1] : weekdaysEn[now.weekday - 1];
                String monthName = isFrench ? monthsFr[now.month - 1] : monthsEn[now.month - 1];
                String hour = now.hour.toString().padLeft(2, '0');
                String minute = now.minute.toString().padLeft(2, '0');

                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("$dayName, ${isFrench ? "${now.day} $monthName" : "$monthName ${now.day}"}", style: TextStyle(color: AppTheme.textSecondary(context), fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 1.0)),
                    const SizedBox(height: 4),
                    Text("$hour:$minute", style: TextStyle(color: AppTheme.textPrimary(context), fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                  ],
                );
              },
            ),
            const Spacer(),

            // 🌍 2. Language Toggle Button
            _buildLanguageToggle(context),
            const SizedBox(width: 40),

            // 🏬 3. Store Name, Location & Logo
            Row(
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(storeLocation.toUpperCase(), style: TextStyle(color: AppTheme.textSecondary(context).withOpacity(0.5), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 2.0)),
                    const SizedBox(height: 2),
                    Text(storeName, style: TextStyle(color: AppTheme.textPrimary(context), fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                  ],
                ),
                const SizedBox(width: 20),
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.glassBorder(context), width: 1.5),
                    image: storeLogoPath != null ? DecorationImage(image: FileImage(File(storeLogoPath!)), fit: BoxFit.cover) : null,
                  ),
                  child: storeLogoPath == null ? const Icon(Icons.storefront_rounded, color: AppTheme.cyan, size: 30) : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Extracted Language Toggle Widget
  Widget _buildLanguageToggle(BuildContext context) {
    return GestureDetector(
      onTap: onToggleLanguage,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 100,
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppTheme.glassTintStart(context),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: AppTheme.glassBorder(context), width: 1),
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutBack,
              alignment: isFrench ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 46,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 2))],
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(child: Center(child: AnimatedDefaultTextStyle(duration: const Duration(milliseconds: 200), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 1, color: !isFrench ? AppTheme.cyan : AppTheme.textSecondary(context).withOpacity(0.5)), child: const Text('EN')))),
                Expanded(child: Center(child: AnimatedDefaultTextStyle(duration: const Duration(milliseconds: 200), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 1, color: isFrench ? AppTheme.cyan : AppTheme.textSecondary(context).withOpacity(0.5)), child: const Text('FR')))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}