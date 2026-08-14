import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppColors {
  AppColors._();

  static const Color background    = Color(0xFF0D0D0D);
  static const Color primary       = Color(0xFFFFB800);
  static const Color accent        = Color(0xFFFF6B00);
  static const Color surface       = Color(0xFF1A1A1A);
  static const Color surfaceLight  = Color(0xFF2A2A2A);
  static const Color textPrimary   = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF9E9E9E);
  static const Color navBarBg      = Color(0xFF111111);
}

class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary:     AppColors.primary,
        secondary:   AppColors.accent,
        surface:     AppColors.surface,
        onPrimary:   AppColors.background,
        onSecondary: AppColors.textPrimary,
        onSurface:   AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.primary,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor:                    Colors.transparent,
          statusBarIconBrightness:           Brightness.light,
          statusBarBrightness:               Brightness.dark,
          systemNavigationBarColor:          AppColors.navBarBg,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor:      AppColors.navBarBg,
        selectedItemColor:    AppColors.primary,
        unselectedItemColor:  AppColors.textSecondary,
        selectedLabelStyle:   TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        unselectedLabelStyle: TextStyle(fontSize: 11),
        type:                 BottomNavigationBarType.fixed,
        elevation:            8,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w900),
        titleLarge:   TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        bodyMedium:   TextStyle(color: AppColors.textSecondary),
      ),
    );
  }

  static void setSystemUI() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor:                    Colors.transparent,
        statusBarIconBrightness:           Brightness.light,
        statusBarBrightness:               Brightness.dark,
        systemNavigationBarColor:          AppColors.navBarBg,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  }
}