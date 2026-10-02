import 'package:flutter/material.dart';
import 'final_terminal_design.dart';

void main() => runApp(const AlgoApp());

class AlgoApp extends StatelessWidget {
  const AlgoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NSE-AI-TERMINAL',
      home: FinalTerminalDesign(),
    );
  }
}
