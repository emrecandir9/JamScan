import 'package:flutter/material.dart';

import 'screens/camera_capture_screen.dart';

class JamScanApp extends StatelessWidget {
  const JamScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JamSCAN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const CameraCaptureScreen(),
    );
  }
}
