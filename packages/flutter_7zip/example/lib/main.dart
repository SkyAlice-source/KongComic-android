import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_7zip/flutter_7zip.dart';
void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('flutter_7zip example app'),
        ),
        body: Center(child: FilledButton(onPressed: _extract, child: Text("Extract test.7z")),)
      ),
    );
  }

  void _extract() async {
    final archive = SZArchive.open('test.7z');
    var outDir = Directory("test");
    if (outDir.existsSync()) {
      outDir.deleteSync(recursive: true);
    }
    for (int i=0; i<archive.numFiles; i++) {
      final file = archive.getFile(i);
      if (file.isDirectory) {
        Directory("test/${file.name}").createSync(recursive: true);
      } else {
        archive.extractToFile(i, "test/${file.name}");
      }
    }
    archive.dispose();
  }
}
