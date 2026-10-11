import 'package:flutter/material.dart';

/// Colours sampled from the S1-07 wireframes (revision 4).
///
/// The wireframes are greyscale on purpose. Keep every colour in this file
/// so a brand palette can replace them later in one place.
abstract final class AppColors {
  /// Filled buttons, selected states, icons on light backgrounds.
  static const ink = Color(0xFF2D2D2D);

  /// Primary text and the dark result card.
  static const inkDeep = Color(0xFF212121);

  /// Camera viewfinder background.
  static const camera = Color(0xFF505050);

  /// Capture card on the camera page.
  static const cameraChrome = Color(0xFF2A2A2A);

  /// Raised controls on dark surfaces (gallery and library buttons).
  static const cameraControl = Color(0xFF6B6B6B);

  /// Tiles inside the dark result card.
  static const darkTile = Color(0xFF343434);

  /// Taskbar, search fields, info panels.
  static const surfaceMuted = Color(0xFFF2F2F2);

  /// Selected pills and chips, cover placeholders.
  static const surfaceStrong = Color(0xFFE4E4E4);

  static const outline = Color(0xFF7A7A7A);
  static const divider = Color(0xFFDDDDDD);
  static const textSecondary = Color(0xFF5F5F5F);
  static const textMuted = Color(0xFF9A9A9A);
  static const onDarkSecondary = Color(0xFFBDBDBD);
}

/// Spacing and radii used across screens.
abstract final class AppSpacing {
  static const page = 20.0;
  static const cardRadius = 20.0;
  static const sheetRadius = 28.0;
}

abstract final class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.ink).copyWith(
      primary: AppColors.ink,
      onPrimary: Colors.white,
      primaryContainer: AppColors.surfaceStrong,
      onPrimaryContainer: AppColors.inkDeep,
      secondary: AppColors.ink,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.surfaceStrong,
      onSecondaryContainer: AppColors.inkDeep,
      tertiary: AppColors.ink,
      onTertiary: Colors.white,
      error: AppColors.inkDeep,
      onError: Colors.white,
      surface: Colors.white,
      onSurface: AppColors.inkDeep,
      onSurfaceVariant: AppColors.textSecondary,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: AppColors.surfaceMuted,
      surfaceContainer: AppColors.surfaceMuted,
      surfaceContainerHigh: AppColors.surfaceMuted,
      surfaceContainerHighest: AppColors.surfaceStrong,
      outline: AppColors.outline,
      outlineVariant: AppColors.divider,
      inverseSurface: AppColors.ink,
      onInverseSurface: Colors.white,
      surfaceTint: Colors.transparent,
    );

    final base = ThemeData(colorScheme: scheme);
    final text = base.textTheme;

    return base.copyWith(
      scaffoldBackgroundColor: Colors.white,
      textTheme: text.copyWith(
        headlineMedium: text.headlineMedium?.copyWith(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          color: AppColors.inkDeep,
        ),
        headlineSmall: text.headlineSmall?.copyWith(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: AppColors.inkDeep,
        ),
        titleLarge: text.titleLarge?.copyWith(
          fontSize: 21,
          fontWeight: FontWeight.w600,
          color: AppColors.inkDeep,
        ),
        titleMedium: text.titleMedium?.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w500,
          color: AppColors.inkDeep,
        ),
        titleSmall: text.titleSmall?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: AppColors.inkDeep,
        ),
        bodyLarge: text.bodyLarge?.copyWith(
          fontSize: 16,
          color: AppColors.inkDeep,
        ),
        bodyMedium: text.bodyMedium?.copyWith(
          fontSize: 15,
          color: AppColors.textSecondary,
          height: 1.35,
        ),
        bodySmall: text.bodySmall?.copyWith(
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
        labelLarge: text.labelLarge?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.surfaceStrong,
          disabledForegroundColor: AppColors.textMuted,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.inkDeep,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: const StadiumBorder(),
          side: const BorderSide(color: AppColors.ink, width: 1.2),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.inkDeep,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: AppColors.surfaceStrong,
        checkmarkColor: AppColors.inkDeep,
        labelStyle: const TextStyle(
          color: AppColors.inkDeep,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        side: WidgetStateBorderSide.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? const BorderSide(color: AppColors.surfaceStrong)
              : const BorderSide(color: AppColors.outline),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        modalBackgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: AppColors.divider,
        dragHandleSize: Size(40, 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.sheetRadius),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: AppColors.inkDeep,
        ),
        contentTextStyle: const TextStyle(
          fontSize: 16,
          height: 1.4,
          color: AppColors.textSecondary,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 15),
        actionTextColor: Colors.white,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.inkDeep,
        contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.page),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : AppColors.outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.ink
              : AppColors.surfaceStrong,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.ink
              : AppColors.outline,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.ink
              : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: const BorderSide(color: AppColors.ink, width: 1.6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.ink,
        inactiveTrackColor: AppColors.surfaceStrong,
        thumbColor: AppColors.ink,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.inkDeep,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorSize: TabBarIndicatorSize.label,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: AppColors.ink, width: 3),
        ),
        dividerColor: AppColors.divider,
        labelStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 16),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.ink,
        linearTrackColor: AppColors.surfaceStrong,
        circularTrackColor: AppColors.surfaceStrong,
      ),
    );
  }
}

/// Input decorations matching the wireframes.
abstract final class AppInputs {
  /// Outlined field with a floating label (login, notes, list name).
  static InputDecoration outlined(String label, {String? errorText}) {
    return InputDecoration(
      labelText: label,
      errorText: errorText,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.ink),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.ink, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.ink, width: 2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.ink, width: 2),
      ),
    );
  }

  /// Rounded grey search field.
  static InputDecoration search(String hint, {Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textMuted),
      prefixIcon: const Icon(Icons.search, color: AppColors.inkDeep),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: AppColors.surfaceMuted,
      contentPadding: const EdgeInsets.symmetric(vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide.none,
      ),
    );
  }
}
