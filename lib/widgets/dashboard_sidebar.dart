// lib/widgets/dashboard_sidebar.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'glass_container.dart';
import '../core/app_theme.dart'; // 🚀 NEW: Import the theme manager

class DashboardSidebar extends StatelessWidget {
  final bool isFrench;
  final bool enablePosFeatures;
  final bool hasData;
  final String erpPortalLink;
  final bool isIpMismatch;
  final bool isFtpRunning;
  final bool isHttpRunning;
  final String localIp;
  final int ftpPort;
  final int httpPort;

  // Callbacks to trigger actions in the main dashboard
  final VoidCallback onLogoTap;
  final VoidCallback onPosEntryTap;
  final VoidCallback onExportTap;
  final VoidCallback onDeveloperTap;

  const DashboardSidebar({
    Key? key,
    required this.isFrench,
    required this.enablePosFeatures,
    required this.hasData,
    required this.erpPortalLink,
    required this.isIpMismatch,
    required this.isFtpRunning,
    required this.isHttpRunning,
    required this.localIp,
    required this.ftpPort,
    required this.httpPort,
    required this.onLogoTap,
    required this.onPosEntryTap,
    required this.onExportTap,
    required this.onDeveloperTap,
  }) : super(key: key);

  // 🚀 UPDATED: Now requires BuildContext to apply dynamic theme colors
  Widget _buildSidebarItem(BuildContext context, IconData icon, String title, {bool isActive = false, Color? iconColor, Color? textColor, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        // Subtle highlight changes based on Light/Dark mode
        tileColor: isActive ? AppTheme.textPrimary(context).withOpacity(0.08) : Colors.transparent,
        leading: Icon(icon, color: iconColor ?? (isActive ? AppTheme.cyan : AppTheme.textSecondary(context))),
        title: Text(title, style: TextStyle(
          // Text color automatically adapts!
            color: textColor ?? (isActive ? AppTheme.textPrimary(context) : AppTheme.textSecondary(context)),
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
            fontSize: 15
        )),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      width: 280,
      margin: const EdgeInsets.only(right: 2), // Slight separation line
      borderRadius: 0, // Flush against the edge
      child: Column(
        children: [
          const SizedBox(height: 50),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: onLogoTap, // Triggers the secret 7-tap menu!
                  child: Image.asset(
                    'assets/boitex_logo.png',
                    width: 140,
                    height: 140,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(Icons.business, color: AppTheme.cyan, size: 80);
                    },
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'BoitexInfo',
                  textAlign: TextAlign.center,
                  // 🚀 UPDATED: Dynamic text color
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppTheme.textPrimary(context), letterSpacing: -1.0, height: 1.1),
                ),
                const Text(
                  'Analytics',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.cyan, letterSpacing: 4.0),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  _buildSidebarItem(context, Icons.dashboard_rounded, isFrench ? 'Tableau de bord' : 'Dashboard', isActive: true),
                  if (enablePosFeatures)
                    _buildSidebarItem(context, Icons.point_of_sale_rounded, isFrench ? 'Saisie de Caisse' : 'POS Entry', onTap: hasData ? onPosEntryTap : null),
                  _buildSidebarItem(context, Icons.download_rounded, isFrench ? 'Exporter Rapports' : 'Export Reports', onTap: hasData ? onExportTap : null),

                  // ERP Intervention Request Button
                  _buildSidebarItem(
                      context,
                      Icons.build_circle_rounded,
                      isFrench ? 'Demander Intervention' : 'Request Support',
                      onTap: () async {
                        if (erpPortalLink.isNotEmpty) {
                          final Uri url = Uri.parse(erpPortalLink);
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url, mode: LaunchMode.externalApplication);
                          } else {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(isFrench ? "Impossible d'ouvrir le portail ERP." : "Could not open ERP portal."), backgroundColor: Colors.redAccent),
                              );
                            }
                          }
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(isFrench ? "Lien ERP non configuré dans le Profil du Magasin." : "ERP link not configured in Store Profile."), backgroundColor: Colors.orangeAccent),
                          );
                        }
                      }
                  ),

                  Divider(color: AppTheme.textSecondary(context).withOpacity(0.2), height: 40, indent: 24, endIndent: 24),

                  // 🚀 NEW: Theme Toggle Button
                  _buildSidebarItem(
                    context,
                    AppTheme.isDark(context) ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                    AppTheme.isDark(context)
                        ? (isFrench ? 'Mode Clair' : 'Light Mode')
                        : (isFrench ? 'Mode Sombre' : 'Dark Mode'),
                    iconColor: AppTheme.isDark(context) ? Colors.amberAccent : Colors.indigoAccent,
                    textColor: AppTheme.textPrimary(context),
                    onTap: () {
                      AppTheme.toggleTheme(); // This instantly flips the whole app!
                    },
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          if ((isFtpRunning || isHttpRunning) && !isIpMismatch)
            Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.greenAccent.withOpacity(0.2))
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.greenAccent, blurRadius: 8)])),
                    const SizedBox(width: 12),
                    Text(
                        isFtpRunning && isHttpRunning
                            ? (isFrench ? 'FTP & HTTP Actifs' : 'FTP & HTTP Active')
                            : isFtpRunning
                            ? (isFrench ? 'FTP Actif' : 'FTP Active')
                            : (isFrench ? 'HTTP Actif' : 'HTTP Active'),
                        // 🚀 UPDATED: Dynamic color
                        style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textPrimary(context), letterSpacing: 0.5)
                    )
                  ]),
                  const SizedBox(height: 8),
                  if (isFtpRunning)
                    Text('ftp://$localIp:$ftpPort', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary(context), fontWeight: FontWeight.w500)),
                  if (isHttpRunning)
                    Text('http://$localIp:$httpPort', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary(context), fontWeight: FontWeight.w500)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}