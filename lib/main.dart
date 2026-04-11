import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const PockyhApp());
}

class PockyhApp extends StatelessWidget {
  const PockyhApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pockyh',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const LoginScreen(),
    );
  }
}