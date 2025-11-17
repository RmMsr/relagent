import 'package:flutter/material.dart';
import 'package:relagent/pages/simple_chat.dart';

import '/config/app_config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Relagent',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.lightBlueAccent),
      ),
      home: const SimpleChatPage(title: 'Simple chart'),
    );
  }
}
