import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const AIFindBaseApp());
}

class AIFindBaseApp extends StatelessWidget {
  const AIFindBaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Find Base',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}