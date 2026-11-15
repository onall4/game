import 'package:flutter/material.dart';

import 'core/app_services.dart';
import 'ui/home/home_page.dart';
import 'ui/theme/app_theme.dart';

class ShiquApp extends StatelessWidget {
  const ShiquApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: MaterialApp(
        title: '拾趣',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        // 游戏界面布局紧凑，限制系统字体放大倍数，避免大字体手机上换行错位
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.15,
          child: child!,
        ),
        home: const HomePage(),
      ),
    );
  }
}
