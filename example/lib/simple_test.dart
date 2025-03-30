import 'package:flutter/material.dart';
import 'package:gcode_view/gcode_view.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Test G0 X114.655 Y41.819',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const TestPage(),
    );
  }
}

class TestPage extends StatelessWidget {
  const TestPage({super.key});

  // G-code spécifique avec le déplacement G0 X114.655 Y41.819
  final String gcode = """
G0 X0 Y0 Z0
G0 X114.655 Y41.819 Z15
G0 Z5
G1 Z-15 F500
G1 X120 Y40 F800
G1 X130 Y50
G1 X130 Y70
G1 X120 Y80
G1 X80 Y80
G1 X70 Y70
G1 X70 Y50
G1 X80 Y40
G1 X114.655 Y41.819
G0 Z15
G0 X0 Y0 Z15
  """;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test G0 X114.655 Y41.819'),
        backgroundColor: Colors.blue.shade700,
      ),
      body: Column(
        children: [
          Expanded(
            child: GcodeViewer(
              gcode: gcode,
              cutColor: Colors.blue,
              travelColor: Colors.red.withOpacity(0.9),
              pathThickness: 4.0,
              showGrid: true,
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade200,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Problème testé:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'Vérifier que le déplacement G0 X114.655 Y41.819 est visible en rouge',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      color: Colors.red.withOpacity(0.9),
                      margin: const EdgeInsets.only(right: 8),
                    ),
                    const Text(
                      'G0 - Déplacements rapides (ROUGE)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      color: Colors.blue,
                      margin: const EdgeInsets.only(right: 8),
                    ),
                    const Text(
                      'G1 - Déplacements de coupe (BLEU)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
