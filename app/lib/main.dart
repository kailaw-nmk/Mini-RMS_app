import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ui/call_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: TailCallApp()));
}

class TailCallApp extends StatelessWidget {
  const TailCallApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TailCall',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F3460),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const CallScreen(),
    );
  }
}
