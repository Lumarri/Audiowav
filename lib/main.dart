import 'package:flutter/material.dart';

import 'audio_controller.dart';
import 'studio_screen.dart';

void main() => runApp(const AudiowavApp());

class AudiowavApp extends StatelessWidget {
  const AudiowavApp({super.key, this.controller});
  final AudioController? controller;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Audiowav',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFB8F76A),
        brightness: Brightness.dark,
        primary: const Color(0xFFB8F76A),
        surface: const Color(0xFF171C23),
      ),
      scaffoldBackgroundColor: const Color(0xFF0C1015),
      useMaterial3: true,
      sliderTheme: const SliderThemeData(trackHeight: 3),
    ),
    home: StudioScreen(controller: controller),
  );
}
