import 'package:flutter/material.dart';

/// 设计令牌：奶油底 + 墨线描边 + 实色偏移阴影的“软萌新粗野”风格。
abstract final class AppColors {
  static const cream = Color(0xFFFFF4E4);
  static const creamDeep = Color(0xFFF7E6CC);
  static const paper = Color(0xFFFFFFFF);
  static const ink = Color(0xFF221D33);
  static const inkSoft = Color(0xFF6E6680);
  static const inkFaint = Color(0xFFB9B1C4);

  static const mint = Color(0xFF7FDDB8);
  static const lemon = Color(0xFFFFD84D);
  static const coral = Color(0xFFFF8E72);
  static const lavender = Color(0xFFB9A3FF);
  static const sky = Color(0xFF7CCBFF);
  static const pink = Color(0xFFFFA6C9);

  /// 电路板主题深色
  static const board = Color(0xFF2B2541);
  static const boardCell = Color(0xFF362F50);
}

abstract final class AppDims {
  static const border = 2.5;
  static const radius = 18.0;
  static const radiusSm = 12.0;
  static const shadow = 4.0;
}

abstract final class AppTheme {
  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: AppColors.ink,
      onPrimary: AppColors.cream,
      secondary: AppColors.coral,
      surface: AppColors.cream,
      onSurface: AppColors.ink,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.cream,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: const WidgetStatePropertyAll(AppColors.ink),
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.paper
              : AppColors.ink,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.mint
              : AppColors.paper,
        ),
      ),
    );
  }
}

/// 常用文字样式
abstract final class AppText {
  static const _tabular = [FontFeature.tabularFigures()];

  static const display = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w900,
    color: AppColors.ink,
    height: 1.1,
    letterSpacing: -0.5,
  );
  static const title = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w900,
    color: AppColors.ink,
  );
  static const subtitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w800,
    color: AppColors.ink,
  );
  static const body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.inkSoft,
    height: 1.45,
  );
  static const caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: AppColors.inkSoft,
  );
  static const number = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w900,
    color: AppColors.ink,
    fontFeatures: _tabular,
  );
}
