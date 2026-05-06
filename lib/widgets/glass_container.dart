// lib/widgets/glass_container.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/app_theme.dart';

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final bool isInteractive;

  const GlassContainer({
    Key? key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius = 24,
    this.isInteractive = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 🚀 High blur radius for that thick, premium frosted glass feel
    const double glassBlur = 40.0;

    return Container(
      width: width,
      height: height,
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: glassBlur, sigmaY: glassBlur),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic, // Smooth, natural Apple-like animation curve
            padding: padding,
            decoration: BoxDecoration(
              // 🚀 3D Specular Highlight using a subtle gradient
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isInteractive && AppTheme.isDark(context)
                    ? [Colors.white.withOpacity(0.15), Colors.white.withOpacity(0.05)]
                    : [AppTheme.glassTintStart(context), AppTheme.glassTintEnd(context)],
              ),
              borderRadius: BorderRadius.circular(borderRadius),
              // Crisp, bright border to catch the virtual light
              border: Border.all(color: AppTheme.glassBorder(context), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.glassShadow(context),
                  blurRadius: 40,
                  spreadRadius: 0,
                  offset: const Offset(0, 10), // Pushes the shadow down slightly for 3D depth
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}