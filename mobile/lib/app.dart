import 'package:flutter/material.dart';

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
      home: Scaffold(
        appBar: AppBar(title: const Text('JamSCAN')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Welcome to JamSCAN', textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }
}
