import 'package:flutter/material.dart';

/// Palet warna. Diambil dari aplikasi Staff Ops (branch health-device)
/// dengan primary diganti ke biru CaritaHub.
class AppColors {
  AppColors._();

  static const primary = Color(0xFF1155CC);
  static const primarySoft = Color(0xFFE7EEFA);
  static const navyBlue = Color(0xFF153276);
  static const blueDenim = Color(0xFF3A73D7);

  static const background = Color(0xFFF4F5F9);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE1E2EC);
  static const greyBorder = Color(0xFFCCCCCC);
  static const lightGrey = Color(0xFFF4F5F9);

  static const charcoal = Color(0xFF242935);
  static const grey1 = Color(0xFF50597E);
  static const grey3 = Color(0xFFB8BAC6);

  /// Teks sekunder: ≥4,5:1 di putih (5,4:1), background (5,0:1) dan
  /// primarySoft (4,6:1). Dulu #7A7F8F (3,7–4,0:1).
  static const grey4 = Color(0xFF656A79);

  /// Hint/placeholder input: ≥3:1 di lightGrey (3,2:1), tetap jelas lebih
  /// muda dari teks isian (charcoal). grey3 hanya 1,8:1.
  static const hint = Color(0xFF858997);

  static const darkGreen = Color(0xFF1CB27C);
  static const greenSoft = Color(0xFFE4FBEE);
  static const red = Color(0xFFD94948);
  static const redSoft = Color(0xFFFFEEED);
  static const orange = Color(0xFFFFA151);
  static const orangeAction = Color(0xFFB4722C);
  static const orangeActionBg = Color(0xFFFDF3E6);
}

/// Gaya teks. Lexend dibundel di assets/fonts sehingga tidak butuh internet.
class AppText {
  AppText._();

  static const String family = 'Lexend';

  static const TextStyle base = TextStyle(
    fontFamily: family,
    color: AppColors.charcoal,
    height: 1.3,
  );

  static TextStyle w400(double size, [Color? color]) =>
      base.copyWith(fontSize: size, fontWeight: FontWeight.w400, color: color);
  static TextStyle w500(double size, [Color? color]) =>
      base.copyWith(fontSize: size, fontWeight: FontWeight.w500, color: color);
  static TextStyle w600(double size, [Color? color]) =>
      base.copyWith(fontSize: size, fontWeight: FontWeight.w600, color: color);
  static TextStyle w700(double size, [Color? color]) =>
      base.copyWith(fontSize: size, fontWeight: FontWeight.w700, color: color);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    surface: AppColors.surface,
    brightness: Brightness.light,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: AppText.family,
    scaffoldBackgroundColor: AppColors.background,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.charcoal,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: AppText.family,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.charcoal,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: const TextStyle(
          fontFamily: AppText.family,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.charcoal,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        side: const BorderSide(color: AppColors.greyBorder),
        textStyle: const TextStyle(
          fontFamily: AppText.family,
          fontWeight: FontWeight.w500,
          fontSize: 15,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.lightGrey,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      labelStyle: const TextStyle(fontFamily: AppText.family),
      hintStyle: const TextStyle(
        fontFamily: AppText.family,
        color: AppColors.hint,
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
  );
}

/// Breakpoint sederhana: iMin desktop (D4/Falcon/Crane) ≈ lebar,
/// iMin handheld (Swift/M2) ≈ sempit.
extension LayoutX on BuildContext {
  bool get isWide => MediaQuery.sizeOf(this).width >= 900;
  bool get isMedium => MediaQuery.sizeOf(this).width >= 600;
}
